// A board as a Timeline (main-site/js/timeline.js): the phases and their tasks down the left,
// each task a bar across its dates, a milestone a diamond, arrows from the tasks a task waits
// for (red when the dates clash), a line for today, and zoom by weeks, months or quarters. Drag
// a bar to move it or an end to change its length; press a day in an undated task's row to give
// it dates. Arrow keys move a focused bar a day; with Shift, its end only.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/edge_tray.dart' show TrayClearance;
import '../../app/env.dart';
import '../../app/nav.dart';
import '../../app/state.dart';
import '../../data/board.dart';
import '../../data/store.dart';
import '../../data/timeline_logic.dart';
import '../../theme/theme.dart';
import '../board/column_sheets.dart';
import '../card/card_sheet.dart';
import '../tour/tour.dart';

class TimelineView extends StatefulWidget {
  const TimelineView({super.key, required this.board, this.fullHeight = false});
  final Json board;

  /// Every row drawn, nothing scrolling up and down: for the desktop's long screenshot.
  final bool fullHeight;

  @override
  State<TimelineView> createState() {
    return _TimelineViewState();
  }
}

class _TimelineViewState extends State<TimelineView> {
  final _horizontalScroll = ScrollController();
  final _listScroll = ScrollController();
  final _chartScroll = ScrollController();
  bool _syncing = false;
  bool _scrolledToToday = false;
  String _zoom = 'months';

  @override
  void initState() {
    super.initState();
    final storedZoom = Store.instance.get(zoomKey);
    if (zooms.containsKey(storedZoom)) {
      _zoom = storedZoom!;
    }
    // The task list and the chart scroll up and down together.
    _listScroll.addListener(() {
      _syncScroll(_listScroll, _chartScroll);
    });
    _chartScroll.addListener(() {
      _syncScroll(_chartScroll, _listScroll);
    });
  }

  /// Moves one vertical scroll to where the other is, without the move echoing back.
  void _syncScroll(ScrollController from, ScrollController to) {
    if (_syncing || !to.hasClients) {
      return;
    }
    _syncing = true;
    to.jumpTo(from.offset.clamp(0, to.position.maxScrollExtent));
    _syncing = false;
  }

  @override
  void dispose() {
    _horizontalScroll.dispose();
    _listScroll.dispose();
    _chartScroll.dispose();
    super.dispose();
  }

  void _setZoom(String newZoom) {
    Store.instance.put(zoomKey, newZoom);
    setState(() {
      _zoom = newZoom;
      _scrolledToToday = false;
    });
  }

  /// Scrolls the chart sideways so today sits a third of the way across.
  void _toToday(TimelineRange range, double pixelsPerDay, double viewWidth, {bool animate = true}) {
    if (!_horizontalScroll.hasClients) {
      return;
    }
    final x = (range.today - range.firstDay) * pixelsPerDay;
    final target = math.max(0.0, x - viewWidth / 3).clamp(0.0, _horizontalScroll.position.maxScrollExtent);
    if (animate) {
      _horizontalScroll.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _horizontalScroll.jumpTo(target);
    }
  }

  void _save(Json card) {
    touch(card);
    AppState.instance.persistBoard(widget.board);
  }

  /// The zoom picker and Today button above the timeline: the task list on the left, and the
  /// chart (its date header above it) scrolling sideways on the right.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final narrow = MediaQuery.sizeOf(context).width <= Environment.phoneWidth;
    double listWidth;
    double sidePadding;
    if (narrow) {
      listWidth = 132.0;
      sidePadding = 12;
    } else {
      listWidth = 240.0;
      sidePadding = 20;
    }
    final zoomSettings = zooms[_zoom]!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewWidth = math.max(constraints.maxWidth - listWidth - sidePadding * 2, 320.0);
        final range = rangeOf(widget.board, _zoom, viewWidth);
        final chartWidth = range.days * zoomSettings.pixelsPerDay;
        final layout = rowsOf(widget.board);
        final scale = scaleOf(range, _zoom);
        double xOfDay(int day) {
          return (day - range.firstDay) * zoomSettings.pixelsPerDay;
        }

        final todayX = xOfDay(range.today) + zoomSettings.pixelsPerDay / 2;
        // In full height, the timeline is as tall as its rows; otherwise it fills the space left.
        Widget fillHeight(Widget child) {
          if (widget.fullHeight) {
            return SizedBox(height: layout.height + 40 + headerHeight + 2, child: child);
          } else {
            return Expanded(child: child);
          }
        }

        if (!_scrolledToToday) {
          _scrolledToToday = true;
          WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
            _toToday(range, zoomSettings.pixelsPerDay, viewWidth, animate: false);
          });
        }

        MainAxisSize columnSize;
        if (widget.fullHeight) {
          columnSize = MainAxisSize.min;
        } else {
          columnSize = MainAxisSize.max;
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(sidePadding, 0, sidePadding, 12),
          child: Column(
            mainAxisSize: columnSize,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    KeyedSubtree(
                      key: TourTargets.key('tl-zoom'),
                      child: _ZoomPicker(zoom: _zoom, onPick: _setZoom),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      key: const ValueKey('tl-today'),
                      onPressed: () {
                        _toToday(range, zoomSettings.pixelsPerDay, viewWidth);
                      },
                      child: const Text('Today'),
                    ),
                  ],
                ),
              ),
              fillHeight(
                Container(
                  key: const ValueKey('timeline'),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: listWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              height: headerHeight,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: colors.border),
                                  right: BorderSide(color: colors.border),
                                ),
                              ),
                              child: Text(
                                'Tasks',
                                style: TextStyle(color: colors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(right: BorderSide(color: colors.border)),
                                ),
                                child: SingleChildScrollView(
                                  controller: _listScroll,
                                  child: SizedBox(
                                    height: layout.height + 40,
                                    child: Stack(children: [for (final row in layout.rows) _listRow(colors, row)]),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Scrollbar(
                          controller: _horizontalScroll,
                          thumbVisibility: Environment.desktop,
                          child: SingleChildScrollView(
                            controller: _horizontalScroll,
                            scrollDirection: Axis.horizontal,
                            // On a phone, room at the end for the chart to come out from under
                            // the open tray.
                            padding: EdgeInsets.only(right: TrayClearance.of(context)),
                            child: SizedBox(
                              width: chartWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    height: headerHeight,
                                    child: _Header(scale: scale, todayX: todayX, zoom: _zoom),
                                  ),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      controller: _chartScroll,
                                      child: SizedBox(
                                        height: layout.height + 40,
                                        child: _Chart(
                                          board: widget.board,
                                          layout: layout,
                                          range: range,
                                          pixelsPerDay: zoomSettings.pixelsPerDay,
                                          zoom: _zoom,
                                          scale: scale,
                                          todayX: todayX,
                                          onChanged: _save,
                                        ),
                                      ),
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
            ],
          ),
        );
      },
    );
  }

  /// One row of the task list on the left: a phase (tap to rename), a task (tap to open), or
  /// the "+ Add task" / "+ Add phase" buttons.
  Widget _listRow(UwuColors colors, TimelineRow row) {
    Widget positioned(Widget child) {
      return Positioned(top: row.y, left: 0, right: 0, height: row.height, child: child);
    }

    switch (row.kind) {
      case 'phase':
        final firstPhase = identical(row.column, columnsOf(widget.board).firstOrNull);
        Key phaseKey;
        if (firstPhase) {
          phaseKey = TourTargets.key('tl-phase');
        } else {
          phaseKey = ValueKey('tl-phase-${row.column!['id']}');
        }
        return positioned(
          InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            key: phaseKey,
            onTap: () {
              openRenameColumn(context, widget.board, row.column!);
            },
            child: Tooltip(excludeFromSemantics: true,
              message: 'Rename or delete this phase',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                color: colors.surfaceStrong,
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: _colourFromHex(row.colour!), borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${row.column!['name']}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.ink, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text('${cardsOf(row.column!).length}', style: TextStyle(color: colors.muted, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        );
      case 'task':
        final card = row.card!;
        final undated = spanOf(card) == null;
        Color whenColour;
        if (undated) {
          whenColour = colors.muted.withValues(alpha: 0.7);
        } else {
          whenColour = colors.muted;
        }
        return positioned(
          InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: () {
              openCardSheet(context, widget.board, '${card['id']}');
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      if (card['milestone'] == true)
                        Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Transform.rotate(
                            angle: math.pi / 4,
                            child: Container(width: 7, height: 7, color: colors.muted),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          '${card['title']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.ink, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  Text(whenOf(card), style: TextStyle(color: whenColour, fontSize: 11)),
                ],
              ),
            ),
          ),
        );
      case 'add':
        return positioned(
          TextButton(
            style: TextButton.styleFrom(alignment: Alignment.centerLeft, foregroundColor: colors.muted, padding: const EdgeInsets.symmetric(horizontal: 12)),
            onPressed: () async {
              final taskName = await AppNavigation.prompt('Task name:');
              if (taskName != null) {
                AppState.instance.addCard(widget.board, '${row.column!['id']}', taskName);
              }
            },
            child: const Text('+ Add task', style: TextStyle(fontSize: 12.5)),
          ),
        );
      default:
        return positioned(
          TextButton(
            style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 12)),
            onPressed: () async {
              final name = await AppNavigation.prompt('Phase name:');
              if (name != null) {
                AppState.instance.addColumn(widget.board, name);
              }
            },
            child: const Text('+ Add phase', style: TextStyle(fontSize: 12.5)),
          ),
        );
    }
  }
}

/// A colour from its hex text, or the default blue when the text isn't a colour.
Color _colourFromHex(String hex) {
  final parsed = parseHexColour(hex);
  int rgb;
  if (parsed == null) {
    rgb = 0x4c9aff;
  } else {
    rgb = parsed;
  }
  return Color(0xFF000000 | rgb);
}

/// The Weeks / Months / Quarters buttons.
class _ZoomPicker extends StatelessWidget {
  const _ZoomPicker({required this.zoom, required this.onPick});
  final String zoom;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (final option in zooms.values) _option(colors, option)],
      ),
    );
  }

  /// One zoom button, filled with the brand colour while it's the zoom on show.
  Widget _option(UwuColors colors, Zoom option) {
    final selected = option.id == zoom;
    Color? fillColour;
    Color textColour;
    if (selected) {
      fillColour = colors.brandFill;
      textColour = colors.onBrand;
    } else {
      fillColour = null;
      textColour = colors.ink;
    }
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        key: ValueKey('zoom-${option.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          onPick(option.id);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: fillColour, borderRadius: BorderRadius.circular(8)),
          child: Text(option.label, style: TextStyle(fontSize: 13, color: textColour)),
        ),
      ),
    );
  }
}

/// The dates above the chart: the top row (months or years), the bottom row (days, weeks or
/// months), and a "Today" tag over today's line.
class _Header extends StatelessWidget {
  const _Header({required this.scale, required this.todayX, required this.zoom});
  final ({List<TimelineTick> top, List<TimelineTick> bottom, List<TimelineLine> lines}) scale;
  final double todayX;
  final String zoom;

  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    TextAlign bottomAlign;
    if (zoom == 'weeks') {
      bottomAlign = TextAlign.center;
    } else {
      bottomAlign = TextAlign.start;
    }
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final tick in scale.top)
            Positioned(
              left: tick.x + 6,
              top: 6,
              child: Text(
                tick.text,
                style: TextStyle(fontSize: 12, color: colors.ink, fontWeight: FontWeight.w600),
              ),
            ),
          for (final tick in scale.bottom) _bottomLabel(colors, tick, bottomAlign),
          Positioned(
            left: todayX - 22,
            bottom: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: colors.error, borderRadius: BorderRadius.circular(6)),
              child: Text('Today', style: TextStyle(fontSize: 10, color: colors.background)),
            ),
          ),
        ],
      ),
    );
  }

  /// One label on the bottom row, fainter on a weekend.
  Widget _bottomLabel(UwuColors colors, TimelineTick tick, TextAlign textAlign) {
    Color labelColour;
    if (tick.weekend) {
      labelColour = colors.muted.withValues(alpha: 0.6);
    } else {
      labelColour = colors.muted;
    }
    return Positioned(
      left: tick.x,
      top: 28,
      width: tick.width,
      child: Text(
        tick.text,
        textAlign: textAlign,
        overflow: TextOverflow.clip,
        maxLines: 1,
        style: TextStyle(fontSize: 11, color: labelColour),
      ),
    );
  }
}

/// The chart itself: the grid, a band for each phase with a line across its tasks' dates, a
/// bar for each dated task, a pressable row for each undated one, the dependency arrows on
/// top, and the red line for today.
class _Chart extends StatelessWidget {
  const _Chart({
    required this.board,
    required this.layout,
    required this.range,
    required this.pixelsPerDay,
    required this.zoom,
    required this.scale,
    required this.todayX,
    required this.onChanged,
  });

  final Json board;
  final ({List<TimelineRow> rows, double height}) layout;
  final TimelineRange range;
  final double pixelsPerDay;
  final String zoom;
  final ({List<TimelineTick> top, List<TimelineTick> bottom, List<TimelineLine> lines}) scale;
  final double todayX;
  final void Function(Json card) onChanged;

  /// Where a day starts across the chart.
  double xOfDay(int day) {
    return (day - range.firstDay) * pixelsPerDay;
  }

  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final bars = <String, Rect>{};
    final children = <Widget>[];
    var barMarked = false;
    var undatedMarked = false;
    for (final row in layout.rows) {
      // A phase: a shaded band, and a thin line from its first task's start to its last's end.
      if (row.kind == 'phase') {
        children.add(
          Positioned(
            top: row.y,
            left: 0,
            right: 0,
            height: row.height,
            child: Container(color: colors.surfaceStrong.withValues(alpha: 0.6)),
          ),
        );
        final spans = cardsOf(row.column!).map(spanOf).whereType<Span>().toList();
        if (spans.isNotEmpty) {
          final firstDay = spans.map((span) {
            return span.start;
          }).reduce(math.min);
          final lastDay = spans.map((span) {
            return span.end;
          }).reduce(math.max);
          children.add(
            Positioned(
              top: row.y + row.height / 2 - 3,
              left: xOfDay(firstDay),
              width: (lastDay - firstDay + 1) * pixelsPerDay,
              height: 6,
              child: Tooltip(
                message: '${row.column!['name']}: ${formatDay(firstDay)} – ${formatDay(lastDay)}',
                child: Container(
                  decoration: BoxDecoration(color: _colourFromHex(row.colour!).withValues(alpha: 0.7), borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ),
          );
        }
        continue;
      }
      if (row.kind != 'task') {
        continue;
      }
      final card = row.card!;
      final span = spanOf(card);
      // An undated task: pressing a day in its row gives it dates starting there.
      if (span == null) {
        final markUndated = undatedMarked;
        undatedMarked = true;
        Key undatedKey;
        if (markUndated) {
          undatedKey = ValueKey('tl-undated-${card['id']}');
        } else {
          undatedKey = TourTargets.key('tl-undated');
        }
        children.add(
          Positioned(
            top: row.y,
            left: 0,
            right: 0,
            height: row.height,
            child: Tooltip(
              message: 'Press a day to give “${card['title']}” dates',
              child: GestureDetector(
                key: undatedKey,
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final day = range.firstDay + (details.localPosition.dx / pixelsPerDay).floor();
                  card['start'] = isoDateOf(day);
                  int extraDays;
                  if (card['milestone'] == true) {
                    extraDays = 0;
                  } else {
                    extraDays = zooms[zoom]!.newLength - 1;
                  }
                  card['due'] = isoDateOf(day + extraDays);
                  onChanged(card);
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(color: colors.brandFill.withValues(alpha: 0.08)),
                ),
              ),
            ),
          ),
        );
        continue;
      }
      // A dated task: its bar, remembered so the arrows can find it.
      final barStartX = xOfDay(span.start);
      final barEndX = xOfDay(span.end) + pixelsPerDay;
      final centreY = row.y + row.height / 2;
      bars['${card['id']}'] = Rect.fromLTRB(barStartX, centreY, barEndX, centreY);
      final markBar = !barMarked;
      barMarked = true;
      GlobalKey? barTourKey;
      if (markBar) {
        barTourKey = TourTargets.key('tl-bar');
      } else {
        barTourKey = null;
      }
      children.add(
        _Bar(
          key: ValueKey('tl-bar-${card['id']}'),
          tourKey: barTourKey,
          board: board,
          card: card,
          span: span,
          colour: _colourFromHex(row.colour!),
          left: barStartX,
          width: barEndX - barStartX,
          top: row.y,
          height: row.height,
          pixelsPerDay: pixelsPerDay,
          onChanged: onChanged,
        ),
      );
    }

    // Dependency arrows, from the end of the task waited for to the start of the one waiting.
    final arrows = <({Rect from, Rect to, bool clash, String label})>[];
    for (final row in layout.rows) {
      if (row.kind != 'task' || !bars.containsKey('${row.card!['id']}')) {
        continue;
      }
      for (final dependencyId in dependenciesOf(row.card!)) {
        final from = bars[dependencyId];
        if (from == null) {
          continue;
        }
        final waitedFor = findCard(board, dependencyId);
        Object? waitedForTitle;
        if (waitedFor != null) {
          waitedForTitle = waitedFor['title'];
        }
        arrows.add((
          from: from,
          to: bars['${row.card!['id']}']!,
          clash: clashes(waitedFor, row.card!),
          label: '$waitedForTitle → ${row.card!['title']}',
        ));
      }
    }

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _GridPainter(scale: scale, zoom: zoom, line: colors.border, strong: colors.muted.withValues(alpha: 0.35), weekend: colors.surfaceStrong.withValues(alpha: 0.5)),
          ),
        ),
        ...children,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ArrowPainter(arrows, normal: colors.muted, clash: colors.error),
            ),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: todayX - 1,
          width: 2,
          child: IgnorePointer(child: Container(color: colors.error.withValues(alpha: 0.8))),
        ),
      ],
    );
  }
}

/// One task's bar (or a milestone's diamond), with its title beside it. Dragged, it moves, or
/// from an end it changes length, snapping to whole days when let go.
class _Bar extends StatefulWidget {
  const _Bar({
    super.key,
    this.tourKey,
    required this.board,
    required this.card,
    required this.span,
    required this.colour,
    required this.left,
    required this.width,
    required this.top,
    required this.height,
    required this.pixelsPerDay,
    required this.onChanged,
  });

  final GlobalKey? tourKey;
  final Json board;
  final Json card;
  final Span span;
  final Color colour;
  final double left;
  final double width;
  final double top;
  final double height;
  final double pixelsPerDay;
  final void Function(Json card) onChanged;

  @override
  State<_Bar> createState() {
    return _BarState();
  }
}

class _BarState extends State<_Bar> {
  String? _mode; // move | start | end
  double _dragDeltaX = 0;
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// How many whole days the drag so far comes to.
  int get _draggedDays {
    return (_dragDeltaX / widget.pixelsPerDay).round();
  }

  /// A drag starting: near the left end it moves the start, near the right end the end, and
  /// anywhere else (or on a milestone) the whole bar.
  void _onDragStart(DragStartDetails details) {
    final milestone = widget.card['milestone'] == true;
    final x = details.localPosition.dx;
    if (milestone) {
      _mode = 'move';
    } else if (x < 10) {
      _mode = 'start';
    } else if (x > widget.width - 10) {
      _mode = 'end';
    } else {
      _mode = 'move';
    }
    setState(() {
      _dragDeltaX = 0;
    });
  }

  /// A drag let go: the task's dates move by the whole days dragged.
  void _onDragEnd() {
    final days = _draggedDays;
    final span = widget.span;
    final mode = _mode;
    setState(() {
      _mode = null;
      _dragDeltaX = 0;
    });
    if (days == 0 || mode == null) {
      return;
    }
    if (mode == 'move') {
      setSpan(widget.card, span.start + days, span.end + days);
    } else if (mode == 'start') {
      setSpan(widget.card, math.min(span.start + days, span.end), span.end);
    } else {
      setSpan(widget.card, span.start, math.max(span.end + days, span.start));
    }
    widget.onChanged(widget.card);
  }

  /// Keys on a focused bar: Enter or Space opens the card; Left and Right move it a day (with
  /// Shift, only its end).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final pressedKey = event.logicalKey;
    if (pressedKey == LogicalKeyboardKey.enter || pressedKey == LogicalKeyboardKey.space) {
      openCardSheet(context, widget.board, '${widget.card['id']}');
      return KeyEventResult.handled;
    }
    if (pressedKey != LogicalKeyboardKey.arrowLeft && pressedKey != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    int direction;
    if (pressedKey == LogicalKeyboardKey.arrowLeft) {
      direction = -1;
    } else {
      direction = 1;
    }
    final span = widget.span;
    if (HardwareKeyboard.instance.isShiftPressed && widget.card['milestone'] != true) {
      setSpan(widget.card, span.start, math.max(span.start, span.end + direction));
    } else {
      setSpan(widget.card, span.start + direction, span.end + direction);
    }
    widget.onChanged(widget.card);
    return KeyEventResult.handled;
  }

  /// The bar (or diamond) where the drag so far puts it, its progress filled in, a ring while
  /// focused, and the title beside it.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final card = widget.card;
    final milestone = card['milestone'] == true;
    final snapped = _draggedDays * widget.pixelsPerDay;
    var left = widget.left;
    var width = widget.width;
    final spanLength = (widget.span.end - widget.span.start) * widget.pixelsPerDay;
    if (_mode == 'move') {
      left = left + snapped;
    }
    if (_mode == 'start') {
      final shift = math.min(snapped, spanLength);
      left = left + shift;
      width = width - shift;
    }
    if (_mode == 'end') {
      width = width + math.max(snapped, -spanLength);
    }

    final progress = progressOf(card);
    final late = isLate(card);
    // What a screen reader says for the bar.
    String datesText;
    if (milestone) {
      datesText = 'milestone, ${formatDay(widget.span.start)}';
    } else {
      datesText = '${formatDay(widget.span.start)} to ${formatDay(widget.span.end)}';
    }
    String progressText;
    if (checklistOf(card).isNotEmpty) {
      progressText = ', ${(progress * 100).round()}% done';
    } else {
      progressText = '';
    }
    final label = '${card['title']}, $datesText$progressText';

    Widget shape;
    if (milestone) {
      shape = SizedBox(
        width: 22,
        height: 22,
        child: Center(
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: widget.colour,
                border: Border.all(color: colors.ink.withValues(alpha: 0.4)),
              ),
            ),
          ),
        ),
      );
    } else {
      Color borderColour;
      double borderWidth;
      if (late) {
        borderColour = colors.error;
        borderWidth = 2;
      } else {
        borderColour = widget.colour;
        borderWidth = 1;
      }
      shape = Container(
        width: width,
        height: 22,
        decoration: BoxDecoration(
          color: widget.colour.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColour, width: borderWidth),
        ),
        clipBehavior: Clip.antiAlias,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: progress,
            heightFactor: 1,
            child: Container(color: widget.colour),
          ),
        ),
      );
    }

    double barLeft;
    if (milestone) {
      barLeft = left + widget.pixelsPerDay / 2 - 11;
    } else {
      barLeft = left;
    }
    MouseCursor cursor;
    if (_mode != null) {
      cursor = SystemMouseCursors.grabbing;
    } else {
      cursor = SystemMouseCursors.grab;
    }
    String lateSuffix;
    Color titleColour;
    if (late) {
      lateSuffix = ' (late)';
      titleColour = colors.error;
    } else {
      lateSuffix = '';
      titleColour = colors.ink;
    }
    return Positioned(
      top: widget.top,
      height: widget.height,
      left: barLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Focus(
            key: widget.tourKey,
            focusNode: _focusNode,
            onKeyEvent: _onKey,
            child: Semantics(
              button: true,
              label: label,
              excludeSemantics: true,
              child: MouseRegion(
                cursor: cursor,
                child: GestureDetector(
                  onTap: () {
                    openCardSheet(context, widget.board, '${card['id']}');
                  },
                  onHorizontalDragStart: _onDragStart,
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _dragDeltaX = _dragDeltaX + details.delta.dx;
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    _onDragEnd();
                  },
                  onHorizontalDragCancel: () {
                    setState(() {
                      _mode = null;
                      _dragDeltaX = 0;
                    });
                  },
                  child: AnimatedBuilder(
                    animation: _focusNode,
                    builder: (context, child) {
                      BoxDecoration? focusRing;
                      if (_focusNode.hasFocus) {
                        focusRing = BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colors.brandInk, width: 2),
                        );
                      } else {
                        focusRing = null;
                      }
                      return Container(decoration: focusRing, child: child);
                    },
                    child: shape,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IgnorePointer(
            // A late task says so in words, not only with its red edge (WCAG 1.4.1).
            child: Text('${card['title']}$lateSuffix', maxLines: 1, style: TextStyle(fontSize: 12, color: titleColour)),
          ),
        ],
      ),
    );
  }
}

/// The chart's background: shaded weekends (in Weeks only) and the vertical grid lines.
class _GridPainter extends CustomPainter {
  _GridPainter({required this.scale, required this.zoom, required this.line, required this.strong, required this.weekend});
  final ({List<TimelineTick> top, List<TimelineTick> bottom, List<TimelineLine> lines}) scale;
  final String zoom;
  final Color line;
  final Color strong;
  final Color weekend;

  @override
  void paint(Canvas canvas, Size size) {
    if (zoom == 'weeks') {
      final weekendPaint = Paint();
      weekendPaint.color = weekend;
      final weekendTicks = scale.bottom.where((tick) {
        return tick.weekend;
      });
      for (final tick in weekendTicks) {
        canvas.drawRect(Rect.fromLTWH(tick.x, 0, tick.width, size.height), weekendPaint);
      }
    }
    final thin = Paint();
    thin.color = line;
    thin.strokeWidth = 1;
    final thick = Paint();
    thick.color = strong;
    thick.strokeWidth = 1;
    for (final gridLine in scale.lines) {
      Paint linePaint;
      if (gridLine.strong) {
        linePaint = thick;
      } else {
        linePaint = thin;
      }
      canvas.drawLine(Offset(gridLine.x, 0), Offset(gridLine.x, size.height), linePaint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldPainter) {
    return oldPainter.scale != scale || oldPainter.line != line;
  }
}

/// The dependency arrows: down (or up) from the end of the task waited for, across, and into
/// the start of the waiting one, with an arrowhead. Dashed and red when the dates clash.
class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.arrows, {required this.normal, required this.clash});
  final List<({Rect from, Rect to, bool clash, String label})> arrows;
  final Color normal;
  final Color clash;

  @override
  void paint(Canvas canvas, Size size) {
    for (final arrow in arrows) {
      final paint = Paint();
      if (arrow.clash) {
        paint.color = clash;
      } else {
        paint.color = normal;
      }
      paint.strokeWidth = 1.5;
      paint.style = PaintingStyle.stroke;
      final from = arrow.from;
      final to = arrow.to;
      double midY;
      if (to.top > from.top) {
        midY = to.top - taskRowHeight / 2;
      } else {
        midY = to.top + taskRowHeight / 2;
      }
      final path = Path();
      path.moveTo(from.right - 6, from.top + 12);
      path.lineTo(from.right - 6, midY);
      path.lineTo(to.left - 10, midY);
      path.lineTo(to.left - 10, to.top);
      path.lineTo(to.left - 3, to.top);
      if (arrow.clash) {
        // Clashing dates: dashed as well as red, so it shows without telling red from grey.
        for (final metric in path.computeMetrics()) {
          for (var distance = 0.0; distance < metric.length; distance = distance + 9) {
            canvas.drawPath(metric.extractPath(distance, (distance + 5).clamp(0, metric.length)), paint);
          }
        }
      } else {
        canvas.drawPath(path, paint);
      }
      final head = Path();
      head.moveTo(to.left - 2, to.top);
      head.lineTo(to.left - 9, to.top - 4);
      head.lineTo(to.left - 9, to.top + 4);
      head.close();
      final headPaint = Paint();
      headPaint.color = paint.color;
      canvas.drawPath(head, headPaint);
    }
  }

  @override
  bool shouldRepaint(_ArrowPainter oldPainter) {
    return true;
  }
}
