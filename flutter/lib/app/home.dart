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
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffold = GlobalKey<ScaffoldState>();
  bool _collapsed = false;
  DateTime? _backAt;

  @override
  void initState() {
    super.initState();
    Tour.currentPage = _page;
    Tour.openPage = _openPage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Tour.init(skipFirst: AppState.I.pendingSyncCode != null);
      Links.appShown();
    });
  }

  /// What's on screen, for the tours.
  String? _page() {
    final app = AppState.I;
    if (!app.shown) return null;
    if (AppSheet.isOpen('newboard')) return 'newboard';
    if (AppSheet.isOpen('card')) return 'card';
    final board = app.activeBoard;
    if (board == null) return 'empty';
    return app.isTimeline(board) ? 'timeline' : 'kanban';
  }

  Future<void> _openPage(String page) async {
    final app = AppState.I;
    final ctx = AppNav.context;
    if (ctx == null) return;
    if (page == 'newboard') {
      AppNav.closeSheets();
      unawaited(openNewBoard(ctx));
      return;
    }
    if (AppSheet.isOpen('newboard') || AppSheet.isOpen('card')) AppNav.closeSheets();
    if (page == 'card') {
      final board = app.activeBoard;
      if (board == null) return;
      final cards = [for (final col in (board['columns'] as List)) ...((col as Map)['cards'] as List)];
      if (cards.isEmpty) return;
      final first = cards.first as Map;
      unawaited(openCardSheet(ctx, board, '${first['id']}'));
      return;
    }
    if (page == 'kanban' || page == 'timeline') app.setViewOverride(page);
    // 'empty' needs nothing more: the windows over it have gone.
  }

  void _back(bool didPop, Object? _) {
    if (didPop) return;
    if (_scaffold.currentState?.isDrawerOpen ?? false) {
      _scaffold.currentState!.closeDrawer();
      return;
    }
    if (Tour.active) {
      Tour.end();
      return;
    }
    final now = DateTime.now();
    if (_backAt != null && now.difference(_backAt!) < const Duration(seconds: 2)) {
      _backAt = null;
      // To the background, not closed: a sync running carries on.
      Native.tryCall('App', 'background').then((r) {
        if (r == null) SystemNavigator.pop();
      });
      return;
    }
    _backAt = now;
    AppNav.toast('Press back again to exit');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final c = UwuColors.of(context);
        final app = AppState.I;
        final width = MediaQuery.sizeOf(context).width;
        final phone = width <= Env.phoneWidth;
        // On a computer between 720 and 1024 wide, the boards fold to a rail by themselves.
        final collapsed = _collapsed || (Env.desktop && width <= Env.splitWidth);
        final board = app.activeBoard;
        final body = Stack(
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: EdgeTray.open,
                // A strip kept clear for the open tray, as the site does, so it never covers a column.
                builder: (context, trayOpen, child) => AnimatedPadding(
                  duration: Duration(milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 220),
                  padding: EdgeInsets.only(right: trayOpen ? 84 : 30),
                  child: child,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: phone ? 66 : 70),
                    Expanded(
                      child: board == null
                          ? _empty(c)
                          : AnimatedSwitcher(
                              duration: Duration(milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 200),
                              // The board from the top, filling the space, never centred in it.
                              layoutBuilder: (current, previous) =>
                                  Stack(alignment: Alignment.topLeft, fit: StackFit.expand, children: [...previous, ?current]),
                              child: app.isTimeline(board)
                                  ? TimelineView(key: ValueKey('tl-${board['id']}'), board: board)
                                  : KanbanView(key: ValueKey('kb-${board['id']}'), board: board),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(top: 10, left: phone ? 10 : 16, right: 90, child: _topBar(c, board, phone, collapsed)),
            const Positioned(top: 10, right: 0, child: EdgeTray()),
          ],
        );

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: _back,
          child: Scaffold(
            key: _scaffold,
            drawer: phone ? Drawer(width: 290, child: Sidebar(inDrawer: true, onToggle: () {})) : null,
            body: Column(
              children: [
                const UpdateBar(),
                ValueListenableBuilder<bool>(
                  valueListenable: Api.offline,
                  builder: (context, off, _) => off
                      ? Container(
                          width: double.infinity,
                          color: c.warn.withValues(alpha: 0.18),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: SafeArea(
                            bottom: false,
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                app.isGuest
                                    ? 'You’re offline. Your boards are on this device.'
                                    : 'You’re offline. Changes are shown here and saved once you’re back online.',
                                style: TextStyle(color: c.ink, fontSize: 13),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!phone) Sidebar(collapsed: collapsed, onToggle: () => setState(() => _collapsed = !_collapsed)),
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

  Widget _topBar(UwuColors c, Map<String, dynamic>? board, bool phone, bool collapsed) {
    return Row(
      children: [
        if (phone || collapsed && !Env.desktop)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: KeyedSubtree(
              key: TourTargets.key('menu'),
              child: GlassButton(
                icon: 'menu',
                label: 'Boards',
                onPressed: () => phone ? _scaffold.currentState?.openDrawer() : setState(() => _collapsed = !_collapsed),
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
                      board == null ? 'Select a board' : '${board['name']}',
                      key: const ValueKey('board-title'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: phone ? 18 : 21, color: c.ink, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                if (board != null)
                  MiniButton(
                    icon: 'pencil',
                    label: 'Rename board',
                    onPressed: () async {
                      final name = await AppNav.prompt('Board name:', initial: '${board['name']}');
                      if (name != null) AppState.I.renameBoard(board, name);
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

  Widget _empty(UwuColors c) {
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
              style: TextStyle(color: c.muted, fontSize: 15),
            ),
            const SizedBox(height: 14),
            KeyedSubtree(
              key: TourTargets.key('empty-new-board'),
              child: FilledButton.icon(
                key: const ValueKey('empty-new-board'),
                onPressed: () => openNewBoard(context),
                icon: AppIcon('plus', size: 16, color: c.onBrand),
                label: const Text('Create Board'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBars extends CustomPainter {
  _EmptyBars(this.colour);
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;
    final p = Paint()..color = colour;
    canvas.drawRRect(RRect.fromLTRBR(4 * s, 16 * s, 20 * s, 48 * s, Radius.circular(4 * s)), p);
    canvas.drawRRect(RRect.fromLTRBR(24 * s, 10 * s, 40 * s, 48 * s, Radius.circular(4 * s)), p..color = colour.withValues(alpha: 0.65));
    canvas.drawRRect(RRect.fromLTRBR(44 * s, 22 * s, 60 * s, 48 * s, Radius.circular(4 * s)), p..color = colour.withValues(alpha: 0.35));
  }

  @override
  bool shouldRepaint(_EmptyBars old) => false;
}
