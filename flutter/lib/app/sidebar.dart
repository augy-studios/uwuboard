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

  /// Closes the drawer the sidebar sits in, if there is one round [context].
  static void _closeDrawerOf(BuildContext context) {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null) {
      scaffold.closeDrawer();
    }
  }

  /// Builds either the folded rail (the boards' initials) or the full panel: the account, the
  /// coffee link, the list of boards, Updates on Android, and New Board.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final app = AppState.instance;

    /// Opens a board, and closes the drawer when the sidebar is in one.
    void pick(String id) {
      app.selectBoard(id);
      if (inDrawer) {
        _closeDrawerOf(context);
      }
    }

    Future<void> newBoard() async {
      // From the drawer, the drawer goes first, and the window opens from the app's own context.
      if (inDrawer) {
        _closeDrawerOf(context);
      }
      final BuildContext? windowContext;
      if (inDrawer) {
        windowContext = AppNavigation.context;
      } else {
        windowContext = context;
      }
      if (windowContext != null) {
        await openNewBoard(windowContext);
      }
    }

    /// What a board's right-click (or long-press) menu offers.
    List<MenuAction> boardMenu(Map<String, dynamic> board) {
      final extraActionsFor = desktopBoardActions;
      List<MenuAction> extraActions = const [];
      if (extraActionsFor != null) {
        extraActions = extraActionsFor(board);
      }
      return [
        MenuAction('Open', () {
          pick('${board['id']}');
        }, icon: 'arrow-right'),
        MenuAction('Rename', () async {
          final name = await AppNavigation.prompt('Board name:', initial: '${board['name']}');
          if (name != null) {
            app.renameBoard(board, name);
          }
        }, icon: 'pencil'),
        MenuAction('Copy link', () async {
          await copyText(linkFor(boardId: '${board['id']}')!);
          AppNavigation.toast('Link copied');
        }, icon: 'link'),
        ...extraActions,
        MenuAction(
          'Delete board',
          () async {
            if (await AppNavigation.confirm('Delete board "${board['name']}"?')) {
              await app.deleteBoard(board);
            }
          },
          icon: 'trash',
          danger: true,
        ),
      ];
    }

    // Folded to a rail: one letter per board.
    if (collapsed) {
      return _frame(
        context,
        colors,
        child: SafeArea(
          right: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              MiniButton(icon: 'chevron-right', label: 'Expand sidebar', onPressed: onToggle, size: 36),
              const SizedBox(height: 8),
              InkWell(
                mouseCursor: WidgetStateMouseCursor.clickable,
                customBorder: const CircleBorder(),
                onTap: () {
                  openProfile(context);
                },
                child: const Avatar(size: 34),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    for (final board in app.boards)
                      _railTile(
                        colors,
                        board,
                        board['id'] == app.activeBoardId,
                        onTap: () {
                          pick('${board['id']}');
                        },
                        actions: () {
                          return boardMenu(board);
                        },
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

    // The full panel. In a drawer its chevron closes the drawer; beside the board it folds it.
    final String foldLabel;
    final VoidCallback? foldAction;
    if (inDrawer) {
      foldLabel = 'Close';
      foldAction = () {
        _closeDrawerOf(context);
      };
    } else {
      foldLabel = 'Collapse sidebar';
      foldAction = onToggle;
    }
    final String profileTooltip;
    if (app.isGuest) {
      profileTooltip = 'Guest';
    } else {
      profileTooltip = 'Profile';
    }
    return _frame(
      context,
      colors,
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
                      style: TextStyle(fontSize: 20, color: colors.ink, fontWeight: FontWeight.w700),
                    ),
                  ),
                  MiniButton(
                    icon: 'chevron-left',
                    label: foldLabel,
                    onPressed: foldAction,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.surfaceStrong,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Tooltip(
                      message: profileTooltip,
                      child: InkWell(
                        mouseCursor: WidgetStateMouseCursor.clickable,
                        customBorder: const CircleBorder(),
                        onTap: () {
                          openProfile(context);
                        },
                        child: const Avatar(size: 36),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.shownName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.ink, fontWeight: FontWeight.w600),
                          ),
                          Text(app.role, style: TextStyle(color: colors.muted, fontSize: 12)),
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
                onPressed: () {
                  launchUrl(_coffee, mode: LaunchMode.externalApplication);
                },
                icon: AppIcon('coffee', size: 14, color: colors.ink),
                label: const Text('Buy Augy a Coffee'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
              child: Text(
                'BOARDS',
                style: TextStyle(color: colors.muted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: KeyedSubtree(
                key: TourTargets.key('board-list'),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    for (final board in app.boards)
                      _boardTile(
                        colors,
                        board,
                        board['id'] == app.activeBoardId,
                        onTap: () {
                          pick('${board['id']}');
                        },
                        actions: () {
                          return boardMenu(board);
                        },
                      ),
                  ],
                ),
              ),
            ),
            if (Environment.android)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: ListenableBuilder(
                  listenable: AndroidUpdates.instance,
                  builder: (context, child) {
                    return _updatesButton(context, colors);
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
              child: OutlinedButton.icon(
                key: const ValueKey('new-board'),
                onPressed: newBoard,
                icon: AppIcon('plus', size: 14, color: colors.ink),
                label: const Text('New Board'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One board on the folded rail: its first letter, with its name as a tooltip.
  Widget _railTile(
    UwuColors colors,
    Map<String, dynamic> board,
    bool selected, {
    required VoidCallback onTap,
    required List<MenuAction> Function() actions,
  }) {
    final String letter;
    if ('${board['name']}'.isEmpty) {
      letter = '?';
    } else {
      letter = '${board['name']}'.characters.first.toUpperCase();
    }
    final Color letterColor;
    if (selected) {
      letterColor = colors.onBrand;
    } else {
      letterColor = colors.ink;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tooltip(
        message: '${board['name']}',
        child: ContextMenuRegion(
          actions: actions,
          child: Hoverable(
            selected: selected,
            onTap: onTap,
            child: SizedBox(
              height: 40,
              child: Center(
                child: Text(
                  letter,
                  style: TextStyle(fontSize: 16, color: letterColor, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One board in the full list: a dot, its view's icon and its name.
  Widget _boardTile(
    UwuColors colors,
    Map<String, dynamic> board,
    bool selected, {
    required VoidCallback onTap,
    required List<MenuAction> Function() actions,
  }) {
    final Color dotColor;
    final Color iconColor;
    final Color nameColor;
    if (selected) {
      dotColor = colors.brandInk;
      iconColor = colors.onBrand;
      nameColor = colors.onBrand;
    } else {
      dotColor = colors.muted.withValues(alpha: 0.5);
      iconColor = colors.muted;
      nameColor = colors.ink;
    }
    final String viewIcon;
    if (board['view'] == 'timeline') {
      viewIcon = 'timeline';
    } else {
      viewIcon = 'kanban';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ContextMenuRegion(
        actions: actions,
        longPress: !Environment.desktop,
        child: Semantics(
          selected: selected,
          button: true,
          child: Hoverable(
            key: ValueKey('board-${board['id']}'),
            selected: selected,
            onTap: onTap,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                AppIcon(viewIcon, size: 15, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${board['name']}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: nameColor, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Android's Updates button: highlighted, with the version, when a newer release is out.
  Widget _updatesButton(BuildContext context, UwuColors colors) {
    final newerRelease = AndroidUpdates.instance.newer;
    final Color updateColor;
    final String updateLabel;
    if (newerRelease != null) {
      updateColor = colors.brandInk;
      updateLabel = 'Update to ${newerRelease['version']}';
    } else {
      updateColor = colors.muted;
      updateLabel = 'Updates · ${AndroidUpdates.instance.mine}';
    }
    return TextButton.icon(
      key: const ValueKey('updates'),
      style: TextButton.styleFrom(foregroundColor: updateColor, alignment: Alignment.centerLeft),
      onPressed: () {
        if (inDrawer) {
          _closeDrawerOf(context);
        }
        openUpdates();
      },
      icon: AppIcon('download', size: 15, color: updateColor),
      label: Text(updateLabel),
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
  Widget _frame(BuildContext context, UwuColors colors, {required Widget child}) {
    final double fullWidth;
    if (Environment.desktop && MediaQuery.sizeOf(context).width > Environment.splitWidth) {
      fullWidth = 300.0;
    } else {
      fullWidth = 260.0;
    }
    if (inDrawer) {
      return Container(
        width: fullWidth,
        decoration: BoxDecoration(
          color: Color.alphaBlend(colors.surfaceStrong, colors.background),
          border: Border(right: BorderSide(color: colors.edge)),
        ),
        child: child,
      );
    }
    final double width;
    if (collapsed) {
      width = railWidth;
    } else {
      width = fullWidth;
    }
    final int durationMilliseconds;
    if (MediaQuery.disableAnimationsOf(context)) {
      durationMilliseconds = 0;
    } else {
      durationMilliseconds = 250;
    }
    return AnimatedContainer(
      key: const ValueKey('sidebar'),
      duration: Duration(milliseconds: durationMilliseconds),
      curve: Curves.ease,
      width: width,
      color: colors.surface,
      // Drawn over what's in it, so it's on the edge at every width and takes no room.
      foregroundDecoration: BoxDecoration(border: Border(right: BorderSide(color: colors.edge))),
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
