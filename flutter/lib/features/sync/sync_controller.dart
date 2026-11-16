// Syncing boards, and the theme, with another device (main-site/js/sync.js): the same session,
// wire and merging, so the app syncs with the site in a browser and with another copy of the
// app. One device shows a code (with a link and a QR code of it), the other enters it. Once
// connected, each side sees the other's boards and ticks which to import, or which of its own
// to send over. Copying merges and never removes. Closing the Sync window ends the session.
//
// The wire, on top of p2p.dart's hello and bye:
//   { type: 'boards', boards, theme }       all of the sender's boards (images by id) and theme
//   { type: 'img', img, seq, total, part }  one chunk of an image's data URL
//   { type: 'add', id, boards, theme }      merge these into yours; their images come first
//   { type: 'added', id, count }            the answer to add
//   { type: 'pull', id, boards }            send me these boards (by id)
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/api.dart';
import '../../app/nav.dart';
import '../../app/state.dart';
import '../../data/board.dart';
import '../../data/images.dart';
import '../../data/store.dart';
import '../../data/sync_logic.dart';
import '../../native/bridge.dart';
import '../../share/p2p.dart';
import '../../theme/theme.dart';

const _hostKey = 'uwuboard.sync.hostCode';
const _lastKey = 'uwuboard.sync.lastCode';
const _acknowledgementMilliseconds = 6000;
const _pullIdleTimeout = Duration(seconds: 15);

/// The link another device opens (or scans as a QR code) to join with this code.
String syncLink(String code) {
  return '$siteOrigin/#sync/$code';
}

/// One setting the theme carries across: its label, what it starts as (only one changed from
/// that is offered), its value as words, and how it's read and set.
class _Setting {
  const _Setting(this.label, this.start, this.values, this.text, this.get, this.set);
  final String label;
  final String start;
  final List<String> Function() values;
  final String Function(String) text;
  final String Function() get;
  final void Function(String) set;
}

/// The theme settings that sync carries, keyed by the field name sent over the wire.
final _settings = <String, _Setting>{
  'mode': _Setting(
    'Light or dark',
    'light',
    () {
      return modePreferences;
    },
    (value) {
      final label = const {'light': 'Light', 'dark': 'Dark', 'time': 'Time-based'}[value];
      if (label == null) {
        return value;
      }
      return label;
    },
    () {
      return ThemeController.I.modePreference;
    },
    ThemeController.I.setMode,
  ),
  'colour': _Setting(
    'Brand colour',
    'classic',
    () {
      return [for (final colorTheme in colorThemes) colorTheme.id];
    },
    (value) {
      final label = colorThemes
          .where((colorTheme) {
            return colorTheme.id == value;
          })
          .map((colorTheme) {
            return colorTheme.label;
          })
          .firstOrNull;
      if (label == null) {
        return value;
      }
      return label;
    },
    () {
      return ThemeController.I.colorThemeId;
    },
    ThemeController.I.setColorTheme,
  ),
};

/// Whether a field and value received from the other device name a real setting and one of its
/// allowed values.
bool _isValidSetting(Object? field, Object? value) {
  return _settings.containsKey(field) && value is String && _settings[field]!.values().contains(value);
}

/// This device's theme settings that differ from where they start, as the wire sends them.
List<Json> _ownTheme() {
  return [
    for (final entry in _settings.entries)
      if (entry.value.get() != entry.value.start) {'field': entry.key, 'value': entry.value.get()},
  ];
}

/// The theme settings the other device sent, keeping only valid ones (at most ten looked at,
/// each field once).
List<Json> _cleanTheme(Object? raw) {
  final seen = <String>{};
  Iterable<dynamic> candidates;
  if (raw is List) {
    candidates = raw.take(10);
  } else {
    candidates = const [];
  }
  return [
    for (final candidate in candidates)
      if (candidate is Map && _isValidSetting(candidate['field'], candidate['value']) && seen.add('${candidate['field']}'))
        {'field': candidate['field'], 'value': candidate['value']},
  ];
}

/// One row the Sync window offers.
class SyncItem {
  SyncItem(this.key, this.kind, this.item, {this.done = false, this.update = false});
  final String key;
  final String kind; // board | setting
  final Json item;
  final bool done;
  final bool update;

  String get title {
    if (kind == 'board') {
      return '${item['name']}';
    } else {
      return _settings[item['field']]!.label;
    }
  }

  String get sub {
    if (kind == 'board') {
      return boardSub(item);
    } else {
      return _settings[item['field']]!.text('${item['value']}');
    }
  }
}

/// Runs a sync session (as the device showing the code, or the one entering it) and holds
/// everything the Sync window shows.
class SyncController extends ChangeNotifier {
  SyncController._();
  static final SyncController I = SyncController._();

  String? role; // host | guest while a session runs
  dynamic connection; // Host or Guest
  String status = 'idle';
  ({List<Json> boards, List<Json> theme})? theirs;
  String tab = 'import';
  final Map<String, Set<String>> picked = {'import': {}, 'export': {}};
  final Map<int, Timer> _pending = {};
  final Map<int, Timer> _pulls = {};
  final Map<String, ({int total, List<String?> parts, int have})> _incoming = {};
  final Map<String, String> _received = {};
  int _lastId = 0;
  bool _retriedTaken = false;
  String droppedCode = '';

  /// What the window shows: a status line with its tone, and a note under the list.
  String statusText = '';
  String statusTone = 'busy';
  String note = '';
  bool noteError = false;
  String hostCode = '';
  String codeInput = '';

  bool get connected {
    return status == 'connected';
  }

  void _changed() {
    notifyListeners();
  }

  void showStatus(String message, [String tone = 'busy']) {
    statusText = message;
    statusTone = tone;
    _changed();
  }

  void showNote(String message, {bool error = false}) {
    note = message;
    noteError = error;
    _changed();
  }

  /// Resets everything for a new session in the given role, and keeps the screen awake.
  void _begin(String newRole) {
    role = newRole;
    status = 'connecting';
    theirs = null;
    droppedCode = '';
    tab = 'import';
    picked['import']!.clear();
    picked['export']!.clear();
    note = '';
    Native.tryCall('App', 'keepScreenOn', {'on': true});
  }

  /// Ends the session: closes the connection (a guest says bye when asked), stops every timer,
  /// forgets anything half received, and shows the given status line.
  void _end({bool bye = false, String text = '', String tone = 'busy'}) {
    final oldConnection = connection;
    connection = null;
    if (oldConnection != null) {
      if (bye && role == 'guest' && oldConnection is Guest) {
        oldConnection.leave();
      } else {
        oldConnection.close();
      }
    }
    for (final timer in [..._pending.values, ..._pulls.values]) {
      timer.cancel();
    }
    _pending.clear();
    _pulls.clear();
    _incoming.clear();
    _received.clear();
    role = null;
    status = 'idle';
    theirs = null;
    Native.tryCall('App', 'keepScreenOn', {'on': false});
    showStatus(text, tone);
  }

  /// Stop, Cancel or Disconnect, or the window closing.
  void stop() {
    droppedCode = '';
    if (role != null) {
      _end(bye: true);
    }
  }

  /// The window closed: nothing is left running out of sight.
  void closed() {
    stop();
    statusText = '';
    note = '';
  }

  /// Shows a code (the stored one when it's still valid) and waits for the other device to join.
  Future<void> startHosting() async {
    if (role != null) {
      return;
    }
    final stored = Store.I.get(_hostKey);
    String code;
    if (isValidCode(stored)) {
      code = stored!;
    } else {
      code = generateCode();
    }
    Store.I.put(_hostKey, code);
    _begin('host');
    hostCode = code;
    final host = Host();
    connection = host;
    host.onStatus = (newStatus, {message, taken = false}) {
      if (!identical(connection, host)) {
        return;
      }
      // The stored code is held by something else: a fresh one, once.
      if (taken && !_retriedTaken) {
        _retriedTaken = true;
        newHostCode();
        return;
      }
      if (newStatus == 'error') {
        if (taken) {
          Store.I.remove(_hostKey);
        }
        String errorText;
        if (message == null) {
          errorText = 'The connection failed.';
        } else {
          errorText = message;
        }
        _end(text: errorText, tone: 'error');
        return;
      }
      if (newStatus == 'waiting') {
        _retriedTaken = false;
      }
      _onStatus(newStatus);
    };
    // A newcomer replaces the device that was connected, whose boards no longer apply.
    host.onJoin = () {
      theirs = null;
      _changed();
    };
    host.onMessage = (message) {
      if (identical(connection, host)) {
        _onMessage(message);
      }
    };
    _render();
    try {
      await host.start(code);
    } catch (error) {
      if (identical(connection, host)) {
        _end(text: 'Could not load syncing. Check your connection.', tone: 'error');
      }
    }
  }

  /// Throws the current code away and starts hosting again with a new one.
  Future<void> newHostCode([String noteText = '']) async {
    _end();
    Store.I.remove(_hostKey);
    await startHosting();
    if (noteText.isNotEmpty) {
      showNote(noteText);
    }
  }

  /// Connects to the device showing the code typed in.
  Future<void> join(String input) async {
    final code = normaliseCode(input);
    if (!isValidCode(code)) {
      showStatus('The code is the $codeLength letters and numbers on the other device’s screen.', 'error');
      return;
    }
    if (role != null) {
      _end();
    }
    _begin('guest');
    Store.I.put(_lastKey, code);
    codeInput = code;
    final guest = Guest();
    connection = guest;
    guest.onStatus = (newStatus, {message, taken = false}) {
      if (!identical(connection, guest)) {
        return;
      }
      if (newStatus == 'dropped') {
        _end(text: 'Lost the connection to the other device. Press Connect to try again.', tone: 'warn');
        droppedCode = code;
      } else if (newStatus == 'unreachable') {
        _end(
          text: 'Could not reach the other device. Both have to be on the same network: join the same wifi, or turn on a hotspot on one and join it from the other. Check the code is still the one on screen.',
          tone: 'error',
        );
      } else if (newStatus == 'error') {
        String errorText;
        if (message == null) {
          errorText = 'The connection failed.';
        } else {
          errorText = message;
        }
        _end(text: errorText, tone: 'error');
      } else {
        _onStatus(newStatus);
      }
    };
    guest.onMessage = (message) {
      if (identical(connection, guest)) {
        _onMessage(message);
      }
    };
    _render();
    try {
      await guest.connect(code);
    } catch (error) {
      if (identical(connection, guest)) {
        _end(text: 'Could not load syncing. Check your connection.', tone: 'error');
      }
    }
  }

  void _onStatus(String newStatus) {
    final previousStatus = status;
    status = newStatus;
    if (newStatus != 'connected') {
      theirs = null;
    } else if (previousStatus != 'connected' && role == 'guest') {
      // The host answers hello with its boards; these are ours for it.
      _sendBoards();
    }
    _render();
  }

  /// Puts the status line that fits the session's state on show.
  void _render() {
    if (role == 'host' && status == 'waiting') {
      showStatus('Waiting for the other device. On it, open Sync and enter this code, or scan the QR code with its camera.', 'warn');
    } else if (role != null && status == 'connecting') {
      String connectingText;
      if (role == 'host') {
        connectingText = 'Getting the code ready…';
      } else {
        connectingText = 'Connecting to the other device…';
      }
      showStatus(connectingText, 'busy');
    } else if (connected) {
      showStatus('Connected to the other device.', 'ok');
    } else {
      _changed();
    }
  }

  void _send(Map<String, Object?> message) {
    final currentConnection = connection;
    if (currentConnection != null) {
      currentConnection.send(message);
    }
  }

  /// Odd on the host and even on the guest, so one side's answer is never taken for the other's.
  int _nextId() {
    _lastId = _lastId + 1;
    int sideNumber;
    if (role == 'host') {
      sideNumber = 1;
    } else {
      sideNumber = 0;
    }
    return _lastId * 2 + sideNumber;
  }

  List<Json> _ownBoards() {
    return [for (final board in AppState.I.boards) listBoard(board)];
  }

  void _sendBoards() {
    _send({'type': 'boards', 'boards': _ownBoards(), 'theme': _ownTheme()});
  }

  Timer? _changeTimer;

  /// This device's boards changed: the other side's lists follow.
  void boardsChanged() {
    if (!connected) {
      return;
    }
    final previousTimer = _changeTimer;
    if (previousTimer != null) {
      previousTimer.cancel();
    }
    _changeTimer = Timer(const Duration(milliseconds: 300), () {
      if (connected) {
        _sendBoards();
      }
      _changed();
    });
  }

  /* ---- images over the channel ---- */

  /// Sends the images of these boards that the other side doesn't already have, in chunks, and
  /// returns how many characters of image data went.
  Future<int> _sendImages(List<Json> boards) async {
    final startConnection = connection;
    final imageIdsTheyHave = <Object?>{};
    List<Json> theirBoards = const <Json>[];
    final theirSide = theirs;
    if (theirSide != null) {
      theirBoards = theirSide.boards;
    }
    for (final theirBoard in theirBoards) {
      for (final card in allCards(theirBoard)) {
        for (final image in imagesOf(card)) {
          imageIdsTheyHave.add(image['id']);
        }
      }
    }
    var charactersSent = 0;
    for (final board in boards) {
      for (final card in allCards(board)) {
        for (final image in imagesOf(card)) {
          if (!imageIdsTheyHave.add(image['id'])) {
            continue;
          }
          String data;
          try {
            data = await ImageStore.dataUrl(image);
          } catch (error) {
            continue;
          }
          if (!identical(connection, startConnection)) {
            return charactersSent;
          }
          if (data.length > maxImageChars) {
            continue;
          }
          final total = (data.length / chunkSize).ceil();
          for (var chunkIndex = 0; chunkIndex < total; chunkIndex = chunkIndex + 1) {
            int end;
            if ((chunkIndex + 1) * chunkSize > data.length) {
              end = data.length;
            } else {
              end = (chunkIndex + 1) * chunkSize;
            }
            _send({'type': 'img', 'img': image['id'], 'seq': chunkIndex, 'total': total, 'part': data.substring(chunkIndex * chunkSize, end)});
          }
          charactersSent = charactersSent + data.length;
        }
      }
    }
    return charactersSent;
  }

  /// One chunk of an image arrived: checks it, files it with the others of that image, and once
  /// every chunk is in, keeps the whole data URL.
  void _onChunk(Json message) {
    int total;
    if (message['total'] is num) {
      total = (message['total'] as num).floor();
    } else {
      total = -1;
    }
    int chunkIndex;
    if (message['seq'] is num) {
      chunkIndex = (message['seq'] as num).floor();
    } else {
      chunkIndex = -1;
    }
    final id = message['img'];
    final part = message['part'];
    if (!isId(id) || part is! String || part.length > chunkSize) {
      return;
    }
    if (!(total >= 1 && total <= (maxImageChars / chunkSize).ceil()) || !(chunkIndex >= 0 && chunkIndex < total)) {
      return;
    }
    if (_received.containsKey(id)) {
      return;
    }
    var entry = _incoming[id];
    if (entry == null || entry.total != total) {
      entry = (total: total, parts: List<String?>.filled(total, null), have: 0);
    }
    if (entry.parts[chunkIndex] == null) {
      entry.parts[chunkIndex] = part;
      entry = (total: entry.total, parts: entry.parts, have: entry.have + 1);
    }
    _incoming[id as String] = entry;
    // An import still arriving is still alive.
    for (final pullId in _pulls.keys.toList()) {
      _pulls[pullId]!.cancel();
      _pulls[pullId] = _pullTimer(pullId);
    }
    if (entry.have < total) {
      return;
    }
    _incoming.remove(id);
    final data = entry.parts.join();
    if (dataUrlRe.hasMatch(data)) {
      _received[id] = data;
    }
  }

  /* ---- merging ---- */

  /// Every image on this device's boards, by its id.
  Map<Object?, Json> _ownImages() {
    return {
      for (final board in AppState.I.boards)
        for (final card in allCards(board))
          for (final image in imagesOf(card)) image['id']: image,
    };
  }

  /// Gives each image on a board that came over the real thing: one this device already has,
  /// or one received over the channel (uploaded first when signed in). Images that can't be
  /// found are left out, and the thumbnail moves if its image went.
  Future<void> _resolveImages(Json board, Map<Object?, Json> local) async {
    for (final card in allCards(board)) {
      final images = imagesOf(card);
      if (images.isEmpty) {
        continue;
      }
      final kept = <dynamic>[];
      for (final image in images) {
        if (image['file'] != null || image['data'] != null || image['url'] != null) {
          kept.add(image);
          continue;
        }
        if (local.containsKey(image['id'])) {
          kept.add(local[image['id']]);
          continue;
        }
        final data = _received[image['id']];
        if (data == null) {
          continue;
        }
        if (AppState.I.isGuest) {
          kept.add({'id': image['id'], 'name': image['name'], 'data': data});
          continue;
        }
        try {
          Object? fileName;
          if (image['name'] == null) {
            fileName = 'image';
          } else {
            fileName = image['name'];
          }
          final response = await Api.call('POST', '/images/upload', {'imageData': data, 'fileName': fileName});
          final entry = <String, dynamic>{'id': image['id'], 'name': image['name'], 'file': response['file']};
          local[image['id']] = entry;
          kept.add(entry);
        } catch (error) {
          // Left out; the card keeps the rest.
        }
      }
      card['images'] = kept;
      final thumbnailKept = kept.any((keptImage) {
        return (keptImage as Map)['id'] == card['thumbnailId'];
      });
      if (!thumbnailKept) {
        if (kept.isEmpty) {
          card['thumbnailId'] = null;
        } else {
          card['thumbnailId'] = (kept.first as Map)['id'];
        }
      }
    }
  }

  /// Merges theme settings and boards from the other device into this one, saves what changed,
  /// and returns how many things changed.
  Future<int> _mergeIn(List<Json> boards, List<Json> theme) async {
    var count = 0;
    for (final themeSetting in theme) {
      final setting = _settings[themeSetting['field']]!;
      if (setting.get() != themeSetting['value']) {
        setting.set('${themeSetting['value']}');
        count = count + 1;
      }
    }
    final app = AppState.I;
    final local = _ownImages();
    final changed = <Json>[];
    for (final incomingBoard in boards) {
      final existingBoard = app.boards.where((board) {
        return board['id'] == incomingBoard['id'];
      }).firstOrNull;
      if (existingBoard == null) {
        final made = <String, dynamic>{
          'id': incomingBoard['id'],
          'name': incomingBoard['name'],
          'view': incomingBoard['view'],
          'updatedAt': stamp(incomingBoard['updatedAt']),
          'columns': <dynamic>[],
        };
        mergeBoardInto(made, incomingBoard);
        app.boards.add(made);
        changed.add(made);
      } else if (mergeBoardInto(existingBoard, incomingBoard) > 0) {
        changed.add(existingBoard);
      }
    }
    for (final changedBoard in changed) {
      await _resolveImages(changedBoard, local);
    }
    if (changed.isNotEmpty) {
      if (app.isGuest) {
        app.saveGuest();
      } else {
        await Future.wait([
          for (final changedBoard in changed)
            Api.call('PUT', '/boards/update', {'board': changedBoard}).catchError((Object error) {
              AppNav.toast('Sync error', error: true);
              return <String, dynamic>{};
            }),
        ]);
      }
      app.boardsChanged(changed);
    }
    return count + changed.length;
  }

  /* ---- messages ---- */

  /// Handles one message from the other device, by its type.
  void _onMessage(Json message) {
    switch (message['type']) {
      case 'hello':
        if (role == 'host') {
          _sendBoards();
        }
      case 'boards':
        final boards = cleanBoards(message['boards']);
        if (boards == null) break;
        theirs = (boards: boards, theme: _cleanTheme(message['theme']));
        _changed();
      case 'img':
        _onChunk(message);
      case 'add':
        _onAdd(message);
      case 'added':
        final id = message['id'];
        final timer = _pending.remove(id);
        if (timer == null) break;
        timer.cancel();
        int addedCount;
        if (message['count'] is num) {
          addedCount = (message['count'] as num).floor().clamp(0, maxBoards + 10);
        } else {
          addedCount = 0;
        }
        String sentNote;
        if (addedCount > 0) {
          String thingsText;
          if (addedCount == 1) {
            thingsText = '1 new thing';
          } else {
            thingsText = '$addedCount new things';
          }
          sentNote = 'Sent. The other device took $thingsText.';
        } else {
          sentNote = 'Sent. The other device already had all of those.';
        }
        showNote(sentNote);
      case 'pull':
        _onPull(message);
      case 'bye':
        if (role == 'host') {
          newHostCode('The other device disconnected. The old code no longer works; this is a new one.');
        }
    }
  }

  /// The other device sent boards and settings to merge in: merges them, answers with how many
  /// changed, and says so in the note.
  Future<void> _onAdd(Json message) async {
    final boards = cleanBoards(message['boards']);
    final id = message['id'];
    if (boards == null || id is! int) {
      return;
    }
    final startConnection = connection;
    final pulled = _pulls.containsKey(id);
    if (pulled) {
      _pulls.remove(id)!.cancel();
    }
    final anyImages = boards.any((board) {
      return allCards(board).any((card) {
        return imagesOf(card).isNotEmpty;
      });
    });
    if (anyImages) {
      showNote('Saving…');
    }
    final count = await _mergeIn(boards, _cleanTheme(message['theme']));
    if (!identical(connection, startConnection)) {
      return;
    }
    _send({'type': 'added', 'id': id, 'count': count});
    if (count > 0) {
      _sendBoards();
    }
    if (pulled) {
      if (count == 1) {
        showNote('Imported 1 thing to this device.');
      } else {
        showNote('Imported $count things to this device.');
      }
    } else {
      String receivedNote;
      if (count > 0) {
        String thingsText;
        if (count == 1) {
          thingsText = '1 thing';
        } else {
          thingsText = '$count things';
        }
        receivedNote = 'The other device sent $thingsText, now saved here.';
      } else {
        receivedNote = 'The other device sent things this device already has.';
      }
      showNote(receivedNote);
    }
  }

  /// The other device asked for some of this device's boards: sends their images, then them.
  Future<void> _onPull(Json message) async {
    final id = message['id'];
    if (id is! int || message['boards'] is! List) {
      return;
    }
    final ids = {
      for (final boardId in message['boards'] as List)
        if (isId(boardId)) boardId,
    };
    final chosen = [
      for (final board in AppState.I.boards)
        if (ids.contains(board['id'])) clone(board),
    ];
    final startConnection = connection;
    await _sendImages(chosen);
    if (!identical(connection, startConnection)) {
      return;
    }
    _send({
      'type': 'add',
      'id': id,
      'boards': [for (final board in chosen) listBoard(board)],
      'theme': <dynamic>[],
    });
  }

  /* ---- copying ---- */

  /// The rows one side has to offer: its boards, then its changed settings.
  List<SyncItem> _items(({List<Json> boards, List<Json> theme})? side) {
    if (side == null) {
      return const [];
    } else {
      return [
        for (final board in side.boards) SyncItem('board:${board['id']}', 'board', board),
        for (final setting in side.theme) SyncItem('setting:${setting['field']}=${setting['value']}', 'setting', setting),
      ];
    }
  }

  ({List<Json> boards, List<Json> theme}) _own() {
    return (boards: _ownBoards(), theme: _ownTheme());
  }

  ({List<Json> boards, List<Json> theme})? get _source {
    if (tab == 'import') {
      return theirs;
    } else {
      return _own();
    }
  }

  ({List<Json> boards, List<Json> theme})? get _destination {
    if (tab == 'import') {
      return _own();
    } else {
      return theirs;
    }
  }

  /// What's on offer in the tab on show, and whether each would change anything at the other end.
  List<SyncItem> offered() {
    final source = _source;
    final destination = _destination;
    if (source == null || destination == null) {
      return const [];
    }
    return [
      for (final offer in _items(source))
        if (offer.kind == 'setting') _offeredSetting(offer, destination) else _offeredBoard(offer, destination),
    ];
  }

  /// A setting on offer, marked done when the other end already has that value.
  SyncItem _offeredSetting(SyncItem offer, ({List<Json> boards, List<Json> theme}) destination) {
    final offeredValue = offer.item['value'];
    Object? valueThere;
    if (tab == 'import') {
      valueThere = _settings[offer.item['field']]!.get();
    } else {
      final matching = destination.theme.where((setting) {
        return setting['field'] == offer.item['field'];
      }).firstOrNull;
      Object? matchingValue;
      if (matching != null) {
        matchingValue = matching['value'];
      }
      if (matchingValue == null) {
        valueThere = _settings[offer.item['field']]!.start;
      } else {
        valueThere = matchingValue;
      }
    }
    return SyncItem(offer.key, offer.kind, offer.item, done: offeredValue == valueThere);
  }

  /// A board on offer, marked done when copying it would change nothing at the other end, or
  /// as an update when the other end has an older copy of it.
  SyncItem _offeredBoard(SyncItem offer, ({List<Json> boards, List<Json> theme}) destination) {
    final exists = destination.boards.any((board) {
      return board['id'] == offer.item['id'];
    });
    final done = !wouldChange(destination.boards, offer.item);
    return SyncItem(offer.key, offer.kind, offer.item, done: done, update: exists && !done);
  }

  void setTab(String newTab) {
    tab = newTab;
    _changed();
  }

  void toggle(String key, bool on) {
    final pickedKeys = picked[tab]!;
    if (on) {
      pickedKeys.add(key);
    } else {
      pickedKeys.remove(key);
    }
    _changed();
  }

  void toggleAll(bool on) {
    final pickedKeys = picked[tab]!;
    for (final offer in offered()) {
      if (offer.done) {
        continue;
      }
      if (on) {
        pickedKeys.add(offer.key);
      } else {
        pickedKeys.remove(offer.key);
      }
    }
    _changed();
  }

  /// Copies the ticked rows: on Import, applies the settings here and asks the other device for
  /// the boards; on Export, sends the boards' images and then the boards and settings, and waits
  /// for an answer (longer the more image data went).
  Future<void> copyPicked() async {
    final pickedKeys = picked[tab]!;
    if (pickedKeys.isEmpty || _source == null) {
      return;
    }
    final chosen = _items(_source).where((offer) {
      return pickedKeys.contains(offer.key);
    }).toList();
    final boards = [
      for (final offer in chosen)
        if (offer.kind == 'board') offer.item,
    ];
    final theme = [
      for (final offer in chosen)
        if (offer.kind == 'setting') offer.item,
    ];
    pickedKeys.clear();
    if (tab == 'import') {
      var count = 0;
      if (theme.isNotEmpty) {
        count = await _mergeIn(const [], theme);
      }
      if (boards.isNotEmpty) {
        final id = _nextId();
        _pulls[id] = _pullTimer(id);
        _send({
          'type': 'pull',
          'id': id,
          'boards': [for (final board in boards) board['id']],
        });
        if (boards.length == 1) {
          showNote('Importing 1 board…');
        } else {
          showNote('Importing ${boards.length} boards…');
        }
      } else {
        if (count == 1) {
          showNote('Imported 1 thing to this device.');
        } else {
          showNote('Imported $count things to this device.');
        }
      }
      if (count > 0) {
        _sendBoards();
      }
    } else {
      final id = _nextId();
      final chosenCount = chosen.length;
      if (chosenCount == 1) {
        showNote('Sending 1 thing…');
      } else {
        showNote('Sending $chosenCount things…');
      }
      final fullBoards = [
        for (final board in AppState.I.boards)
          if (boards.any((chosenBoard) {
            return chosenBoard['id'] == board['id'];
          }))
            clone(board),
      ];
      final startConnection = connection;
      final imageCharacters = await _sendImages(fullBoards);
      if (!identical(connection, startConnection)) {
        return;
      }
      _send({
        'type': 'add',
        'id': id,
        'boards': [for (final board in fullBoards) listBoard(board)],
        'theme': theme,
      });
      // More time for every 100 KB of images.
      _pending[id] = Timer(Duration(milliseconds: _acknowledgementMilliseconds + (imageCharacters / 100000).ceil() * 2000), () {
        _pending.remove(id);
        showNote('No answer from the other device. Check it still says connected, then try again.', error: true);
      });
    }
    _changed();
  }

  /// Gives up on an import when nothing has come for a while.
  Timer _pullTimer(int id) {
    return Timer(_pullIdleTimeout, () {
      _pulls.remove(id);
      showNote('Nothing came from the other device. Check it still says connected, then try again.', error: true);
    });
  }

  /// The window opening: the last code this device joined with, ready to use again.
  void opened() {
    if (role == null && codeInput.isEmpty) {
      final lastCode = Store.I.get(_lastKey);
      if (lastCode == null) {
        codeInput = '';
      } else {
        codeInput = lastCode;
      }
    }
    _render();
  }

  /// A link from another device's QR code: the code filled in, waiting for Connect, since
  /// connecting shows this device's boards to whoever made the link.
  void fromLink(String code) {
    if (role != null) {
      return;
    }
    codeInput = normaliseCode(code);
    showStatus('Press Connect to sync with the device showing this code.', 'busy');
  }

  /// Back in front with a session that dropped meanwhile: try again.
  void resumed(bool windowOpen) {
    if (role == null && droppedCode.isNotEmpty && windowOpen) {
      join(droppedCode);
    }
  }

  void retryTaken() {
    _retriedTaken = false;
  }
}
