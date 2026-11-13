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
const _ackMs = 6000;
const _pullIdle = Duration(seconds: 15);

String syncLink(String code) => '$siteOrigin/#sync/$code';

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

final _settings = <String, _Setting>{
  'mode': _Setting(
    'Light or dark',
    'light',
    () => modePreferences,
    (v) => const {'light': 'Light', 'dark': 'Dark', 'time': 'Time-based'}[v] ?? v,
    () => ThemeController.I.modePreference,
    ThemeController.I.setMode,
  ),
  'colour': _Setting(
    'Brand colour',
    'classic',
    () => [for (final t in colorThemes) t.id],
    (v) => colorThemes.where((t) => t.id == v).map((t) => t.label).firstOrNull ?? v,
    () => ThemeController.I.colorThemeId,
    ThemeController.I.setColorTheme,
  ),
};

bool _settingOk(Object? field, Object? value) => _settings.containsKey(field) && value is String && _settings[field]!.values().contains(value);

List<Json> _ownTheme() => [
  for (final e in _settings.entries)
    if (e.value.get() != e.value.start) {'field': e.key, 'value': e.value.get()},
];

List<Json> _cleanTheme(Object? raw) {
  final seen = <String>{};
  return [
    for (final s in (raw is List ? raw.take(10) : const []))
      if (s is Map && _settingOk(s['field'], s['value']) && seen.add('${s['field']}')) {'field': s['field'], 'value': s['value']},
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

  String get title => kind == 'board' ? '${item['name']}' : _settings[item['field']]!.label;
  String get sub => kind == 'board' ? boardSub(item) : _settings[item['field']]!.text('${item['value']}');
}

class SyncController extends ChangeNotifier {
  SyncController._();
  static final SyncController I = SyncController._();

  String? role; // host | guest while a session runs
  dynamic conn; // Host or Guest
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

  bool get connected => status == 'connected';

  void _changed() => notifyListeners();

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

  void _begin(String r) {
    role = r;
    status = 'connecting';
    theirs = null;
    droppedCode = '';
    tab = 'import';
    picked['import']!.clear();
    picked['export']!.clear();
    note = '';
    Native.tryCall('App', 'keepScreenOn', {'on': true});
  }

  void _end({bool bye = false, String text = '', String tone = 'busy'}) {
    final c = conn;
    conn = null;
    if (c != null) {
      if (bye && role == 'guest' && c is Guest) {
        c.leave();
      } else {
        c.close();
      }
    }
    for (final t in [..._pending.values, ..._pulls.values]) {
      t.cancel();
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
    if (role != null) _end(bye: true);
  }

  /// The window closed: nothing is left running out of sight.
  void closed() {
    stop();
    statusText = '';
    note = '';
  }

  Future<void> startHosting() async {
    if (role != null) return;
    final stored = Store.I.get(_hostKey);
    final code = isValidCode(stored) ? stored! : generateCode();
    Store.I.put(_hostKey, code);
    _begin('host');
    hostCode = code;
    final host = Host();
    conn = host;
    host.onStatus = (s, {message, taken = false}) {
      if (!identical(conn, host)) return;
      // The stored code is held by something else: a fresh one, once.
      if (taken && !_retriedTaken) {
        _retriedTaken = true;
        newHostCode();
        return;
      }
      if (s == 'error') {
        if (taken) Store.I.remove(_hostKey);
        _end(text: message ?? 'The connection failed.', tone: 'error');
        return;
      }
      if (s == 'waiting') _retriedTaken = false;
      _onStatus(s);
    };
    // A newcomer replaces the device that was connected, whose boards no longer apply.
    host.onJoin = () {
      theirs = null;
      _changed();
    };
    host.onMessage = (m) {
      if (identical(conn, host)) _onMessage(m);
    };
    _render();
    try {
      await host.start(code);
    } catch (_) {
      if (identical(conn, host)) _end(text: 'Could not load syncing. Check your connection.', tone: 'error');
    }
  }

  Future<void> newHostCode([String noteText = '']) async {
    _end();
    Store.I.remove(_hostKey);
    await startHosting();
    if (noteText.isNotEmpty) showNote(noteText);
  }

  Future<void> join(String input) async {
    final code = normaliseCode(input);
    if (!isValidCode(code)) {
      showStatus('The code is the $codeLength letters and numbers on the other device’s screen.', 'error');
      return;
    }
    if (role != null) _end();
    _begin('guest');
    Store.I.put(_lastKey, code);
    codeInput = code;
    final guest = Guest();
    conn = guest;
    guest.onStatus = (s, {message, taken = false}) {
      if (!identical(conn, guest)) return;
      if (s == 'dropped') {
        _end(text: 'Lost the connection to the other device. Press Connect to try again.', tone: 'warn');
        droppedCode = code;
      } else if (s == 'unreachable') {
        _end(
          text: 'Could not reach the other device. Both have to be on the same network: join the same wifi, or turn on a hotspot on one and join it from the other. Check the code is still the one on screen.',
          tone: 'error',
        );
      } else if (s == 'error') {
        _end(text: message ?? 'The connection failed.', tone: 'error');
      } else {
        _onStatus(s);
      }
    };
    guest.onMessage = (m) {
      if (identical(conn, guest)) _onMessage(m);
    };
    _render();
    try {
      await guest.connect(code);
    } catch (_) {
      if (identical(conn, guest)) _end(text: 'Could not load syncing. Check your connection.', tone: 'error');
    }
  }

  void _onStatus(String s) {
    final was = status;
    status = s;
    if (s != 'connected') {
      theirs = null;
    } else if (was != 'connected' && role == 'guest') {
      // The host answers hello with its boards; these are ours for it.
      _sendBoards();
    }
    _render();
  }

  void _render() {
    if (role == 'host' && status == 'waiting') {
      showStatus('Waiting for the other device. On it, open Sync and enter this code, or scan the QR code with its camera.', 'warn');
    } else if (role != null && status == 'connecting') {
      showStatus(role == 'host' ? 'Getting the code ready…' : 'Connecting to the other device…', 'busy');
    } else if (connected) {
      showStatus('Connected to the other device.', 'ok');
    } else {
      _changed();
    }
  }

  void _send(Map<String, Object?> m) => conn?.send(m);

  /// Odd on the host and even on the guest, so one side's answer is never taken for the other's.
  int _nextId() => ++_lastId * 2 + (role == 'host' ? 1 : 0);

  List<Json> _ownBoards() => [for (final b in AppState.I.boards) listBoard(b)];

  void _sendBoards() => _send({'type': 'boards', 'boards': _ownBoards(), 'theme': _ownTheme()});

  Timer? _changeTimer;

  /// This device's boards changed: the other side's lists follow.
  void boardsChanged() {
    if (!connected) return;
    _changeTimer?.cancel();
    _changeTimer = Timer(const Duration(milliseconds: 300), () {
      if (connected) _sendBoards();
      _changed();
    });
  }

  /* ---- images over the channel ---- */

  Future<int> _sendImages(List<Json> boards) async {
    final c = conn;
    final have = <Object?>{};
    for (final b in theirs?.boards ?? const <Json>[]) {
      for (final card in allCards(b)) {
        for (final img in imagesOf(card)) {
          have.add(img['id']);
        }
      }
    }
    var sent = 0;
    for (final board in boards) {
      for (final card in allCards(board)) {
        for (final img in imagesOf(card)) {
          if (!have.add(img['id'])) continue;
          String data;
          try {
            data = await ImageStore.dataUrl(img);
          } catch (_) {
            continue;
          }
          if (!identical(conn, c)) return sent;
          if (data.length > maxImageChars) continue;
          final total = (data.length / chunkSize).ceil();
          for (var seq = 0; seq < total; seq++) {
            final end = (seq + 1) * chunkSize > data.length ? data.length : (seq + 1) * chunkSize;
            _send({'type': 'img', 'img': img['id'], 'seq': seq, 'total': total, 'part': data.substring(seq * chunkSize, end)});
          }
          sent += data.length;
        }
      }
    }
    return sent;
  }

  void _onChunk(Json m) {
    final total = m['total'] is num ? (m['total'] as num).floor() : -1;
    final seq = m['seq'] is num ? (m['seq'] as num).floor() : -1;
    final id = m['img'];
    final part = m['part'];
    if (!isId(id) || part is! String || part.length > chunkSize) return;
    if (!(total >= 1 && total <= (maxImageChars / chunkSize).ceil()) || !(seq >= 0 && seq < total)) return;
    if (_received.containsKey(id)) return;
    var entry = _incoming[id];
    if (entry == null || entry.total != total) entry = (total: total, parts: List<String?>.filled(total, null), have: 0);
    if (entry.parts[seq] == null) {
      entry.parts[seq] = part;
      entry = (total: entry.total, parts: entry.parts, have: entry.have + 1);
    }
    _incoming[id as String] = entry;
    // An import still arriving is still alive.
    for (final pid in _pulls.keys.toList()) {
      _pulls[pid]!.cancel();
      _pulls[pid] = _pullTimer(pid);
    }
    if (entry.have < total) return;
    _incoming.remove(id);
    final data = entry.parts.join();
    if (dataUrlRe.hasMatch(data)) _received[id] = data;
  }

  /* ---- merging ---- */

  Map<Object?, Json> _ownImages() => {
    for (final b in AppState.I.boards)
      for (final card in allCards(b))
        for (final img in imagesOf(card)) img['id']: img,
  };

  Future<void> _resolveImages(Json board, Map<Object?, Json> local) async {
    for (final card in allCards(board)) {
      final images = imagesOf(card);
      if (images.isEmpty) continue;
      final kept = <dynamic>[];
      for (final img in images) {
        if (img['file'] != null || img['data'] != null || img['url'] != null) {
          kept.add(img);
          continue;
        }
        if (local.containsKey(img['id'])) {
          kept.add(local[img['id']]);
          continue;
        }
        final data = _received[img['id']];
        if (data == null) continue;
        if (AppState.I.isGuest) {
          kept.add({'id': img['id'], 'name': img['name'], 'data': data});
          continue;
        }
        try {
          final r = await Api.call('POST', '/images/upload', {'imageData': data, 'fileName': img['name'] ?? 'image'});
          final entry = <String, dynamic>{'id': img['id'], 'name': img['name'], 'file': r['file']};
          local[img['id']] = entry;
          kept.add(entry);
        } catch (_) {
          // Left out; the card keeps the rest.
        }
      }
      card['images'] = kept;
      if (!kept.any((i) => (i as Map)['id'] == card['thumbnailId'])) card['thumbnailId'] = kept.isEmpty ? null : (kept.first as Map)['id'];
    }
  }

  Future<int> _mergeIn(List<Json> boards, List<Json> theme) async {
    var count = 0;
    for (final s in theme) {
      final setting = _settings[s['field']]!;
      if (setting.get() != s['value']) {
        setting.set('${s['value']}');
        count++;
      }
    }
    final app = AppState.I;
    final local = _ownImages();
    final changed = <Json>[];
    for (final src in boards) {
      final dest = app.boards.where((b) => b['id'] == src['id']).firstOrNull;
      if (dest == null) {
        final made = <String, dynamic>{'id': src['id'], 'name': src['name'], 'view': src['view'], 'updatedAt': stamp(src['updatedAt']), 'columns': <dynamic>[]};
        mergeBoardInto(made, src);
        app.boards.add(made);
        changed.add(made);
      } else if (mergeBoardInto(dest, src) > 0) {
        changed.add(dest);
      }
    }
    for (final b in changed) {
      await _resolveImages(b, local);
    }
    if (changed.isNotEmpty) {
      if (app.isGuest) {
        app.saveGuest();
      } else {
        await Future.wait([
          for (final b in changed)
            Api.call('PUT', '/boards/update', {'board': b}).catchError((Object _) {
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

  void _onMessage(Json m) {
    switch (m['type']) {
      case 'hello':
        if (role == 'host') _sendBoards();
      case 'boards':
        final boards = cleanBoards(m['boards']);
        if (boards == null) break;
        theirs = (boards: boards, theme: _cleanTheme(m['theme']));
        _changed();
      case 'img':
        _onChunk(m);
      case 'add':
        _onAdd(m);
      case 'added':
        final id = m['id'];
        final timer = _pending.remove(id);
        if (timer == null) break;
        timer.cancel();
        final n = m['count'] is num ? (m['count'] as num).floor().clamp(0, maxBoards + 10) : 0;
        showNote(n > 0 ? 'Sent. The other device took ${n == 1 ? '1 new thing' : '$n new things'}.' : 'Sent. The other device already had all of those.');
      case 'pull':
        _onPull(m);
      case 'bye':
        if (role == 'host') newHostCode('The other device disconnected. The old code no longer works; this is a new one.');
    }
  }

  Future<void> _onAdd(Json m) async {
    final boards = cleanBoards(m['boards']);
    final id = m['id'];
    if (boards == null || id is! int) return;
    final c = conn;
    final pulled = _pulls.containsKey(id);
    if (pulled) _pulls.remove(id)!.cancel();
    if (boards.any((b) => allCards(b).any((k) => imagesOf(k).isNotEmpty))) showNote('Saving…');
    final count = await _mergeIn(boards, _cleanTheme(m['theme']));
    if (!identical(conn, c)) return;
    _send({'type': 'added', 'id': id, 'count': count});
    if (count > 0) _sendBoards();
    if (pulled) {
      showNote(count == 1 ? 'Imported 1 thing to this device.' : 'Imported $count things to this device.');
    } else {
      showNote(
        count > 0
            ? 'The other device sent ${count == 1 ? '1 thing' : '$count things'}, now saved here.'
            : 'The other device sent things this device already has.',
      );
    }
  }

  Future<void> _onPull(Json m) async {
    final id = m['id'];
    if (id is! int || m['boards'] is! List) return;
    final ids = {
      for (final b in m['boards'] as List)
        if (isId(b)) b,
    };
    final chosen = [
      for (final b in AppState.I.boards)
        if (ids.contains(b['id'])) clone(b),
    ];
    final c = conn;
    await _sendImages(chosen);
    if (!identical(conn, c)) return;
    _send({
      'type': 'add',
      'id': id,
      'boards': [for (final b in chosen) listBoard(b)],
      'theme': <dynamic>[],
    });
  }

  /* ---- copying ---- */

  List<SyncItem> _items(({List<Json> boards, List<Json> theme})? side) => side == null
      ? const []
      : [
          for (final b in side.boards) SyncItem('board:${b['id']}', 'board', b),
          for (final s in side.theme) SyncItem('setting:${s['field']}=${s['value']}', 'setting', s),
        ];

  ({List<Json> boards, List<Json> theme}) _own() => (boards: _ownBoards(), theme: _ownTheme());
  ({List<Json> boards, List<Json> theme})? get _source => tab == 'import' ? theirs : _own();
  ({List<Json> boards, List<Json> theme})? get _dest => tab == 'import' ? _own() : theirs;

  /// What's on offer in the tab on show, and whether each would change anything at the other end.
  List<SyncItem> offered() {
    final from = _source, to = _dest;
    if (from == null || to == null) return const [];
    return [
      for (final f in _items(from))
        if (f.kind == 'setting')
          SyncItem(
            f.key,
            f.kind,
            f.item,
            done:
                f.item['value'] ==
                (tab == 'import'
                    ? _settings[f.item['field']]!.get()
                    : (to.theme.where((s) => s['field'] == f.item['field']).firstOrNull?['value'] ?? _settings[f.item['field']]!.start)),
          )
        else
          () {
            final exists = to.boards.any((b) => b['id'] == f.item['id']);
            final done = !wouldChange(to.boards, f.item);
            return SyncItem(f.key, f.kind, f.item, done: done, update: exists && !done);
          }(),
    ];
  }

  void setTab(String t) {
    tab = t;
    _changed();
  }

  void toggle(String key, bool on) {
    final p = picked[tab]!;
    on ? p.add(key) : p.remove(key);
    _changed();
  }

  void toggleAll(bool on) {
    final p = picked[tab]!;
    for (final f in offered()) {
      if (f.done) continue;
      on ? p.add(f.key) : p.remove(f.key);
    }
    _changed();
  }

  Future<void> copyPicked() async {
    final p = picked[tab]!;
    if (p.isEmpty || _source == null) return;
    final chosen = _items(_source).where((f) => p.contains(f.key)).toList();
    final boards = [
      for (final f in chosen)
        if (f.kind == 'board') f.item,
    ];
    final theme = [
      for (final f in chosen)
        if (f.kind == 'setting') f.item,
    ];
    p.clear();
    if (tab == 'import') {
      final count = theme.isNotEmpty ? await _mergeIn(const [], theme) : 0;
      if (boards.isNotEmpty) {
        final id = _nextId();
        _pulls[id] = _pullTimer(id);
        _send({
          'type': 'pull',
          'id': id,
          'boards': [for (final b in boards) b['id']],
        });
        showNote(boards.length == 1 ? 'Importing 1 board…' : 'Importing ${boards.length} boards…');
      } else {
        showNote(count == 1 ? 'Imported 1 thing to this device.' : 'Imported $count things to this device.');
      }
      if (count > 0) _sendBoards();
    } else {
      final id = _nextId();
      final n = chosen.length;
      showNote(n == 1 ? 'Sending 1 thing…' : 'Sending $n things…');
      final full = [
        for (final b in AppState.I.boards)
          if (boards.any((x) => x['id'] == b['id'])) clone(b),
      ];
      final c = conn;
      final chars = await _sendImages(full);
      if (!identical(conn, c)) return;
      _send({
        'type': 'add',
        'id': id,
        'boards': [for (final b in full) listBoard(b)],
        'theme': theme,
      });
      // More time for every 100 KB of images.
      _pending[id] = Timer(Duration(milliseconds: _ackMs + (chars / 100000).ceil() * 2000), () {
        _pending.remove(id);
        showNote('No answer from the other device. Check it still says connected, then try again.', error: true);
      });
    }
    _changed();
  }

  Timer _pullTimer(int id) => Timer(_pullIdle, () {
    _pulls.remove(id);
    showNote('Nothing came from the other device. Check it still says connected, then try again.', error: true);
  });

  /// The window opening: the last code this device joined with, ready to use again.
  void opened() {
    if (role == null && codeInput.isEmpty) codeInput = Store.I.get(_lastKey) ?? '';
    _render();
  }

  /// A link from another device's QR code: the code filled in, waiting for Connect, since
  /// connecting shows this device's boards to whoever made the link.
  void fromLink(String code) {
    if (role != null) return;
    codeInput = normaliseCode(code);
    showStatus('Press Connect to sync with the device showing this code.', 'busy');
  }

  /// Back in front with a session that dropped meanwhile: try again.
  void resumed(bool windowOpen) {
    if (role == null && droppedCode.isNotEmpty && windowOpen) join(droppedCode);
  }

  void retryTaken() => _retriedTaken = false;
}
