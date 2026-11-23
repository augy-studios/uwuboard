// The edge tray (docs/edge-tray-spec.md, main-site/js/tray.js): the app's own actions and the
// open board's in a column at the top right, with a tab that slides it off the edge. Open
// unless it was last left collapsed. A long press on a button shows its label.
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../features/bug/bug_report.dart';
import '../features/card/card_sheet.dart';
import '../features/sync/sync_sheet.dart';
import '../features/theme/theme_sheet.dart';
import '../features/tour/tour.dart';
import '../theme/icons.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import 'nav.dart';
import 'state.dart';

const _trayKey = 'uwuboard.trayOpen';

class EdgeTray extends StatefulWidget {
  const EdgeTray({super.key});

  /// Whether it's open. On a wider screen the page keeps a strip clear for it while it is; on a
  /// phone it floats over the board instead (home.dart).
  static final ValueNotifier<bool> open = ValueNotifier(true);

  /// How far it reaches in from the right edge: just the tab when it's closed, and the tab, its
  /// gap, a button and the edge's margin when it's open.
  static const tabWidth = 26.0;
  static const openWidth = tabWidth + 6 + 44 + 10;

  @override
  State<EdgeTray> createState() {
    return _EdgeTrayState();
  }
}

/// How much further the board's sideways scroll runs at its end, so its last column (or the end
/// of the Timeline) can come out from under the open tray. On a phone the board takes the whole
/// width and the tray floats over its right edge (home.dart); elsewhere it's 0, as the page keeps
/// a strip clear instead, and a board drawn off screen for a screenshot has none.
class TrayClearance extends InheritedWidget {
  const TrayClearance({super.key, required this.end, required super.child});

  final double end;

  static double of(BuildContext context) {
    final clearance = context.dependOnInheritedWidgetOfExactType<TrayClearance>();
    if (clearance == null) {
      return 0;
    }
    return clearance.end;
  }

  @override
  bool updateShouldNotify(TrayClearance oldWidget) {
    return oldWidget.end != end;
  }
}

class _EdgeTrayState extends State<EdgeTray> {
  bool get _open {
    return EdgeTray.open.value;
  }

  @override
  void initState() {
    super.initState();
    EdgeTray.open.value = Store.instance.get(_trayKey) != '0';
  }

  /// Opens or closes the tray, and remembers which on this device.
  void _toggle() {
    setState(() {
      EdgeTray.open.value = !_open;
    });
    if (_open) {
      Store.instance.put(_trayKey, '1');
    } else {
      Store.instance.put(_trayKey, '0');
    }
  }

  /// One round button in the tray, with its label shown on a long press.
  Widget _button(String target, String icon, String label, VoidCallback onTap, {bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: KeyedSubtree(
        key: TourTargets.key(target),
        child: Tooltip(
          excludeFromSemantics: true,
          triggerMode: TooltipTriggerMode.longPress,
          message: label,
          preferBelow: false,
          child: GlassButton(icon: icon, label: label, onPressed: onTap, danger: danger),
        ),
      ),
    );
  }

  /// The tab on the left that slides the tray in and out, then the buttons themselves while
  /// it's open.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final app = AppState.instance;
    final board = app.activeBoard;
    final timeline = app.isTimeline(board);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final String tabLabel;
    final String tabIcon;
    if (_open) {
      tabLabel = 'Hide menu';
      tabIcon = 'chevron-right';
    } else {
      tabLabel = 'Show menu';
      tabIcon = 'chevron-left';
    }
    final int resizeMilliseconds;
    if (reduceMotion) {
      resizeMilliseconds = 0;
    } else {
      resizeMilliseconds = 220;
    }
    final Widget trayContent;
    if (!_open) {
      trayContent = const SizedBox(width: 0);
    } else {
      trayContent = _trayButtons(context, colors, app, board, timeline);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: KeyedSubtree(
            key: TourTargets.key('tray-tab'),
            child: Semantics(
              button: true,
              expanded: _open,
              label: tabLabel,
              excludeSemantics: true,
              child: Tooltip(
                excludeFromSemantics: true,
                message: tabLabel,
                child: Material(
                  color: colors.surfaceStrong,
                  shape: RoundedRectangleBorder(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                    side: BorderSide(color: colors.border),
                  ),
                  child: InkWell(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                    onTap: _toggle,
                    child: SizedBox(
                      width: 26,
                      height: 44,
                      child: Center(child: AppIcon(tabIcon, size: 16, color: colors.ink)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: Duration(milliseconds: resizeMilliseconds),
          curve: Curves.easeOutCubic,
          alignment: Alignment.centerLeft,
          child: trayContent,
        ),
      ],
    );
  }

  /// The column of buttons in the open tray: the app's own actions, then, with a board open,
  /// that board's (switch view, export, import over it, delete).
  Widget _trayButtons(BuildContext context, UwuColors colors, AppState app, Map<String, dynamic>? board, bool timeline) {
    final String themeIcon;
    if (ThemeController.instance.mode == 'dark') {
      themeIcon = 'moon';
    } else {
      themeIcon = 'sun';
    }
    final String viewIcon;
    final String viewLabel;
    if (timeline) {
      viewIcon = 'kanban';
      viewLabel = 'Show as Kanban';
    } else {
      viewIcon = 'timeline';
      viewLabel = 'Show as Timeline';
    }
    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 10),
      child: KeyedSubtree(
        key: TourTargets.key('tray-buttons'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _button('tray-theme', themeIcon, 'Theme: colour, light or dark', () {
              openThemeSheet(context);
            }),
            _button('tray-sync', 'sync', 'Sync with another device', () {
              openSync(context);
            }),
            _button('tray-tour', 'help', 'Show me around', () {
              openTourPicker(context);
            }),
            _button('tray-bug', 'bug', 'Report a bug', () {
              openBugReport(context);
            }),
            if (board != null) ...[
              Container(width: 22, height: 1, margin: const EdgeInsets.only(bottom: 8), color: colors.border),
              _button('tray-view', viewIcon, viewLabel, app.toggleView),
              _button('tray-export', 'file-export', 'Export this board to a file', exportActiveBoard),
              _button('tray-import', 'file-import', 'Import a board file over this board', importOverActiveBoard),
              _button('tray-delete', 'trash', 'Delete this board', () async {
                if (await AppNavigation.confirm('Delete board "${board['name']}"?')) {
                  await app.deleteBoard(board);
                }
              }, danger: true),
            ],
          ],
        ),
      ),
    );
  }
}
