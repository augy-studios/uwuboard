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

  /// Every kept widget, as its settings entry.
  static List<Map<String, dynamic>> _all() {
    List<dynamic>? kept = DeskSettings.get<List<dynamic>>('widgets');
    if (kept == null) {
      kept = const [];
    }
    return [
      for (final entry in kept)
        if (entry is Map) Map<String, dynamic>.from(entry),
    ];
  }

  static void _save(List<Map<String, dynamic>> list) {
    DeskSettings.write({'widgets': list});
  }

  /// Opens a widget in its own window and engine.
  static Future<void> _open(Map<String, dynamic> widgetEntry) async {
    try {
      final controller = await WindowController.create(WindowConfiguration(hiddenAtLaunch: true, arguments: jsonEncode({'kind': 'widget', 'id': widgetEntry['id']})));
      await controller.show();
    } catch (error) {
      // No second window on this system.
    }
  }

  /// A new widget, in its setup state, or already showing `board`.
  static Future<void> add([Json? board]) async {
    final id = uid();
    Object? code;
    Object? name;
    if (board != null) {
      code = board['id'];
      name = board['name'];
    }
    if (name == null) {
      name = '';
    }
    final widgetEntry = <String, dynamic>{'id': id, 'code': code, 'name': name, 'items': <dynamic>[], 'onTop': false, 'bounds': null};
    _save([..._all(), widgetEntry]);
    await _open(widgetEntry);
  }

  /// Every kept widget, where it was, as the app starts.
  static Future<void> reopenAll() async {
    for (final widgetEntry in _all()) {
      await _open(widgetEntry);
    }
  }

  /// The main window hears what its widgets ask: open a board.
  static void listen(void Function(String link) open) {
    widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) {
        open(call.arguments as String);
      }
      return null;
    });
  }
}

/// A widget's own engine: its window set up, then its screen.
Future<void> runWidgetWindow(String id) async {
  await Store.open();
  ThemeController.I.init();
  await windowManager.ensureInitialized();
  final widgetEntry = DeskWidgets._all().where((entry) {
    return entry['id'] == id;
  }).firstOrNull;
  if (widgetEntry == null) {
    return;
  }
  final bounds = widgetEntry['bounds'];
  // Its kept size, or the default size for a new one.
  Size size;
  if (bounds is Map) {
    size = Size((bounds['width'] as num).toDouble(), (bounds['height'] as num).toDouble());
  } else {
    size = const Size(320, 300);
  }
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: size,
      minimumSize: const Size(200, 110),
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      alwaysOnTop: widgetEntry['onTop'] == true,
      backgroundColor: Colors.transparent,
    ),
  );
  if (bounds is Map) {
    await windowManager.setPosition(Offset((bounds['x'] as num).toDouble(), (bounds['y'] as num).toDouble()));
  }
  await windowManager.setAsFrameless();
  await windowManager.show();
  runApp(_WidgetApp(id: id));
}

class _WidgetApp extends StatefulWidget {
  const _WidgetApp({required this.id});
  final String id;

  @override
  State<_WidgetApp> createState() {
    return _WidgetAppState();
  }
}

class _WidgetAppState extends State<_WidgetApp> with WindowListener {
  /// This widget's settings entry: its board, pin and place.
  Map<String, dynamic> _widgetEntry = {};
  List<Json> _boards = [];
  Json? _board;

  /// True while it's asking which board to show.
  bool _settingUp = false;
  bool _loading = true;
  String? _error;
  Timer? _fetchTimer;
  Timer? _tickTimer;
  Timer? _keepBoundsTimer;

  /// Finds its entry, then reads the boards now and every 30 seconds, and counts the days
  /// again every 15 seconds.
  @override
  void initState() {
    super.initState();
    _widgetEntry = DeskWidgets._all().firstWhere(
      (entry) {
        return entry['id'] == widget.id;
      },
      orElse: () {
        return {'id': widget.id};
      },
    );
    _settingUp = _widgetEntry['code'] == null;
    windowManager.addListener(this);
    _load();
    _fetchTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _load();
    });
    _tickTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    final fetchTimer = _fetchTimer;
    if (fetchTimer != null) {
      fetchTimer.cancel();
    }
    final tickTimer = _tickTimer;
    if (tickTimer != null) {
      tickTimer.cancel();
    }
    windowManager.removeListener(this);
    super.dispose();
  }

  /// Merges `changes` into this widget's entry and saves it among the others.
  void _update(Map<String, dynamic> changes) {
    _widgetEntry = {..._widgetEntry, ...changes};
    final list = DeskWidgets._all();
    final index = list.indexWhere((entry) {
      return entry['id'] == widget.id;
    });
    if (index >= 0) {
      list[index] = _widgetEntry;
    } else {
      list.add(_widgetEntry);
    }
    DeskWidgets._save(list);
  }

  // Bounds, a moment after the last move or resize.
  void _keepBounds() {
    final oldTimer = _keepBoundsTimer;
    if (oldTimer != null) {
      oldTimer.cancel();
    }
    _keepBoundsTimer = Timer(const Duration(milliseconds: 500), () async {
      final bounds = await windowManager.getBounds();
      _update({
        'bounds': {'x': bounds.left.round(), 'y': bounds.top.round(), 'width': bounds.width.round(), 'height': bounds.height.round()},
      });
    });
  }

  @override
  void onWindowMoved() {
    _keepBounds();
  }

  @override
  void onWindowResized() {
    _keepBounds();
  }

  /// The boards: the account's, signed in, or this computer's guest boards.
  Future<void> _load() async {
    await Store.I.reload();
    try {
      final saved = Store.I.get(keySession);
      // The session's token, if a session is saved.
      Object? token;
      if (saved != null) {
        final session = (jsonDecode(saved) as Map)['session'] as Map?;
        if (session != null) {
          token = session['token'];
        }
      }
      if (token is String) {
        final response = await http.get(Uri.parse('$siteOrigin/api/boards/list'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw StateError('HTTP ${response.statusCode}');
        }
        _boards = boardsFromJson((jsonDecode(response.body) as Map)['boards']);
      } else {
        String? guestBoards = Store.I.get(keyGuestBoards);
        if (guestBoards == null) {
          guestBoards = '[]';
        }
        _boards = boardsFromJson(jsonDecode(guestBoards));
      }
      _error = null;
    } catch (error) {
      _error = 'Couldn’t get the cards just now';
    }
    _board = _boards.where((board) {
      return board['id'] == _widgetEntry['code'];
    }).firstOrNull;
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  /// The widget: a rounded card with its top bar, then either the board picker or the cards.
  @override
  Widget build(BuildContext context) {
    final themeController = ThemeController.I;
    final theme = buildTheme(look: lookUwuApps, brightness: themeController.brightness, brand: themeController.colorTheme.color, desktop: true);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Builder(
        builder: (context) {
          final colors = UwuColors.of(context);
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Container(
              decoration: BoxDecoration(
                color: colors.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _top(colors),
                  Expanded(child: _content(colors)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Under the top bar: the board picker while setting up, or else the cards.
  Widget _content(UwuColors colors) {
    if (_settingUp) {
      return _setupView(colors);
    } else {
      return _cards(colors);
    }
  }

  /// The top bar's title: the board's name, or 'Desktop widget' while setting up.
  String _title() {
    if (_settingUp) {
      return 'Desktop widget';
    }
    Object? name;
    final board = _board;
    if (board != null) {
      name = board['name'];
    }
    if (name == null) {
      name = _widgetEntry['name'];
    }
    if (name == null) {
      name = '';
    }
    return '$name';
  }

  /// The top bar: dragged to move the window, with the title and the widget's own buttons
  /// (refresh, change the board, keep on top, remove).
  Widget _top(UwuColors colors) {
    Widget button(String icon, String label, VoidCallback onTap, {bool highlighted = false}) {
      Color iconColor;
      if (highlighted) {
        iconColor = colors.brandInk;
      } else {
        iconColor = colors.muted;
      }
      return Tooltip(
        excludeFromSemantics: true,
        message: label,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: AppIcon(icon, size: 14, color: iconColor),
          ),
        ),
      );
    }

    String pinLabel;
    if (_widgetEntry['onTop'] == true) {
      pinLabel = 'Stop keeping on top';
    } else {
      pinLabel = 'Keep on top of other windows';
    }
    return Container(
      color: colors.surfaceStrong,
      padding: const EdgeInsets.only(left: 10, right: 4),
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Container(
                alignment: Alignment.centerLeft,
                child: Text(
                  _title(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.ink, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          if (!_settingUp) ...[
            button('refresh', 'Refresh', _load),
            button('pencil', 'Change what it shows', () {
              setState(() {
                _settingUp = true;
              });
            }),
          ],
          button(
            'pin',
            pinLabel,
            () async {
              final keepOnTop = _widgetEntry['onTop'] != true;
              _update({'onTop': keepOnTop});
              await windowManager.setAlwaysOnTop(keepOnTop);
              setState(() {});
            },
            highlighted: _widgetEntry['onTop'] == true,
          ),
          button('close', 'Remove', () async {
            DeskWidgets._save(
              DeskWidgets._all().where((entry) {
                return entry['id'] != widget.id;
              }).toList(),
            );
            await windowManager.destroy();
          }),
        ],
      ),
    );
  }

  /// A board's row in the picker is filled in when it's the one shown now.
  Color? _tileColorFor(Json board, UwuColors colors) {
    if (board['id'] == _widgetEntry['code']) {
      return colors.brandFill;
    } else {
      return null;
    }
  }

  /// The setup state: a list of the boards to pick from.
  Widget _setupView(UwuColors colors) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_boards.isEmpty) {
      String? message = _error;
      if (message == null) {
        message = 'Make a board in uwuBoard first.';
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.muted, fontSize: 12),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text('Pick a board to show its due cards', style: TextStyle(color: colors.muted, fontSize: 12)),
        ),
        for (final board in _boards)
          ListTile(
            dense: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tileColor: _tileColorFor(board, colors),
            title: Text('${board['name']}', style: TextStyle(color: colors.ink, fontSize: 13)),
            onTap: () {
              _update({'code': board['id'], 'name': board['name']});
              setState(() {
                _board = board;
                _settingUp = false;
              });
            },
          ),
      ],
    );
  }

  /// The board's due cards, each with when it's due (red overdue, amber today); a click opens
  /// the board in the main window.
  Widget _cards(UwuColors colors) {
    final board = _board;
    if (board == null) {
      String message;
      if (_loading) {
        message = '';
      } else {
        final error = _error;
        if (error != null) {
          message = error;
        } else {
          message = 'That board is gone. Change what it shows.';
        }
      }
      return Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.muted, fontSize: 12),
        ),
      );
    }
    final due = dueCards(board);
    if (due.isEmpty) {
      return Center(child: Text('No cards due', style: TextStyle(color: colors.muted, fontSize: 12)));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: due.length,
      separatorBuilder: (context, index) {
        return Divider(height: 1, color: colors.border);
      },
      itemBuilder: (context, index) {
        final dueCard = due[index];
        Color colour;
        if (dueCard.days < 0) {
          colour = colors.error;
        } else if (dueCard.days == 0) {
          colour = colors.warn;
        } else {
          colour = colors.muted;
        }
        return InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: () {
            widgetChannel.invokeMethod('open', 'uwu://board/b/${board['id']}').catchError((Object error) {
              return null;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${dueCard.card['title']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.ink, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                Text(dueCard.when, style: TextStyle(color: colour, fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }
}
