// Desktop widgets (docs/desktop-features-spec.md §8), for boards: small frameless windows on the
// desktop, each showing one board's next due cards, because a third-party app can't add to the
// system's widget board. Each is its own window and Flutter engine (desktop_multi_window),
// started from main(args) with { kind: 'widget', id } and running only this small screen.
//
// - Added from the tray (Add a desktop widget) or a board's right-click menu (Pin to Desktop
//   Widget). A new one opens in its setup state: pick a board; Save.
// - Shows as many cards as fit, scrolling for the rest, each with when it's due, counted again
//   every 15 s and read again every 30 s (from the account, or this computer's guest boards).
// - Its own buttons: refresh, change the board, pin on top of other windows, remove (×).
// - Moved by dragging its top; resized from any edge, down to 200 × 110. Default 320 × 300.
// - Clicking a card opens its board in the main window.
// - Kept: each widget's board, pin and place, reopened where it was when the app starts.
//   Removing one with × forgets it; quitting keeps them all. Not in the taskbar or Alt+Tab.
//
// Keys: widgets: [{ id, code, name, items: [], onTop, bounds }].
import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';

import '../api/api.dart';
import '../app/state.dart' show keyGuestBoards, keySession;
import '../data/board.dart';
import '../data/store.dart';
import '../theme/icons.dart';
import '../theme/theme.dart';
import 'glance.dart';
import 'settings.dart';

const widgetChannel = WindowMethodChannel('org.uwuapps.board/widgets');

class DeskWidgets {
  DeskWidgets._();

  static List<Map<String, dynamic>> _all() => [
    for (final w in (DeskSettings.get<List<dynamic>>('widgets') ?? const []))
      if (w is Map) Map<String, dynamic>.from(w),
  ];

  static void _save(List<Map<String, dynamic>> list) => DeskSettings.write({'widgets': list});

  static Future<void> _open(Map<String, dynamic> w) async {
    try {
      final c = await WindowController.create(WindowConfiguration(hiddenAtLaunch: true, arguments: jsonEncode({'kind': 'widget', 'id': w['id']})));
      await c.show();
    } catch (_) {
      // No second window on this system.
    }
  }

  /// A new widget, in its setup state, or already showing `board`.
  static Future<void> add([Json? board]) async {
    final w = <String, dynamic>{'id': uid(), 'code': board?['id'], 'name': board?['name'] ?? '', 'items': <dynamic>[], 'onTop': false, 'bounds': null};
    _save([..._all(), w]);
    await _open(w);
  }

  /// Every kept widget, where it was, as the app starts.
  static Future<void> reopenAll() async {
    for (final w in _all()) {
      await _open(w);
    }
  }

  /// The main window hears what its widgets ask: open a board.
  static void listen(void Function(String link) open) {
    widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) open(call.arguments as String);
      return null;
    });
  }
}

/// A widget's own engine: its window set up, then its screen.
Future<void> runWidgetWindow(String id) async {
  await Store.open();
  ThemeController.I.init();
  await windowManager.ensureInitialized();
  final w = DeskWidgets._all().where((x) => x['id'] == id).firstOrNull;
  if (w == null) return;
  final b = w['bounds'];
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: b is Map ? Size((b['width'] as num).toDouble(), (b['height'] as num).toDouble()) : const Size(320, 300),
      minimumSize: const Size(200, 110),
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      alwaysOnTop: w['onTop'] == true,
      backgroundColor: Colors.transparent,
    ),
  );
  if (b is Map) await windowManager.setPosition(Offset((b['x'] as num).toDouble(), (b['y'] as num).toDouble()));
  await windowManager.setAsFrameless();
  await windowManager.show();
  runApp(_WidgetApp(id: id));
}

class _WidgetApp extends StatefulWidget {
  const _WidgetApp({required this.id});
  final String id;

  @override
  State<_WidgetApp> createState() => _WidgetAppState();
}

class _WidgetAppState extends State<_WidgetApp> with WindowListener {
  Map<String, dynamic> _w = {};
  List<Json> _boards = [];
  Json? _board;
  bool _setup = false;
  bool _loading = true;
  String? _error;
  Timer? _fetch;
  Timer? _tick;
  Timer? _keep;

  @override
  void initState() {
    super.initState();
    _w = DeskWidgets._all().firstWhere((x) => x['id'] == widget.id, orElse: () => {'id': widget.id});
    _setup = _w['code'] == null;
    windowManager.addListener(this);
    _load();
    _fetch = Timer.periodic(const Duration(seconds: 30), (_) => _load());
    _tick = Timer.periodic(const Duration(seconds: 15), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _fetch?.cancel();
    _tick?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  void _update(Map<String, dynamic> changes) {
    _w = {..._w, ...changes};
    final list = DeskWidgets._all();
    final i = list.indexWhere((x) => x['id'] == widget.id);
    if (i >= 0) {
      list[i] = _w;
    } else {
      list.add(_w);
    }
    DeskWidgets._save(list);
  }

  // Bounds, a moment after the last move or resize.
  void _keepBounds() {
    _keep?.cancel();
    _keep = Timer(const Duration(milliseconds: 500), () async {
      final r = await windowManager.getBounds();
      _update({
        'bounds': {'x': r.left.round(), 'y': r.top.round(), 'width': r.width.round(), 'height': r.height.round()},
      });
    });
  }

  @override
  void onWindowMoved() => _keepBounds();

  @override
  void onWindowResized() => _keepBounds();

  /// The boards: the account's, signed in, or this computer's guest boards.
  Future<void> _load() async {
    await Store.I.reload();
    try {
      final saved = Store.I.get(keySession);
      final token = saved == null ? null : ((jsonDecode(saved) as Map)['session'] as Map?)?['token'];
      if (token is String) {
        final r = await http.get(Uri.parse('$siteOrigin/api/boards/list'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
        if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode}');
        _boards = boardsFromJson((jsonDecode(r.body) as Map)['boards']);
      } else {
        _boards = boardsFromJson(jsonDecode(Store.I.get(keyGuestBoards) ?? '[]'));
      }
      _error = null;
    } catch (_) {
      _error = 'Couldn’t get the cards just now';
    }
    _board = _boards.where((b) => b['id'] == _w['code']).firstOrNull;
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeController.I;
    final theme = buildTheme(look: lookUwuApps, brightness: t.brightness, brand: t.colorTheme.color, desktop: true);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Builder(
        builder: (context) {
          final c = UwuColors.of(context);
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Container(
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _top(c),
                  Expanded(child: _setup ? _setupView(c) : _cards(c)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _top(UwuColors c) {
    Widget btn(String icon, String label, VoidCallback onTap, {bool on = false}) => Tooltip(
      excludeFromSemantics: true,
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: AppIcon(icon, size: 14, color: on ? c.brandInk : c.muted),
        ),
      ),
    );
    return Container(
      color: c.surfaceStrong,
      padding: const EdgeInsets.only(left: 10, right: 4),
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Container(
                alignment: Alignment.centerLeft,
                child: Text(
                  _setup ? 'Desktop widget' : '${_board?['name'] ?? _w['name'] ?? ''}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.ink, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          if (!_setup) ...[btn('refresh', 'Refresh', _load), btn('pencil', 'Change what it shows', () => setState(() => _setup = true))],
          btn('pin', _w['onTop'] == true ? 'Stop keeping on top' : 'Keep on top of other windows', () async {
            final on = _w['onTop'] != true;
            _update({'onTop': on});
            await windowManager.setAlwaysOnTop(on);
            setState(() {});
          }, on: _w['onTop'] == true),
          btn('close', 'Remove', () async {
            DeskWidgets._save(DeskWidgets._all().where((x) => x['id'] != widget.id).toList());
            await windowManager.destroy();
          }),
        ],
      ),
    );
  }

  Widget _setupView(UwuColors c) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_boards.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _error ?? 'Make a board in uwuBoard first.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text('Pick a board to show its due cards', style: TextStyle(color: c.muted, fontSize: 12)),
        ),
        for (final b in _boards)
          ListTile(
            dense: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tileColor: b['id'] == _w['code'] ? c.brandFill : null,
            title: Text('${b['name']}', style: TextStyle(color: c.ink, fontSize: 13)),
            onTap: () {
              _update({'code': b['id'], 'name': b['name']});
              setState(() {
                _board = b;
                _setup = false;
              });
            },
          ),
      ],
    );
  }

  Widget _cards(UwuColors c) {
    final board = _board;
    if (board == null) {
      return Center(
        child: Text(
          _loading ? '' : (_error ?? 'That board is gone. Change what it shows.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
      );
    }
    final due = dueCards(board);
    if (due.isEmpty) {
      return Center(child: Text('No cards due', style: TextStyle(color: c.muted, fontSize: 12)));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: due.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
      itemBuilder: (context, i) {
        final d = due[i];
        final colour = d.days < 0 ? c.error : (d.days == 0 ? c.warn : c.muted);
        return InkWell(
          onTap: () => widgetChannel.invokeMethod('open', 'uwu://board/b/${board['id']}').catchError((Object _) => null),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${d.card['title']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.ink, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                Text(d.when, style: TextStyle(color: colour, fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }
}
