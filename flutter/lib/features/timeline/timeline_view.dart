// A board as a Timeline (main-site/js/timeline.js): the phases and their tasks down the left,
// each task a bar across its dates, a milestone a diamond, arrows from the tasks a task waits
// for (red when the dates clash), a line for today, and zoom by weeks, months or quarters. Drag
// a bar to move it or an end to change its length; press a day in an undated task's row to give
// it dates. Arrow keys move a focused bar a day; with Shift, its end only.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  final _h = ScrollController();
  final _vList = ScrollController();
  final _vChart = ScrollController();
  bool _syncing = false;
  bool _scrolledToToday = false;
  String _zoom = 'months';

  @override
  void initState() {
    super.initState();
    final z = Store.I.get(zoomKey);
    if (zooms.containsKey(z)) _zoom = z!;
    _vList.addListener(() => _sync(_vList, _vChart));
    _vChart.addListener(() => _sync(_vChart, _vList));
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !to.hasClients) return;
    _syncing = true;
    to.jumpTo(from.offset.clamp(0, to.position.maxScrollExtent));
    _syncing = false;
  }

  @override
  void dispose() {
    _h.dispose();
    _vList.dispose();
    _vChart.dispose();
    super.dispose();
  }

  void _setZoom(String z) {
    Store.I.put(zoomKey, z);
    setState(() {
      _zoom = z;
      _scrolledToToday = false;
    });
  }

  void _toToday(TlRange range, double ppd, double viewW, {bool animate = true}) {
    if (!_h.hasClients) return;
    final x = (range.today - range.lo) * ppd;
    final target = math.max(0.0, x - viewW / 3).clamp(0.0, _h.position.maxScrollExtent);
    if (animate) {
      _h.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _h.jumpTo(target);
    }
  }

  void _save(Json card) {
    touch(card);
    AppState.I.persistBoard(widget.board);
  }

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final narrow = MediaQuery.sizeOf(context).width <= Env.phoneWidth;
    final listW = narrow ? 132.0 : 240.0;
    final z = zooms[_zoom]!;
    return LayoutBuilder(
      builder: (context, box) {
        final viewW = math.max(box.maxWidth - listW - (narrow ? 12 : 20) * 2, 320.0);
        final range = rangeOf(widget.board, _zoom, viewW);
        final chartW = range.days * z.ppd;
        final layout = rowsOf(widget.board);
        final sc = scaleOf(range, _zoom);
        double xOf(int n) => (n - range.lo) * z.ppd;
        final todayX = xOf(range.today) + z.ppd / 2;
        Widget fill(Widget child) => widget.fullHeight ? SizedBox(height: layout.height + 40 + headHeight + 2, child: child) : Expanded(child: child);
        if (!_scrolledToToday) {
          _scrolledToToday = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _toToday(range, z.ppd, viewW, animate: false));
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(narrow ? 12 : 20, 0, narrow ? 12 : 20, 12),
          child: Column(
            mainAxisSize: widget.fullHeight ? MainAxisSize.min : MainAxisSize.max,
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
                    OutlinedButton(key: const ValueKey('tl-today'), onPressed: () => _toToday(range, z.ppd, viewW), child: const Text('Today')),
                  ],
                ),
              ),
              fill(
                Container(
                  key: const ValueKey('timeline'),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: listW,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              height: headHeight,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: c.border),
                                  right: BorderSide(color: c.border),
                                ),
                              ),
                              child: Text(
                                'Tasks',
                                style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(right: BorderSide(color: c.border)),
                                ),
                                child: SingleChildScrollView(
                                  controller: _vList,
                                  child: SizedBox(
                                    height: layout.height + 40,
                                    child: Stack(children: [for (final r in layout.rows) _listRow(c, r)]),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Scrollbar(
                          controller: _h,
                          thumbVisibility: Env.desktop,
                          child: SingleChildScrollView(
                            controller: _h,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: chartW,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    height: headHeight,
                                    child: _Header(sc: sc, todayX: todayX, zoom: _zoom),
                                  ),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      controller: _vChart,
                                      child: SizedBox(
                                        height: layout.height + 40,
                                        child: _Chart(
                                          board: widget.board,
                                          layout: layout,
                                          range: range,
                                          ppd: z.ppd,
                                          zoom: _zoom,
                                          sc: sc,
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

  Widget _listRow(UwuColors c, TlRow r) {
    Widget pos(Widget child) => Positioned(top: r.y, left: 0, right: 0, height: r.h, child: child);
    switch (r.kind) {
      case 'phase':
        final firstPhase = identical(r.col, columnsOf(widget.board).firstOrNull);
        return pos(
          InkWell(
            key: firstPhase ? TourTargets.key('tl-phase') : ValueKey('tl-phase-${r.col!['id']}'),
            onTap: () => openRenameColumn(context, widget.board, r.col!),
            child: Tooltip(excludeFromSemantics: true, 
              message: 'Rename or delete this phase',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                color: c.surfaceStrong,
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: _hex(r.colour!), borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${r.col!['name']}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.ink, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text('${cardsOf(r.col!).length}', style: TextStyle(color: c.muted, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        );
      case 'task':
        final card = r.card!;
        final undated = spanOf(card) == null;
        return pos(
          InkWell(
            onTap: () => openCardSheet(context, widget.board, '${card['id']}'),
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
                            child: Container(width: 7, height: 7, color: c.muted),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          '${card['title']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.ink, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  Text(whenOf(card), style: TextStyle(color: undated ? c.muted.withValues(alpha: 0.7) : c.muted, fontSize: 11)),
                ],
              ),
            ),
          ),
        );
      case 'add':
        return pos(
          TextButton(
            style: TextButton.styleFrom(alignment: Alignment.centerLeft, foregroundColor: c.muted, padding: const EdgeInsets.symmetric(horizontal: 12)),
            onPressed: () async {
              final t = await AppNav.prompt('Task name:');
              if (t != null) AppState.I.addCard(widget.board, '${r.col!['id']}', t);
            },
            child: const Text('+ Add task', style: TextStyle(fontSize: 12.5)),
          ),
        );
      default:
        return pos(
          TextButton(
            style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 12)),
            onPressed: () async {
              final name = await AppNav.prompt('Phase name:');
              if (name != null) AppState.I.addColumn(widget.board, name);
            },
            child: const Text('+ Add phase', style: TextStyle(fontSize: 12.5)),
          ),
        );
    }
  }
}

Color _hex(String hex) => Color(0xFF000000 | (parseHex(hex) ?? 0x4c9aff));

class _ZoomPicker extends StatelessWidget {
  const _ZoomPicker({required this.zoom, required this.onPick});
  final String zoom;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final z in zooms.values)
            Semantics(
              selected: z.id == zoom,
              button: true,
              child: InkWell(
                key: ValueKey('zoom-${z.id}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => onPick(z.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: z.id == zoom ? c.brandFill : null, borderRadius: BorderRadius.circular(8)),
                  child: Text(z.label, style: TextStyle(fontSize: 13, color: z.id == zoom ? c.onBrand : c.ink)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.sc, required this.todayX, required this.zoom});
  final ({List<TlTick> top, List<TlTick> bottom, List<TlLine> lines}) sc;
  final double todayX;
  final String zoom;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final t in sc.top)
            Positioned(
              left: t.x + 6,
              top: 6,
              child: Text(
                t.text,
                style: TextStyle(fontSize: 12, color: c.ink, fontWeight: FontWeight.w600),
              ),
            ),
          for (final t in sc.bottom)
            Positioned(
              left: t.x,
              top: 28,
              width: t.w,
              child: Text(
                t.text,
                textAlign: zoom == 'weeks' ? TextAlign.center : TextAlign.start,
                overflow: TextOverflow.clip,
                maxLines: 1,
                style: TextStyle(fontSize: 11, color: t.weekend ? c.muted.withValues(alpha: 0.6) : c.muted),
              ),
            ),
          Positioned(
            left: todayX - 22,
            bottom: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: c.error, borderRadius: BorderRadius.circular(6)),
              child: Text('Today', style: TextStyle(fontSize: 10, color: c.bg)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({
    required this.board,
    required this.layout,
    required this.range,
    required this.ppd,
    required this.zoom,
    required this.sc,
    required this.todayX,
    required this.onChanged,
  });

  final Json board;
  final ({List<TlRow> rows, double height}) layout;
  final TlRange range;
  final double ppd;
  final String zoom;
  final ({List<TlTick> top, List<TlTick> bottom, List<TlLine> lines}) sc;
  final double todayX;
  final void Function(Json card) onChanged;

  double xOf(int n) => (n - range.lo) * ppd;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final bars = <String, Rect>{};
    final children = <Widget>[];
    var barMarked = false, undatedMarked = false;
    for (final r in layout.rows) {
      if (r.kind == 'phase') {
        children.add(
          Positioned(
            top: r.y,
            left: 0,
            right: 0,
            height: r.h,
            child: Container(color: c.surfaceStrong.withValues(alpha: 0.6)),
          ),
        );
        final spans = cardsOf(r.col!).map(spanOf).whereType<Span>().toList();
        if (spans.isNotEmpty) {
          final a = spans.map((s) => s.start).reduce(math.min), b = spans.map((s) => s.end).reduce(math.max);
          children.add(
            Positioned(
              top: r.y + r.h / 2 - 3,
              left: xOf(a),
              width: (b - a + 1) * ppd,
              height: 6,
              child: Tooltip(
                message: '${r.col!['name']}: ${fmtDay(a)} – ${fmtDay(b)}',
                child: Container(
                  decoration: BoxDecoration(color: _hex(r.colour!).withValues(alpha: 0.7), borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ),
          );
        }
        continue;
      }
      if (r.kind != 'task') continue;
      final card = r.card!;
      final s = spanOf(card);
      if (s == null) {
        final markUndated = undatedMarked;
        undatedMarked = true;
        children.add(
          Positioned(
            top: r.y,
            left: 0,
            right: 0,
            height: r.h,
            child: Tooltip(
              message: 'Press a day to give “${card['title']}” dates',
              child: GestureDetector(
                key: markUndated ? ValueKey('tl-undated-${card['id']}') : TourTargets.key('tl-undated'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final day = range.lo + (d.localPosition.dx / ppd).floor();
                  card['start'] = isoOf(day);
                  card['due'] = isoOf(day + (card['milestone'] == true ? 0 : zooms[zoom]!.newLength - 1));
                  onChanged(card);
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(color: c.brandFill.withValues(alpha: 0.08)),
                ),
              ),
            ),
          ),
        );
        continue;
      }
      final x1 = xOf(s.start), x2 = xOf(s.end) + ppd, cy = r.y + r.h / 2;
      bars['${card['id']}'] = Rect.fromLTRB(x1, cy, x2, cy);
      final markBar = !barMarked;
      barMarked = true;
      children.add(
        _Bar(
          key: ValueKey('tl-bar-${card['id']}'),
          tourKey: markBar ? TourTargets.key('tl-bar') : null,
          board: board,
          card: card,
          span: s,
          colour: _hex(r.colour!),
          left: x1,
          width: x2 - x1,
          top: r.y,
          height: r.h,
          ppd: ppd,
          onChanged: onChanged,
        ),
      );
    }

    // Dependency arrows, from the end of the task waited for to the start of the one waiting.
    final arrows = <({Rect from, Rect to, bool clash, String label})>[];
    for (final r in layout.rows) {
      if (r.kind != 'task' || !bars.containsKey('${r.card!['id']}')) continue;
      for (final dep in depsOf(r.card!)) {
        final from = bars[dep];
        if (from == null) continue;
        final pred = findCard(board, dep);
        arrows.add((from: from, to: bars['${r.card!['id']}']!, clash: clashes(pred, r.card!), label: '${pred?['title']} → ${r.card!['title']}'));
      }
    }

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _GridPainter(sc: sc, zoom: zoom, line: c.border, strong: c.muted.withValues(alpha: 0.35), weekend: c.surfaceStrong.withValues(alpha: 0.5)),
          ),
        ),
        ...children,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ArrowPainter(arrows, normal: c.muted, clash: c.error),
            ),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: todayX - 1,
          width: 2,
          child: IgnorePointer(child: Container(color: c.error.withValues(alpha: 0.8))),
        ),
      ],
    );
  }
}

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
    required this.ppd,
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
  final double ppd;
  final void Function(Json card) onChanged;

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> {
  String? _mode; // move | start | end
  double _dx = 0;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  int get _days => (_dx / widget.ppd).round();

  void _start(DragStartDetails d) {
    final milestone = widget.card['milestone'] == true;
    final x = d.localPosition.dx;
    _mode = milestone ? 'move' : (x < 10 ? 'start' : (x > widget.width - 10 ? 'end' : 'move'));
    setState(() => _dx = 0);
  }

  void _end() {
    final days = _days;
    final s = widget.span;
    final mode = _mode;
    setState(() {
      _mode = null;
      _dx = 0;
    });
    if (days == 0 || mode == null) return;
    if (mode == 'move') {
      setSpan(widget.card, s.start + days, s.end + days);
    } else if (mode == 'start') {
      setSpan(widget.card, math.min(s.start + days, s.end), s.end);
    } else {
      setSpan(widget.card, s.start, math.max(s.end + days, s.start));
    }
    widget.onChanged(widget.card);
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space) {
      openCardSheet(context, widget.board, '${widget.card['id']}');
      return KeyEventResult.handled;
    }
    if (k != LogicalKeyboardKey.arrowLeft && k != LogicalKeyboardKey.arrowRight) return KeyEventResult.ignored;
    final d = k == LogicalKeyboardKey.arrowLeft ? -1 : 1;
    final s = widget.span;
    if (HardwareKeyboard.instance.isShiftPressed && widget.card['milestone'] != true) {
      setSpan(widget.card, s.start, math.max(s.start, s.end + d));
    } else {
      setSpan(widget.card, s.start + d, s.end + d);
    }
    widget.onChanged(widget.card);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final card = widget.card;
    final milestone = card['milestone'] == true;
    final snapped = _days * widget.ppd;
    var left = widget.left, width = widget.width;
    final len = (widget.span.end - widget.span.start) * widget.ppd;
    if (_mode == 'move') left += snapped;
    if (_mode == 'start') {
      final d = math.min(snapped, len);
      left += d;
      width -= d;
    }
    if (_mode == 'end') width += math.max(snapped, -len);

    final pct = progressOf(card);
    final late = isLate(card);
    final label =
        '${card['title']}, ${milestone ? 'milestone, ${fmtDay(widget.span.start)}' : '${fmtDay(widget.span.start)} to ${fmtDay(widget.span.end)}'}'
        '${checklistOf(card).isNotEmpty ? ', ${(pct * 100).round()}% done' : ''}';

    final Widget shape = milestone
        ? SizedBox(
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
                    border: Border.all(color: c.ink.withValues(alpha: 0.4)),
                  ),
                ),
              ),
            ),
          )
        : Container(
            width: width,
            height: 22,
            decoration: BoxDecoration(
              color: widget.colour.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: late ? c.error : widget.colour, width: late ? 2 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: pct,
                heightFactor: 1,
                child: Container(color: widget.colour),
              ),
            ),
          );

    final barLeft = milestone ? left + widget.ppd / 2 - 11 : left;
    return Positioned(
      top: widget.top,
      height: widget.height,
      left: barLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Focus(
            key: widget.tourKey,
            focusNode: _focus,
            onKeyEvent: _key,
            child: Semantics(
              button: true,
              label: label,
              excludeSemantics: true,
              child: MouseRegion(
                cursor: _mode != null ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
                child: GestureDetector(
                  onTap: () => openCardSheet(context, widget.board, '${card['id']}'),
                  onHorizontalDragStart: _start,
                  onHorizontalDragUpdate: (d) => setState(() => _dx += d.delta.dx),
                  onHorizontalDragEnd: (_) => _end(),
                  onHorizontalDragCancel: () => setState(() {
                    _mode = null;
                    _dx = 0;
                  }),
                  child: AnimatedBuilder(
                    animation: _focus,
                    builder: (context, child) => Container(
                      decoration: _focus.hasFocus
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: c.brandInk, width: 2),
                            )
                          : null,
                      child: child,
                    ),
                    child: shape,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IgnorePointer(
            child: Text('${card['title']}', maxLines: 1, style: TextStyle(fontSize: 12, color: c.ink)),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.sc, required this.zoom, required this.line, required this.strong, required this.weekend});
  final ({List<TlTick> top, List<TlTick> bottom, List<TlLine> lines}) sc;
  final String zoom;
  final Color line;
  final Color strong;
  final Color weekend;

  @override
  void paint(Canvas canvas, Size size) {
    if (zoom == 'weeks') {
      final p = Paint()..color = weekend;
      for (final b in sc.bottom.where((b) => b.weekend)) {
        canvas.drawRect(Rect.fromLTWH(b.x, 0, b.w, size.height), p);
      }
    }
    final thin = Paint()
      ..color = line
      ..strokeWidth = 1;
    final thick = Paint()
      ..color = strong
      ..strokeWidth = 1;
    for (final l in sc.lines) {
      canvas.drawLine(Offset(l.x, 0), Offset(l.x, size.height), l.strong ? thick : thin);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.sc != sc || old.line != line;
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.arrows, {required this.normal, required this.clash});
  final List<({Rect from, Rect to, bool clash, String label})> arrows;
  final Color normal;
  final Color clash;

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in arrows) {
      final paint = Paint()
        ..color = a.clash ? clash : normal
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final from = a.from, to = a.to;
      final midY = to.top > from.top ? to.top - rowTask / 2 : to.top + rowTask / 2;
      final path = Path()
        ..moveTo(from.right - 6, from.top + 12)
        ..lineTo(from.right - 6, midY)
        ..lineTo(to.left - 10, midY)
        ..lineTo(to.left - 10, to.top)
        ..lineTo(to.left - 3, to.top);
      canvas.drawPath(path, paint);
      final head = Path()
        ..moveTo(to.left - 2, to.top)
        ..lineTo(to.left - 9, to.top - 4)
        ..lineTo(to.left - 9, to.top + 4)
        ..close();
      canvas.drawPath(head, Paint()..color = paint.color);
    }
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => true;
}
