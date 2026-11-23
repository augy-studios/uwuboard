// The app's state and what can be done to it, ported from main-site/script.js: the session (or
// the guest), the boards, the one that's open, and every change to them. Each change goes where
// the site's does: to the API signed in, to this device as a guest, and on to a sync session
// when one's running.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api.dart';
import '../data/board.dart';
import '../data/images.dart';
import '../data/store.dart';
import '../data/timeline_logic.dart' as timeline_logic;
import 'nav.dart';

const keySession = 'uwuboard_session';
const keyGuestBoards = 'kanbanflow_guest_boards';

/// The app's own: the signed-in boards as last fetched, for opening offline. The site's service
/// worker keeps the same thing as its copy of /api/boards/list.
const keyBoardsCache = 'app.boardsCache';

/// The one place the app keeps who is signed in and their boards. Widgets listen to it and
/// rebuild when [notifyListeners] is called after a change.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  /// { token, userId }, or null as a guest or signed out.
  Json? session;
  String username = '';
  String displayName = '';
  bool hasAvatar = false;
  bool isGuest = false;

  List<Json> boards = [];
  String? activeBoardId;

  /// True once the boards have loaded: the tours wait for it.
  bool boardsReady = false;

  /// The open board shown as the other view, just for a tour. Never saved.
  String? viewOverride;

  /// Whether the app is on screen (signed in or as a guest), rather than the sign-in screen.
  bool shown = false;

  /// Bumped when the avatar changes, so widgets showing it fetch again.
  int avatarVersion = 0;

  /// A sync code from a link that opened the app before anyone was signed in.
  String? pendingSyncCode;

  /// What's on screen changed (a board opened, a view switched): the tours listen.
  final StreamController<void> _pageChanges = StreamController<void>.broadcast();
  Stream<void> get pageChanges {
    return _pageChanges.stream;
  }

  void pageChanged() {
    _pageChanges.add(null);
  }

  /// This device's boards changed: a running sync tells the other device.
  void Function()? onBoardsChanged;

  /// Tells a running sync that this device's boards changed, if one is listening.
  void _notifyBoardsChanged() {
    final callback = onBoardsChanged;
    if (callback != null) {
      callback();
    }
  }

  /// For tests.
  @visibleForTesting
  void reset() {
    session = null;
    displayName = '';
    username = '';
    shown = false;
    boardsReady = false;
    isGuest = false;
    hasAvatar = false;
    boards = [];
    pendingSyncCode = null;
    viewOverride = null;
    activeBoardId = null;
  }

  bool get signedIn {
    return !isGuest && session != null;
  }

  String get shownName {
    if (isGuest) {
      return 'Guest';
    } else if (displayName.isEmpty) {
      return username;
    } else {
      return displayName;
    }
  }

  String get role {
    if (isGuest) {
      return 'Guest session';
    } else {
      return 'Signed in';
    }
  }

  /// The letter shown in the round avatar when there is no picture: 'G' for a guest.
  String get initial {
    if (signedIn) {
      if (shownName.isEmpty) {
        return 'U';
      } else {
        return shownName[0].toUpperCase();
      }
    } else {
      return 'G';
    }
  }

  Json? get activeBoard {
    for (final board in boards) {
      if (board['id'] == activeBoardId) {
        return board;
      }
    }
    return null;
  }

  /// The same board either way: its columns are a timeline's phases and its cards the tasks.
  bool isTimeline(Json? board) {
    if (board == null) {
      return false;
    }
    String? override;
    if (identical(board, activeBoard)) {
      override = viewOverride;
    } else {
      override = null;
    }
    Object? shownView;
    if (override != null) {
      shownView = override;
    } else {
      shownView = board['view'];
    }
    return shownView == 'timeline';
  }

  /* ---- storage ---- */

  void saveGuest() {
    if (!isGuest) {
      return;
    }
    Store.instance.put(keyGuestBoards, jsonEncode(boards));
    _notifyBoardsChanged();
  }

  List<Json> _loadGuest() {
    try {
      String savedText;
      final stored = Store.instance.get(keyGuestBoards);
      if (stored != null) {
        savedText = stored;
      } else {
        savedText = '[]';
      }
      return boardsFromJson(jsonDecode(savedText));
    } catch (error) {
      return [];
    }
  }

  /// What's kept of a session on this device: no avatar address, just whether there is one.
  void _saveSession([Json changes = const {}]) {
    Json saved;
    try {
      String savedText;
      final stored = Store.instance.get(keySession);
      if (stored != null) {
        savedText = stored;
      } else {
        savedText = '{}';
      }
      saved = Map<String, dynamic>.from(jsonDecode(savedText) as Map);
    } catch (error) {
      saved = {};
    }
    saved.remove('avatarUrl');
    Store.instance.put(keySession, jsonEncode({...saved, ...changes}));
  }

  void _cacheBoards() {
    if (signedIn) {
      Store.instance.put(keyBoardsCache, jsonEncode(boards));
    }
  }

  /* ---- signing in and out ---- */

  /// Takes on a session: remembers it on this device, gives the API its token and shows the app.
  void _setSession(Json newSession, String user, String? shownAs, bool avatarExists) {
    session = newSession;
    username = user;
    hasAvatar = avatarExists;
    isGuest = false;
    Api.token = newSession['token'] as String?;
    if (shownAs == null || shownAs.isEmpty) {
      displayName = user;
    } else {
      displayName = shownAs;
    }
    Store.instance.put(keySession, jsonEncode({'session': newSession, 'username': user, 'displayName': displayName, 'hasAvatar': avatarExists}));
    shown = true;
    notifyListeners();
    pageChanged();
  }

  /// The username saved with a session, as text ('' when there is none).
  static String _usernameFrom(Json parsed) {
    final savedUsername = parsed['username'];
    if (savedUsername != null) {
      return '$savedUsername';
    } else {
      return '';
    }
  }

  /// The session saved on this device, if it still works. Offline, the boards as last
  /// fetched; a session the server refuses is forgotten.
  Future<void> restore() async {
    final saved = Store.instance.get(keySession);
    if (saved == null) {
      return;
    }
    Json parsed;
    try {
      parsed = Map<String, dynamic>.from(jsonDecode(saved) as Map);
    } catch (error) {
      Store.instance.remove(keySession);
      return;
    }
    final savedSession = parsed['session'];
    if (savedSession is! Map || savedSession['token'] is! String) {
      Store.instance.remove(keySession);
      return;
    }
    final restoredSession = Map<String, dynamic>.from(savedSession);
    // A session saved before images were hidden kept the avatar's address; only whether there
    // is one matters now.
    final bool avatar;
    if (parsed['hasAvatar'] is bool) {
      avatar = parsed['hasAvatar'] as bool;
    } else {
      avatar = parsed['avatarUrl'] != null && parsed['avatarUrl'] != '';
    }
    Api.token = restoredSession['token'] as String;
    try {
      final data = await Api.call('GET', '/boards/list');
      _setSession(restoredSession, _usernameFrom(parsed), parsed['displayName'] as String?, avatar);
      boards = boardsFromJson(data['boards']);
      _cacheBoards();
    } on ApiError catch (error) {
      if (!error.offline) {
        Api.token = null;
        Store.instance.remove(keySession);
        Store.instance.remove(keyBoardsCache);
        return;
      }
      // No network: what was here last time, and the offline bar says why.
      _setSession(restoredSession, _usernameFrom(parsed), parsed['displayName'] as String?, avatar);
      try {
        String cachedText;
        final cached = Store.instance.get(keyBoardsCache);
        if (cached != null) {
          cachedText = cached;
        } else {
          cachedText = '[]';
        }
        boards = boardsFromJson(jsonDecode(cachedText));
      } catch (error) {
        boards = [];
      }
      _reloadWhenOnline();
    }
    boardsReady = true;
    if (boards.isNotEmpty) {
      selectBoard('${boards.first['id']}');
    }
    notifyListeners();
  }

  /// Waits for the network to come back, once, then fetches the boards again.
  void _reloadWhenOnline() {
    void listener() {
      if (Api.offline.value) {
        return;
      }
      Api.offline.removeListener(listener);
      if (signedIn) {
        loadUserBoards();
      }
    }

    Api.offline.addListener(listener);
  }

  /// Returns what went wrong, or null.
  Future<String?> login(String user, String password) async {
    if (user.isEmpty || password.isEmpty) {
      return 'Please fill in all fields.';
    }
    try {
      final data = await Api.call('POST', '/auth/login', {'username': user, 'password': password});
      _setSession(Map<String, dynamic>.from(data['session'] as Map), '${data['username']}', data['displayName'] as String?, data['hasAvatar'] == true);
      await loadUserBoards();
      return null;
    } on ApiError catch (error) {
      if (error.offline) {
        return 'No connection. Check your internet and try again.';
      } else {
        return error.message;
      }
    }
  }

  /// Makes a new account and signs in to it. Returns what went wrong, or null.
  Future<String?> register(String user, String email, String password) async {
    if (user.isEmpty || email.isEmpty || password.isEmpty) {
      return 'Please fill in all fields.';
    }
    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    try {
      final data = await Api.call('POST', '/auth/register', {'username': user, 'email': email, 'password': password});
      _setSession(Map<String, dynamic>.from(data['session'] as Map), '${data['username']}', data['displayName'] as String?, false);
      await loadUserBoards();
      return null;
    } on ApiError catch (error) {
      if (error.offline) {
        return 'No connection. Check your internet and try again.';
      } else {
        return error.message;
      }
    }
  }

  void setGuest() {
    session = null;
    Api.token = null;
    isGuest = true;
    hasAvatar = false;
    boards = _loadGuest();
    boardsReady = true;
    shown = true;
    activeBoardId = null;
    if (boards.isNotEmpty) {
      selectBoard('${boards.first['id']}');
    } else {
      notifyListeners();
      pageChanged();
    }
  }

  /// Run before the state goes, by whatever belongs to the account: a sync session, a tour.
  final List<void Function()> onLogout = [];

  /// Signs out: tells the server (without waiting), runs [onLogout], and forgets the account's
  /// session, boards and images on this device.
  void logout() {
    Object? token;
    final currentSession = session;
    if (currentSession != null) {
      token = currentSession['token'];
    }
    if (signedIn && token is String) {
      Api.client.post(Api.uri('/auth/logout'), headers: {'Authorization': 'Bearer $token'}).then<void>((response) {}, onError: (Object error) {});
    }
    for (final callback in List.of(onLogout)) {
      callback();
    }
    Store.instance.remove(keySession);
    Store.instance.remove(keyBoardsCache);
    session = null;
    Api.token = null;
    isGuest = false;
    hasAvatar = false;
    boards = [];
    boardsReady = false;
    activeBoardId = null;
    viewOverride = null;
    shown = false;
    // Nothing of this account is left for the next.
    ImageStore.clear();
    notifyListeners();
    pageChanged();
  }

  /* ---- boards ---- */

  Future<void> loadUserBoards() async {
    if (isGuest) {
      return;
    }
    try {
      final data = await Api.call('GET', '/boards/list');
      boards = boardsFromJson(data['boards']);
      _cacheBoards();
      final keep = activeBoard != null;
      if (!keep && boards.isNotEmpty) {
        selectBoard('${boards.first['id']}');
      }
      _notifyBoardsChanged();
    } on ApiError {
      AppNavigation.toast('Failed to load boards', error: true);
    }
    boardsReady = true;
    notifyListeners();
  }

  void selectBoard(String id) {
    final exists = boards.any((board) {
      return board['id'] == id;
    });
    if (!exists) {
      return;
    }
    activeBoardId = id;
    viewOverride = null;
    notifyListeners();
    pageChanged();
  }

  /// Saves a board where this session keeps them.
  Future<void> persistBoard(Json board) async {
    notifyListeners();
    if (isGuest) {
      saveGuest();
      return;
    }
    _cacheBoards();
    try {
      await Api.call('PUT', '/boards/update', {'board': board});
    } on ApiError {
      AppNavigation.toast('Sync error', error: true);
    }
    _notifyBoardsChanged();
  }

  Future<void> createBoard(String name, String type, List<String> columns) async {
    final board = newBoard(name, type, columns);
    boards.add(board);
    if (!isGuest) {
      _cacheBoards();
      try {
        await Api.call('POST', '/boards/create', {'board': board});
      } on ApiError {
        AppNavigation.toast('Save error', error: true);
      }
      _notifyBoardsChanged();
    } else {
      saveGuest();
    }
    selectBoard('${board['id']}');
    AppNavigation.toast('Board "$name" created');
  }

  void renameBoard(Json board, String name) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return;
    }
    board['name'] = trimmedName;
    touch(board);
    persistBoard(board);
  }

  /// Deletes a board (from the server when signed in), then opens the first one left.
  Future<void> deleteBoard(Json board) async {
    if (!isGuest) {
      try {
        await Api.call('DELETE', '/boards/delete', {'boardId': board['id']});
      } on ApiError {
        AppNavigation.toast('Delete error', error: true);
      }
    }
    boards.removeWhere((existingBoard) {
      return existingBoard['id'] == board['id'];
    });
    activeBoardId = null;
    viewOverride = null;
    saveGuest();
    if (!isGuest) {
      _cacheBoards();
      _notifyBoardsChanged();
    }
    AppNavigation.toast('Board deleted');
    if (boards.isNotEmpty) {
      selectBoard('${boards.first['id']}');
    } else {
      notifyListeners();
      pageChanged();
    }
  }

  /// Kanban to Timeline or back, for good.
  void toggleView() {
    final board = activeBoard;
    if (board == null) {
      return;
    }
    if (isTimeline(board)) {
      board['view'] = 'kanban';
    } else {
      board['view'] = 'timeline';
    }
    viewOverride = null;
    touch(board);
    persistBoard(board);
    pageChanged();
    if (isTimeline(board)) {
      AppNavigation.toast('Showing as a timeline');
    } else {
      AppNavigation.toast('Showing as a kanban board');
    }
  }

  /// `view` for the open board, just for now; its own view clears it.
  void setViewOverride(String? view) {
    final board = activeBoard;
    if (board == null) {
      return;
    }
    final String own;
    if (board['view'] == 'timeline') {
      own = 'timeline';
    } else {
      own = 'kanban';
    }
    if (view != null && view != own) {
      viewOverride = view;
    } else {
      viewOverride = null;
    }
    notifyListeners();
    pageChanged();
  }

  /// Boards that came in from another device: the list and the board on show follow.
  void boardsChanged(List<Json> changed) {
    if (activeBoard == null && boards.isNotEmpty) {
      selectBoard('${boards.first['id']}');
      return;
    }
    notifyListeners();
  }

  /* ---- columns and cards ---- */

  void addColumn(Json board, String name) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return;
    }
    (board['columns'] as List).add(newColumn(trimmedName));
    persistBoard(board);
  }

  void renameColumn(Json board, Json column, String name) {
    final trimmedName = name.trim();
    if (trimmedName.isNotEmpty) {
      column['name'] = trimmedName;
    }
    touch(column);
    persistBoard(board);
  }

  void deleteColumn(Json board, String columnId) {
    final timeline = isTimeline(board);
    (board['columns'] as List).removeWhere((column) {
      return column is Map && column['id'] == columnId;
    });
    timeline_logic.pruneDependencies(board);
    persistBoard(board);
    if (timeline) {
      AppNavigation.toast('Phase deleted');
    } else {
      AppNavigation.toast('Column deleted');
    }
  }

  /// Columns in a new order, by id.
  void reorderColumns(Json board, List<String> order) {
    final columns = columnsOf(board);
    final sorted = <dynamic>[
      for (final id in order)
        ...columns.where((column) {
          return column['id'] == id;
        }),
      ...columns.where((column) {
        return !order.contains(column['id']);
      }),
    ];
    board['columns'] = sorted;
    persistBoard(board);
    AppNavigation.toast('Columns reordered');
  }

  Json? addCard(Json board, String columnId, String title) {
    final column = findColumn(board, columnId);
    final trimmedTitle = title.trim();
    if (column == null || trimmedTitle.isEmpty) {
      return null;
    }
    final card = newCard(trimmedTitle);
    (column['cards'] as List).add(card);
    // Added straight into Done: done today.
    timeline_logic.stampCompleted(board, card, null, columnId);
    persistBoard(board);
    return card;
  }

  /// Moves a card to `toColumnId`, before the card `beforeId` or at the end. Where a card is
  /// counts as a change to it, so a move made here wins over an older copy.
  ///
  /// Into the last column (Done) it's completed today; out of it, not completed any more
  /// ([timeline_logic.stampCompleted]), unless `keepCompleted`: a date was just typed in for it.
  void moveCard(Json board, String cardId, String toColumnId, {String? beforeId, bool keepCompleted = false}) {
    final sourceColumn = columnOfCard(board, cardId);
    final targetColumn = findColumn(board, toColumnId);
    if (sourceColumn == null || targetColumn == null || beforeId == cardId) {
      return;
    }
    final sourceCards = sourceColumn['cards'] as List;
    final cardIndex = sourceCards.indexWhere((card) {
      return card is Map && card['id'] == cardId;
    });
    if (cardIndex < 0) {
      return;
    }
    final card = sourceCards.removeAt(cardIndex) as Map;
    if (!identical(sourceColumn, targetColumn)) {
      card['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    }
    if (!keepCompleted) {
      timeline_logic.stampCompleted(board, card, '${sourceColumn['id']}', toColumnId);
    }
    final targetCards = targetColumn['cards'] as List;
    int insertIndex;
    if (beforeId == null) {
      insertIndex = -1;
    } else {
      insertIndex = targetCards.indexWhere((otherCard) {
        return otherCard is Map && otherCard['id'] == beforeId;
      });
    }
    if (insertIndex < 0) {
      targetCards.add(card);
    } else {
      targetCards.insert(insertIndex, card);
    }
    persistBoard(board);
  }

  void deleteCard(Json board, String cardId) {
    final column = columnOfCard(board, cardId);
    if (column == null) {
      return;
    }
    (column['cards'] as List).removeWhere((card) {
      return card is Map && card['id'] == cardId;
    });
    timeline_logic.pruneDependencies(board);
    persistBoard(board);
    AppNavigation.toast('Card deleted');
  }

  /* ---- export and import ---- */

  /// The file carries each image's bytes as a data URL, so it opens anywhere: as a guest, or in
  /// another account. It names no storage address. Returns the JSON and how many images
  /// wouldn't load.
  Future<({String json, int missing})> exportBoard(Json board) async {
    final copy = clone(board);
    var missing = 0;
    for (final card in allCards(copy)) {
      final images = <dynamic>[];
      for (final image in imagesOf(card)) {
        try {
          images.add({'id': image['id'], 'name': image['name'], 'data': await ImageStore.dataUrl(image)});
        } catch (error) {
          missing = missing + 1;
        }
      }
      card['images'] = images;
    }
    return (json: const JsonEncoder.withIndent('  ').convert(copy), missing: missing);
  }

  // Signed in, an imported board's images go into this account's storage, so they're kept by
  // name like any other.
  Future<void> _uploadImportedImages(Json board) async {
    for (final card in allCards(board)) {
      if (card['images'] is! List) {
        continue;
      }
      final kept = <dynamic>[];
      for (final image in imagesOf(card)) {
        if (image['file'] != null) {
          kept.add(image);
          continue;
        }
        if (image['data'] == null && image['url'] == null) {
          continue;
        }
        try {
          final data = await ImageStore.dataUrl(image);
          final dynamic uploadName;
          if (image['name'] != null) {
            uploadName = image['name'];
          } else {
            uploadName = 'image';
          }
          final response = await Api.call('POST', '/images/upload', {'imageData': data, 'fileName': uploadName});
          final dynamic keptId;
          if (image['id'] != null) {
            keptId = image['id'];
          } else {
            keptId = uniqueId();
          }
          final dynamic keptFile = response['file'];
          final dynamic keptName;
          if (image['name'] != null) {
            keptName = image['name'];
          } else {
            keptName = '';
          }
          kept.add(<String, dynamic>{'id': keptId, 'file': keptFile, 'name': keptName});
        } catch (error) {
          // Left out.
        }
      }
      card['images'] = kept;
      final thumbnailStillThere = kept.any((keptImage) {
        return (keptImage as Map)['id'] == card['thumbnailId'];
      });
      if (!thumbnailStillThere) {
        if (kept.isEmpty) {
          card['thumbnailId'] = null;
        } else {
          card['thumbnailId'] = (kept.first as Map)['id'];
        }
      }
    }
  }

  /// A board file, as a new board or over the open one.
  Future<void> importBoard(Object? json, {required bool asNew}) async {
    if (!isBoardFile(json)) {
      AppNavigation.toast('Invalid board file', error: true);
      return;
    }
    final board = clone(Map<String, dynamic>.from(json as Map));
    if (asNew || activeBoardId == null) {
      board['id'] = uniqueId();
    } else {
      board['id'] = activeBoardId;
    }
    if (!isGuest) {
      await _uploadImportedImages(board);
    }
    final existingIndex = boards.indexWhere((existingBoard) {
      return existingBoard['id'] == board['id'];
    });
    if (existingIndex >= 0) {
      boards[existingIndex] = board;
    } else {
      boards.add(board);
    }
    await persistBoard(board);
    selectBoard('${board['id']}');
    AppNavigation.toast('Board imported');
  }

  /* ---- profile ---- */

  /// Returns what went wrong, or null.
  Future<String?> updateProfile({required String name, String newPassword = '', String confirm = '', String? avatarData}) async {
    if (name.isEmpty) {
      return 'Display name cannot be empty.';
    }
    if (!RegExp(r'^[a-zA-Z0-9_]{3,24}$').hasMatch(name)) {
      return 'Name must be 3–24 characters (letters, numbers, underscore).';
    }
    if (newPassword.isNotEmpty && newPassword.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    if (newPassword.isNotEmpty && newPassword != confirm) {
      return 'Passwords do not match.';
    }
    final payload = <String, dynamic>{if (name != shownName) 'displayName': name, if (newPassword.isNotEmpty) 'newPassword': newPassword};
    try {
      if (payload.isNotEmpty) {
        final result = await Api.call('PUT', '/auth/update-profile', payload);
        final shownAs = result['displayName'];
        if (shownAs is String && shownAs.isNotEmpty) {
          displayName = shownAs;
          _saveSession({'displayName': shownAs});
        }
      }
      if (avatarData != null) {
        await Api.call('PUT', '/auth/update-avatar', {'imageData': avatarData});
        hasAvatar = true;
        _saveSession({'hasAvatar': true});
        // The new one, not the copy of the old one this session already has.
        ImageStore.avatar(fresh: true).then<void>((result) {}, onError: (Object error) {});
        avatarVersion = avatarVersion + 1;
      }
      notifyListeners();
      AppNavigation.toast('Profile updated');
      return null;
    } on ApiError catch (error) {
      if (error.offline) {
        return 'No connection. Check your internet and try again.';
      } else {
        return error.message;
      }
    }
  }

  Future<String?> deleteAccount(String password) async {
    if (password.isEmpty) {
      return 'Please enter your password.';
    }
    try {
      await Api.call('DELETE', '/auth/delete-account', {'password': password});
      logout();
      AppNavigation.toast('Account deleted');
      return null;
    } on ApiError catch (error) {
      if (error.offline) {
        return 'No connection. Check your internet and try again.';
      } else {
        return error.message;
      }
    }
  }
}
