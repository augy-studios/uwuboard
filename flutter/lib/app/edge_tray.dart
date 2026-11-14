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
  State<EdgeTray> createState() => _EdgeTrayState();
}

/// How much further the board's sideways scroll runs at its end, so its last column (or the end
/// of the Timeline) can come out from under the open tray. On a phone the board takes the whole
/// width and the tray floats over its right edge (home.dart); elsewhere it's 0, as the page keeps
/// a strip clear instead, and a board drawn off screen for a screenshot has none.
class TrayClearance extends InheritedWidget {
  const TrayClearance({super.key, required this.end, required super.child});

  final double end;

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TrayClearance>()?.end ?? 0;

  @override
  bool updateShouldNotify(TrayClearance oldWidget) => oldWidget.end != end;
}

class _EdgeTrayState extends State<EdgeTray> {
  bool get _open => EdgeTray.open.value;

  @override
  void initState() {
    super.initState();
    EdgeTray.open.value = Store.I.get(_trayKey) != '0';
  }

  void _toggle() {
    setState(() => EdgeTray.open.value = !_open);
    Store.I.put(_trayKey, _open ? '1' : '0');
  }

  Widget _button(String target, String icon, String label, VoidCallback onTap, {bool danger = false}) => Padding(
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

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final app = AppState.I;
    final board = app.activeBoard;
    final timeline = app.isTimeline(board);
    final reduce = MediaQuery.disableAnimationsOf(context);
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
              label: _open ? 'Hide menu' : 'Show menu',
              excludeSemantics: true,
              child: Tooltip(
                excludeFromSemantics: true,
                message: _open ? 'Hide menu' : 'Show menu',
                child: Material(
                  color: c.surfaceStrong,
                  shape: RoundedRectangleBorder(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                    side: BorderSide(color: c.border),
                  ),
                  child: InkWell(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                    onTap: _toggle,
                    child: SizedBox(
                      width: 26,
                      height: 44,
                      child: Center(child: AppIcon(_open ? 'chevron-right' : 'chevron-left', size: 16, color: c.ink)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: Duration(milliseconds: reduce ? 0 : 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.centerLeft,
          child: !_open
              ? const SizedBox(width: 0)
              : Padding(
                  padding: const EdgeInsets.only(left: 6, right: 10),
                  child: KeyedSubtree(
                    key: TourTargets.key('tray-buttons'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _button('tray-theme', ThemeController.I.mode == 'dark' ? 'moon' : 'sun', 'Theme: colour, light or dark', () => openThemeSheet(context)),
                        _button('tray-sync', 'sync', 'Sync with another device', () => openSync(context)),
                        _button('tray-tour', 'help', 'Show me around', () => openTourPicker(context)),
                        _button('tray-bug', 'bug', 'Report a bug', () => openBugReport(context)),
                        if (board != null) ...[
                          Container(width: 22, height: 1, margin: const EdgeInsets.only(bottom: 8), color: c.border),
                          _button('tray-view', timeline ? 'kanban' : 'timeline', timeline ? 'Show as Kanban' : 'Show as Timeline', app.toggleView),
                          _button('tray-export', 'file-export', 'Export this board to a file', exportActiveBoard),
                          _button('tray-import', 'file-import', 'Import a board file over this board', importOverActiveBoard),
                          _button('tray-delete', 'trash', 'Delete this board', () async {
                            if (await AppNav.confirm('Delete board "${board['name']}"?')) await app.deleteBoard(board);
                          }, danger: true),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
