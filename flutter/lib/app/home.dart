// The app once someone's signed in or a guest (the site's #app): the sidebar, the board's title
// floating at the top with the menu button, the edge tray opposite it, and the board as columns
// or a Timeline, or the empty state with Create Board.
//
// Back on Android closes what's open, then asks once more before leaving, and the second press
// sends the app to the background rather than closing it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api.dart';
import '../features/board/column_sheets.dart';
import '../features/board/kanban_view.dart';
import '../features/card/card_sheet.dart';
import '../features/timeline/timeline_view.dart';
import '../features/tour/tour.dart';
import '../features/update/update_bar.dart';
import '../native/bridge.dart';
import '../theme/icons.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/sheet.dart';
import 'edge_tray.dart';
import 'env.dart';
import 'links.dart';
import 'nav.dart';
import 'sidebar.dart';
import 'state.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() {
    return _HomeScreenState();
  }
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _collapsed = false;

  /// When Back was last pressed with nothing left to close: a second press soon after leaves.
  DateTime? _lastBackPressAt;

  @override
  void initState() {
    super.initState();
    Tour.currentPage = _page;
    Tour.openPage = _openPage;
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      Tour.init(skipFirst: AppState.instance.pendingSyncCode != null);
      Links.appShown();
    });
  }

  /// What's on screen, for the tours.
  String? _page() {
    final app = AppState.instance;
    if (!app.shown) {
      return null;
    }
    if (AppSheet.isOpen('newboard')) {
      return 'newboard';
    }
    if (AppSheet.isOpen('card')) {
      return 'card';
    }
    final board = app.activeBoard;
    if (board == null) {
      return 'empty';
    }
    if (app.isTimeline(board)) {
      return 'timeline';
    } else {
      return 'kanban';
    }
  }

  /// Brings up a page a tour asks for: the New Board window, a card, or one of the two views.
  Future<void> _openPage(String page) async {
    final app = AppState.instance;
    final currentContext = AppNavigation.context;
    if (currentContext == null) {
      return;
    }
    if (page == 'newboard') {
      AppNavigation.closeSheets();
      unawaited(openNewBoard(currentContext));
      return;
    }
    if (AppSheet.isOpen('newboard') || AppSheet.isOpen('card')) {
      AppNavigation.closeSheets();
    }
    if (page == 'card') {
      final board = app.activeBoard;
      if (board == null) {
        return;
      }
      final cards = [for (final column in (board['columns'] as List)) ...((column as Map)['cards'] as List)];
      if (cards.isEmpty) {
        return;
      }
      final first = cards.first as Map;
      unawaited(openCardSheet(currentContext, board, '${first['id']}'));
      return;
    }
    if (page == 'kanban' || page == 'timeline') {
      app.setViewOverride(page);
    }
    // 'empty' needs nothing more: the windows over it have gone.
  }

  /// Android's Back: closes the drawer or the tour first, then asks for a second press within
  /// two seconds before sending the app to the background.
  void _back(bool didPop, Object? result) {
    if (didPop) {
      return;
    }
    final scaffoldState = _scaffoldKey.currentState;
    if (scaffoldState != null && scaffoldState.isDrawerOpen) {
      scaffoldState.closeDrawer();
      return;
    }
    if (Tour.active) {
      Tour.end();
      return;
    }
    final now = DateTime.now();
    final lastBackPressAt = _lastBackPressAt;
    if (lastBackPressAt != null && now.difference(lastBackPressAt) < const Duration(seconds: 2)) {
      _lastBackPressAt = null;
      // To the background, not closed: a sync running carries on.
      Native.tryCall('App', 'background').then((response) {
        if (response == null) {
          SystemNavigator.pop();
        }
      });
      return;
    }
    _lastBackPressAt = now;
    AppNavigation.toast('Press back again to exit');
  }

  /// [milliseconds], or 0 when the device asks for no animations.
  int _animationMilliseconds(BuildContext context, int milliseconds) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return 0;
    } else {
      return milliseconds;
    }
  }

  /// The whole signed-in screen: the update and offline bars on top, the sidebar (or a drawer on
  /// a phone), and the board with its floating title bar and the edge tray.
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, listenableChild) {
        final colors = UwuColors.of(context);
        final app = AppState.instance;
        final width = MediaQuery.sizeOf(context).width;
        final phone = width <= Environment.phoneWidth;
        // On a computer between 720 and 1024 wide, the boards fold to a rail by themselves.
        final collapsed = _collapsed || (Environment.desktop && width <= Environment.splitWidth);
        final board = app.activeBoard;
        final double topSpace;
        if (phone) {
          topSpace = 66;
        } else {
          topSpace = 70;
        }
        final double titleBarLeft;
        if (phone) {
          titleBarLeft = 10;
        } else {
          titleBarLeft = 16;
        }
        final body = Stack(
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: EdgeTray.open,
                // On a wider screen, a strip kept clear for the tray, so it never covers a column.
                // On a phone that strip is a fifth of the screen: the board takes the whole width
                // and the tray floats over its right edge, the board scrolling far enough for its
                // last column to come out from under the open tray (TrayClearance).
                builder: (context, trayOpen, child) {
                  double rightPadding;
                  if (phone) {
                    rightPadding = 0;
                  } else if (trayOpen) {
                    rightPadding = 84;
                  } else {
                    rightPadding = 30;
                  }
                  double clearance;
                  if (phone && trayOpen) {
                    clearance = EdgeTray.openWidth;
                  } else {
                    clearance = 0;
                  }
                  return AnimatedPadding(
                    duration: Duration(milliseconds: _animationMilliseconds(context, 220)),
                    padding: EdgeInsets.only(right: rightPadding),
                    child: TrayClearance(end: clearance, child: child!),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: topSpace),
                    Expanded(
                      child: _boardArea(context, colors, app, board),
                    ),
                  ],
                ),
              ),
            ),
            // Level with the tray, so it stops short of it: on a phone just short of the tab, or
            // of the open tray, following it as it opens and closes.
            ValueListenableBuilder<bool>(
              valueListenable: EdgeTray.open,
              builder: (context, trayOpen, child) {
                double titleBarRight;
                if (phone) {
                  if (trayOpen) {
                    titleBarRight = EdgeTray.openWidth + 6;
                  } else {
                    titleBarRight = EdgeTray.tabWidth + 8;
                  }
                } else {
                  titleBarRight = 90;
                }
                return AnimatedPositioned(
                  duration: Duration(milliseconds: _animationMilliseconds(context, 220)),
                  curve: Curves.easeOutCubic,
                  top: 10,
                  left: titleBarLeft,
                  right: titleBarRight,
                  child: _topBar(colors, board, phone, collapsed),
                );
              },
            ),
            const Positioned(top: 10, right: 0, child: EdgeTray()),
          ],
        );

        // On a phone the boards live in a drawer that slides in; wider, they sit beside the board.
        Widget? drawer;
        if (phone) {
          drawer = Drawer(
            width: 290,
            child: Sidebar(
              inDrawer: true,
              onToggle: () {},
            ),
          );
        } else {
          drawer = null;
        }
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: _back,
          child: Scaffold(
            key: _scaffoldKey,
            drawer: drawer,
            body: Column(
              children: [
                const UpdateBar(),
                ValueListenableBuilder<bool>(
                  valueListenable: Api.offline,
                  builder: (context, offline, child) {
                    if (offline) {
                      return _offlineBar(colors, app);
                    } else {
                      return const SizedBox.shrink();
                    }
                  },
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!phone)
                        Sidebar(
                          collapsed: collapsed,
                          onToggle: () {
                            setState(() {
                              _collapsed = !_collapsed;
                            });
                          },
                        ),
                      Expanded(
                        child: SafeArea(left: phone, child: body),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The bar across the top that says the device is offline.
  Widget _offlineBar(UwuColors colors, AppState app) {
    final String message;
    if (app.isGuest) {
      message = 'You’re offline. Your boards are on this device.';
    } else {
      message = 'You’re offline. Changes are shown here and saved once you’re back online.';
    }
    return Container(
      width: double.infinity,
      color: colors.warning.withValues(alpha: 0.18),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SafeArea(
        bottom: false,
        child: Semantics(
          liveRegion: true,
          child: Text(
            message,
            style: TextStyle(color: colors.ink, fontSize: 13),
          ),
        ),
      ),
    );
  }

  /// The open board, as a timeline or as columns, fading from one to the other; or the empty
  /// state when no board is open.
  Widget _boardArea(BuildContext context, UwuColors colors, AppState app, Map<String, dynamic>? board) {
    if (board == null) {
      return _emptyState(colors);
    }
    final Widget boardView;
    if (app.isTimeline(board)) {
      boardView = TimelineView(key: ValueKey('tl-${board['id']}'), board: board);
    } else {
      boardView = KanbanView(key: ValueKey('kb-${board['id']}'), board: board);
    }
    return AnimatedSwitcher(
      duration: Duration(milliseconds: _animationMilliseconds(context, 200)),
      // The board from the top, filling the space, never centred in it.
      layoutBuilder: (current, previous) {
        return Stack(
          alignment: Alignment.topLeft,
          fit: StackFit.expand,
          children: [
            ...previous,
            if (current != null) current,
          ],
        );
      },
      child: boardView,
    );
  }

  /// The floating bar at the top: the menu button where the boards are hidden, then the board's
  /// name with a button to rename it.
  Widget _topBar(UwuColors colors, Map<String, dynamic>? board, bool phone, bool collapsed) {
    final String title;
    if (board == null) {
      title = 'Select a board';
    } else {
      title = '${board['name']}';
    }
    final double titleSize;
    if (phone) {
      titleSize = 18;
    } else {
      titleSize = 21;
    }
    return Row(
      children: [
        if (phone || collapsed && !Environment.desktop)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: KeyedSubtree(
              key: TourTargets.key('menu'),
              child: GlassButton(
                icon: 'menu',
                label: 'Boards',
                onPressed: () {
                  if (phone) {
                    final scaffoldState = _scaffoldKey.currentState;
                    if (scaffoldState != null) {
                      scaffoldState.openDrawer();
                    }
                  } else {
                    setState(() {
                      _collapsed = !_collapsed;
                    });
                  }
                },
              ),
            ),
          ),
        Flexible(
          child: GlassPanel(
            radius: 24,
            padding: const EdgeInsets.fromLTRB(18, 8, 6, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      key: const ValueKey('board-title'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: titleSize, color: colors.ink, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                if (board != null)
                  MiniButton(
                    icon: 'pencil',
                    label: 'Rename board',
                    onPressed: () async {
                      final name = await AppNavigation.prompt('Board name:', initial: '${board['name']}');
                      if (name != null) {
                        AppState.instance.renameBoard(board, name);
                      }
                    },
                  )
                else
                  const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// What shows when no board is open: three faint bars, a line of text and Create Board.
  Widget _emptyState(UwuColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.35,
              child: SizedBox(width: 64, height: 64, child: CustomPaint(painter: _EmptyBars(const Color(0xFF22A85A)))),
            ),
            const SizedBox(height: 14),
            Text(
              'Select or create a board to get started',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.muted, fontSize: 15),
            ),
            const SizedBox(height: 14),
            KeyedSubtree(
              key: TourTargets.key('empty-new-board'),
              child: FilledButton.icon(
                key: const ValueKey('empty-new-board'),
                onPressed: () {
                  openNewBoard(context);
                },
                icon: AppIcon('plus', size: 16, color: colors.onBrand),
                label: const Text('Create Board'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints three rounded bars, like little kanban columns, each fainter than the last.
class _EmptyBars extends CustomPainter {
  _EmptyBars(this.colour);
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 64-wide grid, scaled to the space given.
    final scale = size.width / 64;
    final paint = Paint();
    paint.color = colour;
    canvas.drawRRect(RRect.fromLTRBR(4 * scale, 16 * scale, 20 * scale, 48 * scale, Radius.circular(4 * scale)), paint);
    paint.color = colour.withValues(alpha: 0.65);
    canvas.drawRRect(RRect.fromLTRBR(24 * scale, 10 * scale, 40 * scale, 48 * scale, Radius.circular(4 * scale)), paint);
    paint.color = colour.withValues(alpha: 0.35);
    canvas.drawRRect(RRect.fromLTRBR(44 * scale, 22 * scale, 60 * scale, 48 * scale, Radius.circular(4 * scale)), paint);
  }

  @override
  bool shouldRepaint(_EmptyBars oldDelegate) {
    return false;
  }
}
