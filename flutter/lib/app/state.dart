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
import '../data/timeline_logic.dart' as tl;
import 'nav.dart';

const keySession = 'uwuboard_session';
const keyGuestBoards = 'kanbanflow_guest_boards';

/// The app's own: the signed-in boards as last fetched, for opening offline. The site's service
/// worker keeps the same thing as its copy of /api/boards/list.
const keyBoardsCache = 'app.boardsCache';

class AppState extends ChangeNotifier {
  AppState._();
  static final AppState I = AppState._();

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
  Stream<void> get pageChanges => _pageChanges.stream;
  void pageChanged() => _pageChanges.add(null);

  /// This device's boards changed: a running sync tells the other device.
  void Function()? onBoardsChanged;

  /// For tests.
  @visibleForTesting
  void reset() {
    session = null;
    username = displayName = '';
    hasAvatar = isGuest = boardsReady = shown = false;
    boards = [];
    activeBoardId = viewOverride = pendingSyncCode = null;
  }

  bool get signedIn => !isGuest && session != null;
  String get shownName => isGuest ? 'Guest' : (displayName.isEmpty ? username : displayName);
  String get role => isGuest ? 'Guest session' : 'Signed in';
  String get initial => signedIn ? (shownName.isEmpty ? 'U' : shownName[0].toUpperCase()) : 'G';

  Json? get activeBoard {
    for (final b in boards) {
      if (b['id'] == activeBoardId) return b;
    }
    return null;
  }

  /// The same board either way: its columns are a timeline's phases and its cards the tasks.
  bool isTimeline(Json? board) {
    if (board == null) return false;
    final override = identical(board, activeBoard) ? viewOverride : null;
    return (override ?? board['view']) == 'timeline';
  }

  /* ---- storage ---- */

  void saveGuest() {
    if (!isGuest) return;
    Store.I.put(keyGuestBoards, jsonEncode(boards));
    onBoardsChanged?.call();
  }

  List<Json> _loadGuest() {
    try {
      return boardsFromJson(jsonDecode(Store.I.get(keyGuestBoards) ?? '[]'));
    } catch (_) {
      return [];
    }
  }

  /// What's kept of a session on this device: no avatar address, just whether there is one.
  void _saveSession([Json changes = const {}]) {
    Json saved;
    try {
      saved = Map<String, dynamic>.from(jsonDecode(Store.I.get(keySession) ?? '{}') as Map);
    } catch (_) {
      saved = {};
    }
    saved.remove('avatarUrl');
    Store.I.put(keySession, jsonEncode({...saved, ...changes}));
  }

  void _cacheBoards() {
    if (signedIn) Store.I.put(keyBoardsCache, jsonEncode(boards));
  }

  /* ---- signing in and out ---- */

  void _setSession(Json s, String user, String? shownAs, bool avatar) {
    session = s;
    username = user;
    hasAvatar = avatar;
    isGuest = false;
    Api.token = s['token'] as String?;
    displayName = shownAs == null || shownAs.isEmpty ? user : shownAs;
    Store.I.put(keySession, jsonEncode({'session': s, 'username': user, 'displayName': displayName, 'hasAvatar': avatar}));
    shown = true;
    notifyListeners();
    pageChanged();
  }

  /// The session saved on this device, if it still works. Offline, the boards as last
  /// fetched; a session the server refuses is forgotten.
  Future<void> restore() async {
    final saved = Store.I.get(keySession);
    if (saved == null) return;
    Json parsed;
    try {
      parsed = Map<String, dynamic>.from(jsonDecode(saved) as Map);
    } catch (_) {
      Store.I.remove(keySession);
      return;
    }
    final s = parsed['session'];
    if (s is! Map || s['token'] is! String) {
      Store.I.remove(keySession);
      return;
    }
    final sess = Map<String, dynamic>.from(s);
    // A session saved before images were hidden kept the avatar's address; only whether there
    // is one matters now.
    final avatar = parsed['hasAvatar'] is bool ? parsed['hasAvatar'] as bool : parsed['avatarUrl'] != null && parsed['avatarUrl'] != '';
    Api.token = sess['token'] as String;
    try {
      final data = await Api.call('GET', '/boards/list');
      _setSession(sess, '${parsed['username'] ?? ''}', parsed['displayName'] as String?, avatar);
      boards = boardsFromJson(data['boards']);
      _cacheBoards();
    } on ApiError catch (e) {
      if (!e.offline) {
        Api.token = null;
        Store.I.remove(keySession);
        Store.I.remove(keyBoardsCache);
        return;
      }
      // No network: what was here last time, and the offline bar says why.
      _setSession(sess, '${parsed['username'] ?? ''}', parsed['displayName'] as String?, avatar);
      try {
        boards = boardsFromJson(jsonDecode(Store.I.get(keyBoardsCache) ?? '[]'));
      } catch (_) {
        boards = [];
      }
      _reloadWhenOnline();
    }
    boardsReady = true;
    if (boards.isNotEmpty) selectBoard('${boards.first['id']}');
    notifyListeners();
  }

  void _reloadWhenOnline() {
    void listener() {
      if (Api.offline.value) return;
      Api.offline.removeListener(listener);
      if (signedIn) loadUserBoards();
    }

    Api.offline.addListener(listener);
  }

  /// Returns what went wrong, or null.
  Future<String?> login(String user, String pass) async {
    if (user.isEmpty || pass.isEmpty) return 'Please fill in all fields.';
    try {
      final data = await Api.call('POST', '/auth/login', {'username': user, 'password': pass});
      _setSession(Map<String, dynamic>.from(data['session'] as Map), '${data['username']}', data['displayName'] as String?, data['hasAvatar'] == true);
      await loadUserBoards();
      return null;
    } on ApiError catch (e) {
      return e.offline ? 'No connection. Check your internet and try again.' : e.message;
    }
  }

  Future<String?> register(String user, String email, String pass) async {
    if (user.isEmpty || email.isEmpty || pass.isEmpty) return 'Please fill in all fields.';
    if (pass.length < 8) return 'Password must be at least 8 characters.';
    try {
      final data = await Api.call('POST', '/auth/register', {'username': user, 'email': email, 'password': pass});
      _setSession(Map<String, dynamic>.from(data['session'] as Map), '${data['username']}', data['displayName'] as String?, false);
      await loadUserBoards();
      return null;
    } on ApiError catch (e) {
      return e.offline ? 'No connection. Check your internet and try again.' : e.message;
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

  void logout() {
    final token = session?['token'];
    if (signedIn && token is String) {
      Api.client.post(Api.uri('/auth/logout'), headers: {'Authorization': 'Bearer $token'}).then<void>((_) {}, onError: (Object _) {});
    }
    for (final f in List.of(onLogout)) {
      f();
    }
    Store.I.remove(keySession);
    Store.I.remove(keyBoardsCache);
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
    if (isGuest) return;
    try {
      final data = await Api.call('GET', '/boards/list');
      boards = boardsFromJson(data['boards']);
      _cacheBoards();
      final keep = activeBoard != null;
      if (!keep && boards.isNotEmpty) selectBoard('${boards.first['id']}');
      onBoardsChanged?.call();
    } on ApiError {
      AppNav.toast('Failed to load boards', error: true);
    }
    boardsReady = true;
    notifyListeners();
  }

  void selectBoard(String id) {
    if (!boards.any((b) => b['id'] == id)) return;
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
      AppNav.toast('Sync error', error: true);
    }
    onBoardsChanged?.call();
  }

  Future<void> createBoard(String name, String type, List<String> columns) async {
    final board = newBoard(name, type, columns);
    boards.add(board);
    if (!isGuest) {
      _cacheBoards();
      try {
        await Api.call('POST', '/boards/create', {'board': board});
      } on ApiError {
        AppNav.toast('Save error', error: true);
      }
      onBoardsChanged?.call();
    } else {
      saveGuest();
    }
    selectBoard('${board['id']}');
    AppNav.toast('Board "$name" created');
  }

  void renameBoard(Json board, String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    board['name'] = n;
    touch(board);
    persistBoard(board);
  }

  Future<void> deleteBoard(Json board) async {
    if (!isGuest) {
      try {
        await Api.call('DELETE', '/boards/delete', {'boardId': board['id']});
      } on ApiError {
        AppNav.toast('Delete error', error: true);
      }
    }
    boards.removeWhere((b) => b['id'] == board['id']);
    activeBoardId = null;
    viewOverride = null;
    saveGuest();
    if (!isGuest) {
      _cacheBoards();
      onBoardsChanged?.call();
    }
    AppNav.toast('Board deleted');
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
    if (board == null) return;
    board['view'] = isTimeline(board) ? 'kanban' : 'timeline';
    viewOverride = null;
    touch(board);
    persistBoard(board);
    pageChanged();
    AppNav.toast(isTimeline(board) ? 'Showing as a timeline' : 'Showing as a kanban board');
  }

  /// `view` for the open board, just for now; its own view clears it.
  void setViewOverride(String? view) {
    final board = activeBoard;
    if (board == null) return;
    final own = board['view'] == 'timeline' ? 'timeline' : 'kanban';
    viewOverride = view != null && view != own ? view : null;
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
    final n = name.trim();
    if (n.isEmpty) return;
    (board['columns'] as List).add(newColumn(n));
    persistBoard(board);
  }

  void renameColumn(Json board, Json col, String name) {
    final n = name.trim();
    if (n.isNotEmpty) col['name'] = n;
    touch(col);
    persistBoard(board);
  }

  void deleteColumn(Json board, String colId) {
    final timeline = isTimeline(board);
    (board['columns'] as List).removeWhere((c) => c is Map && c['id'] == colId);
    tl.pruneDeps(board);
    persistBoard(board);
    AppNav.toast(timeline ? 'Phase deleted' : 'Column deleted');
  }

  /// Columns in a new order, by id.
  void reorderColumns(Json board, List<String> order) {
    final cols = columnsOf(board);
    final sorted = <dynamic>[for (final id in order) ...cols.where((c) => c['id'] == id), ...cols.where((c) => !order.contains(c['id']))];
    board['columns'] = sorted;
    persistBoard(board);
    AppNav.toast('Columns reordered');
  }

  Json? addCard(Json board, String colId, String title) {
    final col = findColumn(board, colId);
    final t = title.trim();
    if (col == null || t.isEmpty) return null;
    final card = newCard(t);
    (col['cards'] as List).add(card);
    persistBoard(board);
    return card;
  }

  /// Moves a card to `toColId`, before the card `beforeId` or at the end. Where a card is
  /// counts as a change to it, so a move made here wins over an older copy.
  void moveCard(Json board, String cardId, String toColId, {String? beforeId}) {
    final src = columnOfCard(board, cardId);
    final dst = findColumn(board, toColId);
    if (src == null || dst == null || beforeId == cardId) return;
    final srcCards = src['cards'] as List;
    final i = srcCards.indexWhere((c) => c is Map && c['id'] == cardId);
    if (i < 0) return;
    final card = srcCards.removeAt(i) as Map;
    if (!identical(src, dst)) card['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    final dstCards = dst['cards'] as List;
    final at = beforeId == null ? -1 : dstCards.indexWhere((c) => c is Map && c['id'] == beforeId);
    if (at < 0) {
      dstCards.add(card);
    } else {
      dstCards.insert(at, card);
    }
    persistBoard(board);
  }

  void deleteCard(Json board, String cardId) {
    final col = columnOfCard(board, cardId);
    if (col == null) return;
    (col['cards'] as List).removeWhere((c) => c is Map && c['id'] == cardId);
    tl.pruneDeps(board);
    persistBoard(board);
    AppNav.toast('Card deleted');
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
      for (final img in imagesOf(card)) {
        try {
          images.add({'id': img['id'], 'name': img['name'], 'data': await ImageStore.dataUrl(img)});
        } catch (_) {
          missing++;
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
      if (card['images'] is! List) continue;
      final kept = <dynamic>[];
      for (final img in imagesOf(card)) {
        if (img['file'] != null) {
          kept.add(img);
          continue;
        }
        if (img['data'] == null && img['url'] == null) continue;
        try {
          final data = await ImageStore.dataUrl(img);
          final r = await Api.call('POST', '/images/upload', {'imageData': data, 'fileName': img['name'] ?? 'image'});
          kept.add({'id': img['id'] ?? uid(), 'file': r['file'], 'name': img['name'] ?? ''});
        } catch (_) {
          // Left out.
        }
      }
      card['images'] = kept;
      if (!kept.any((i) => (i as Map)['id'] == card['thumbnailId'])) {
        card['thumbnailId'] = kept.isEmpty ? null : (kept.first as Map)['id'];
      }
    }
  }

  /// A board file, as a new board or over the open one.
  Future<void> importBoard(Object? json, {required bool asNew}) async {
    if (!isBoardFile(json)) {
      AppNav.toast('Invalid board file', error: true);
      return;
    }
    final board = clone(Map<String, dynamic>.from(json as Map));
    board['id'] = asNew || activeBoardId == null ? uid() : activeBoardId;
    if (!isGuest) await _uploadImportedImages(board);
    final i = boards.indexWhere((b) => b['id'] == board['id']);
    if (i >= 0) {
      boards[i] = board;
    } else {
      boards.add(board);
    }
    await persistBoard(board);
    selectBoard('${board['id']}');
    AppNav.toast('Board imported');
  }

  /* ---- profile ---- */

  /// Returns what went wrong, or null.
  Future<String?> updateProfile({required String name, String newPassword = '', String confirm = '', String? avatarData}) async {
    if (name.isEmpty) return 'Display name cannot be empty.';
    if (!RegExp(r'^[a-zA-Z0-9_]{3,24}$').hasMatch(name)) return 'Name must be 3–24 characters (letters, numbers, underscore).';
    if (newPassword.isNotEmpty && newPassword.length < 8) return 'Password must be at least 8 characters.';
    if (newPassword.isNotEmpty && newPassword != confirm) return 'Passwords do not match.';
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
        ImageStore.avatar(fresh: true).then<void>((_) {}, onError: (Object _) {});
        avatarVersion++;
      }
      notifyListeners();
      AppNav.toast('Profile updated');
      return null;
    } on ApiError catch (e) {
      return e.offline ? 'No connection. Check your internet and try again.' : e.message;
    }
  }

  Future<String?> deleteAccount(String password) async {
    if (password.isEmpty) return 'Please enter your password.';
    try {
      await Api.call('DELETE', '/auth/delete-account', {'password': password});
      logout();
      AppNav.toast('Account deleted');
      return null;
    } on ApiError catch (e) {
      return e.offline ? 'No connection. Check your internet and try again.' : e.message;
    }
  }
}
