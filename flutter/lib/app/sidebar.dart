// The sidebar (the site's #sidebar): who's signed in, the boards, New Board, and Buy Augy a
// Coffee. A drawer on a phone; beside the board on a wider screen, where it can fold to a
// narrow rail of the boards' initials.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../desktop/adaptive.dart';
import '../features/board/column_sheets.dart';
import '../features/profile/profile_sheet.dart';
import '../features/tour/tour.dart';
import '../features/update/update_bar.dart';
import '../theme/icons.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import 'env.dart';
import 'links.dart';
import 'nav.dart';
import 'state.dart';

final _coffee = Uri.parse('https://donate.stripe.com/28o2akeAr3hv0DK6oo');

/// Extra actions for a board's right-click menu on the desktop (the tray countdown, a desktop
/// widget), added by lib/desktop/.
List<MenuAction> Function(Map<String, dynamic> board)? desktopBoardActions;

class Sidebar extends StatelessWidget {
  const Sidebar({super.key, this.collapsed = false, this.onToggle, this.inDrawer = false});

  final bool collapsed;
  final VoidCallback? onToggle;
  final bool inDrawer;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final app = AppState.I;
    void pick(String id) {
      app.selectBoard(id);
      if (inDrawer) Scaffold.maybeOf(context)?.closeDrawer();
    }

    Future<void> newBoard() async {
      // From the drawer, the drawer goes first, and the window opens from the app's own context.
      if (inDrawer) Scaffold.maybeOf(context)?.closeDrawer();
      final ctx = inDrawer ? AppNav.context : context;
      if (ctx != null) await openNewBoard(ctx);
    }

    List<MenuAction> boardMenu(Map<String, dynamic> b) => [
      MenuAction('Open', () => pick('${b['id']}'), icon: 'arrow-right'),
      MenuAction('Rename', () async {
        final name = await AppNav.prompt('Board name:', initial: '${b['name']}');
        if (name != null) app.renameBoard(b, name);
      }, icon: 'pencil'),
      MenuAction('Copy link', () async {
        await copyText(linkFor(boardId: '${b['id']}')!);
        AppNav.toast('Link copied');
      }, icon: 'link'),
      ...?desktopBoardActions?.call(b),
      MenuAction(
        'Delete board',
        () async {
          if (await AppNav.confirm('Delete board "${b['name']}"?')) await app.deleteBoard(b);
        },
        icon: 'trash',
        danger: true,
      ),
    ];

    if (collapsed) {
      return _frame(
        context,
        c,
        child: SafeArea(
          right: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              MiniButton(icon: 'chevron-right', label: 'Expand sidebar', onPressed: onToggle, size: 36),
              const SizedBox(height: 8),
              InkWell(customBorder: const CircleBorder(), onTap: () => openProfile(context), child: const Avatar(size: 34)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    for (final b in app.boards)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Tooltip(
                          message: '${b['name']}',
                          child: ContextMenuRegion(
                            actions: () => boardMenu(b),
                            child: Hoverable(
                              selected: b['id'] == app.activeBoardId,
                              onTap: () => pick('${b['id']}'),
                              child: SizedBox(
                                height: 40,
                                child: Center(
                                  child: Text(
                                    '${b['name']}'.isEmpty ? '?' : '${b['name']}'.characters.first.toUpperCase(),
                                    style: TextStyle(fontSize: 16, color: b['id'] == app.activeBoardId ? c.onBrand : c.ink, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              MiniButton(icon: 'plus', label: 'New Board', onPressed: newBoard, size: 40),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    }

    return _frame(
      context,
      c,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/images/icon-512.png', width: 28, height: 28)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'uwuBoard',
                      style: TextStyle(fontSize: 20, color: c.ink, fontWeight: FontWeight.w700),
                    ),
                  ),
                  MiniButton(
                    icon: 'chevron-left',
                    label: inDrawer ? 'Close' : 'Collapse sidebar',
                    onPressed: inDrawer ? () => Scaffold.maybeOf(context)?.closeDrawer() : onToggle,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.surfaceStrong,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    Tooltip(
                      message: app.isGuest ? 'Guest' : 'Profile',
                      child: InkWell(customBorder: const CircleBorder(), onTap: () => openProfile(context), child: const Avatar(size: 36)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.shownName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
                          ),
                          Text(app.role, style: TextStyle(color: c.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                    MiniButton(icon: 'logout', label: 'Sign out', onPressed: app.logout),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(_coffee, mode: LaunchMode.externalApplication),
                icon: AppIcon('coffee', size: 14, color: c.ink),
                label: const Text('Buy Augy a Coffee'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
              child: Text(
                'BOARDS',
                style: TextStyle(color: c.muted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: KeyedSubtree(
                key: TourTargets.key('board-list'),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    for (final b in app.boards)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: ContextMenuRegion(
                          actions: () => boardMenu(b),
                          longPress: !Env.desktop,
                          child: Semantics(
                            selected: b['id'] == app.activeBoardId,
                            button: true,
                            child: Hoverable(
                              key: ValueKey('board-${b['id']}'),
                              selected: b['id'] == app.activeBoardId,
                              onTap: () => pick('${b['id']}'),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: b['id'] == app.activeBoardId ? c.brandInk : c.muted.withValues(alpha: 0.5),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  AppIcon(b['view'] == 'timeline' ? 'timeline' : 'kanban', size: 15, color: b['id'] == app.activeBoardId ? c.onBrand : c.muted),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${b['name']}',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: b['id'] == app.activeBoardId ? c.onBrand : c.ink, fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (Env.android)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: ListenableBuilder(
                  listenable: AndroidUpdates.I,
                  builder: (context, _) {
                    final n = AndroidUpdates.I.newer;
                    return TextButton.icon(
                      key: const ValueKey('updates'),
                      style: TextButton.styleFrom(foregroundColor: n != null ? c.brandInk : c.muted, alignment: Alignment.centerLeft),
                      onPressed: () {
                        if (inDrawer) Scaffold.maybeOf(context)?.closeDrawer();
                        openUpdates();
                      },
                      icon: AppIcon('download', size: 15, color: n != null ? c.brandInk : c.muted),
                      label: Text(n != null ? 'Update to ${n['version']}' : 'Updates · ${AndroidUpdates.I.mine}'),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
              child: OutlinedButton.icon(
                key: const ValueKey('new-board'),
                onPressed: newBoard,
                icon: AppIcon('plus', size: 14, color: c.ink),
                label: const Text('New Board'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The rail's width.
  static const railWidth = 64.0;

  /// What holds the sidebar: its width, its surface and the line along its right side.
  ///
  /// Beside the board it folds and unfolds as the site's does (main-site/style.css, .sidebar):
  /// the width eased over 250 ms with CSS's own `ease`, what's in it switched at once and clipped
  /// to the width while it changes. Folding, the rail shows at once and the empty surface beside
  /// it narrows; unfolding, the panel is laid out at its full width at once and uncovered as the
  /// sidebar widens. With animations turned off, it snaps, as the site does.
  Widget _frame(BuildContext context, UwuColors c, {required Widget child}) {
    final full = Env.desktop && MediaQuery.sizeOf(context).width > Env.splitWidth ? 300.0 : 260.0;
    if (inDrawer) {
      return Container(
        width: full,
        decoration: BoxDecoration(
          color: Color.alphaBlend(c.surfaceStrong, c.bg),
          border: Border(right: BorderSide(color: c.border)),
        ),
        child: child,
      );
    }
    final width = collapsed ? railWidth : full;
    return AnimatedContainer(
      key: const ValueKey('sidebar'),
      duration: Duration(milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 250),
      curve: Curves.ease,
      width: width,
      color: c.surface,
      // Drawn over what's in it, so it's on the edge at every width and takes no room.
      foregroundDecoration: BoxDecoration(border: Border(right: BorderSide(color: c.border))),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: width,
          maxWidth: width,
          child: child,
        ),
      ),
    );
  }
}
