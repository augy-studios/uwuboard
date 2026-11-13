// A board as columns (the site's renderBoard, buildColumn and buildCard): cards dragged from
// column to column, a card's details on a tap, an inline box to add one, and a round button to
// add a column. On a phone a card is picked up with a long press, so a swipe still scrolls; with
// a mouse it's dragged straight away.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/env.dart';
import '../../app/nav.dart';
import '../../app/state.dart';
import '../../data/board.dart';
import '../../data/timeline_logic.dart' show progressOf;
import '../../desktop/adaptive.dart';
import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../card/card_sheet.dart';
import 'column_sheets.dart';
import '../tour/tour.dart';

class KanbanView extends StatefulWidget {
  const KanbanView({super.key, required this.board, this.fullHeight = false});
  final Json board;

  /// Every column at its whole height, side by side, nothing scrolling: for the desktop's long
  /// screenshot.
  final bool fullHeight;

  @override
  State<KanbanView> createState() => _KanbanViewState();
}

class _KanbanViewState extends State<KanbanView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cols = columnsOf(widget.board);
    final narrow = MediaQuery.sizeOf(context).width <= Env.phoneWidth;
    final colWidth = narrow ? (MediaQuery.sizeOf(context).width * 0.82).clamp(240.0, 300.0) : 280.0;
    if (widget.fullHeight) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final col in cols) ...[
              SizedBox(
                width: colWidth,
                child: _Column(board: widget.board, col: col, fullHeight: true),
              ),
              const SizedBox(width: 14),
            ],
          ],
        ),
      );
    }
    return Scrollbar(
      controller: _scroll,
      thumbVisibility: Env.desktop,
      child: SingleChildScrollView(
        key: const ValueKey('columns'),
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(narrow ? 12 : 20, 4, 20, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final col in cols) ...[
              SizedBox(
                width: colWidth,
                child: _Column(board: widget.board, col: col, first: identical(col, cols.first)),
              ),
              const SizedBox(width: 14),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: GlassButton(
                key: TourTargets.key('add-column'),
                icon: 'plus',
                label: 'Add Column',
                size: 46,
                onPressed: () async {
                  final name = await AppNav.prompt('Column name:');
                  if (name != null) AppState.I.addColumn(widget.board, name);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What's being dragged: one card, from one column.
class DragCard {
  const DragCard(this.cardId, this.colId);
  final String cardId;
  final String colId;
}

class _Column extends StatefulWidget {
  const _Column({required this.board, required this.col, this.first = false, this.fullHeight = false});
  final Json board;
  final Json col;
  final bool fullHeight;

  /// The first column carries the tour's targets.
  final bool first;

  @override
  State<_Column> createState() => _ColumnState();
}

class _ColumnState extends State<_Column> {
  bool _adding = false;
  final _add = TextEditingController();
  final _addFocus = FocusNode();

  /// Where a dragged card would land: before this card id, or at the end ('').
  String? _dropBefore;

  void _submitAdd() {
    final t = _add.text.trim();
    if (t.isEmpty) return;
    AppState.I.addCard(widget.board, '${widget.col['id']}', t);
    _add.clear();
    setState(() => _adding = false);
  }

  @override
  void dispose() {
    _add.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  void _drop(DragCard d) {
    final before = _dropBefore == '' ? null : _dropBefore;
    setState(() => _dropBefore = null);
    AppState.I.moveCard(widget.board, d.cardId, '${widget.col['id']}', beforeId: before);
  }

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final cards = cardsOf(widget.col);
    final colId = '${widget.col['id']}';
    return DragTarget<DragCard>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (_) {
        if (_dropBefore == null) setState(() => _dropBefore = '');
      },
      onLeave: (_) => setState(() => _dropBefore = null),
      onAcceptWithDetails: (d) => _drop(d.data),
      builder: (context, candidates, _) {
        final over = candidates.isNotEmpty;
        return GlassPanel(
          key: ValueKey('column-$colId'),
          radius: 16,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${widget.col['name']}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: c.ink, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    decoration: BoxDecoration(color: c.brandFill, borderRadius: BorderRadius.circular(10)),
                    child: Text('${cards.length}', style: TextStyle(fontSize: 12, color: c.onBrand)),
                  ),
                  const Spacer(),
                  MiniButton(
                    key: widget.first ? TourTargets.key('col-menu') : ValueKey('col-menu-$colId'),
                    icon: 'dots',
                    label: 'Column options',
                    onPressed: () => openRenameColumn(context, widget.board, widget.col),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _scrollIfNeeded(
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  constraints: const BoxConstraints(minHeight: 40),
                  decoration: BoxDecoration(color: over ? c.brandFill.withValues(alpha: 0.35) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final card in cards) ...[
                        if (over && _dropBefore == card['id']) const _Placeholder(),
                        DragTarget<DragCard>(
                          onWillAcceptWithDetails: (d) => d.data.cardId != card['id'],
                          onMove: (_) {
                            if (_dropBefore != card['id']) setState(() => _dropBefore = '${card['id']}');
                          },
                          onAcceptWithDetails: (d) => _drop(d.data),
                          builder: (context, _, _) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: widget.first && identical(card, cards.first)
                                ? KeyedSubtree(
                                    key: TourTargets.key('first-card'),
                                    child: _DraggableCard(board: widget.board, card: card, colId: colId),
                                  )
                                : _DraggableCard(board: widget.board, card: card, colId: colId),
                          ),
                        ),
                      ],
                      if (over && _dropBefore == '') const _Placeholder(),
                    ],
                  ),
                ),
              ),
              if (_adding) _inlineAdd(c),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      key: widget.first ? TourTargets.key('add-card') : ValueKey('add-card-$colId'),
                      style: TextButton.styleFrom(foregroundColor: c.muted, alignment: Alignment.centerLeft),
                      onPressed: () {
                        setState(() => _adding = true);
                        WidgetsBinding.instance.addPostFrameCallback((_) => _addFocus.requestFocus());
                      },
                      icon: AppIcon('plus', size: 14, color: c.muted),
                      label: const Text('Add card'),
                    ),
                  ),
                  MiniButton(icon: 'reorder', label: 'Reorder columns', onPressed: () => openReorderColumns(context, widget.board)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// The cards scroll within the column, unless the column's drawn whole (a long screenshot).
  Widget _scrollIfNeeded(Widget cards) => widget.fullHeight ? cards : Flexible(child: SingleChildScrollView(child: cards));

  Widget _inlineAdd(UwuColors c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CallbackShortcutsEscape(
            onEscape: () => setState(() => _adding = false),
            child: TextField(
              controller: _add,
              focusNode: _addFocus,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitAdd(),
              decoration: const InputDecoration(hintText: 'Card title…'),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              FilledButton(onPressed: _submitAdd, child: const Text('Add')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => setState(() => _adding = false), child: const Text('Cancel')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Escape on a field closes what it belongs to.
class CallbackShortcutsEscape extends StatelessWidget {
  const CallbackShortcutsEscape({super.key, required this.onEscape, required this.child});
  final VoidCallback onEscape;
  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(bindings: {const SingleActivator(LogicalKeyboardKey.escape): onEscape}, child: child);
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.brandInk.withValues(alpha: 0.5), width: 1.5),
        color: c.brandFill.withValues(alpha: 0.3),
      ),
    );
  }
}

class _DraggableCard extends StatelessWidget {
  const _DraggableCard({required this.board, required this.card, required this.colId});
  final Json board;
  final Json card;
  final String colId;

  @override
  Widget build(BuildContext context) {
    final tile = CardTile(board: board, card: card, colId: colId);
    final width = context.findRenderObject() is RenderBox ? (context.findRenderObject() as RenderBox).size.width : 260.0;
    final feedback = Material(
      color: Colors.transparent,
      child: SizedBox(
        width: width,
        child: Opacity(
          opacity: 0.9,
          child: Transform.rotate(
            angle: 0.02,
            child: CardTile(board: board, card: card, colId: colId, lifted: true),
          ),
        ),
      ),
    );
    final data = DragCard('${card['id']}', colId);
    final ghost = Opacity(opacity: 0.35, child: tile);
    if (Env.desktop) return Draggable<DragCard>(data: data, feedback: feedback, childWhenDragging: ghost, child: tile);
    return LongPressDraggable<DragCard>(data: data, feedback: feedback, childWhenDragging: ghost, child: tile);
  }
}

/// One card on the board (the site's .card).
class CardTile extends StatelessWidget {
  const CardTile({super.key, required this.board, required this.card, required this.colId, this.lifted = false});
  final Json board;
  final Json card;
  final String colId;
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final labels = labelsOf(card);
    final checklist = checklistOf(card);
    final thumb = thumbOf(card);
    final due = '${card['due'] ?? ''}';
    final start = '${card['start'] ?? ''}';
    final priority = '${card['priority'] ?? ''}';
    final dueCls = due.isEmpty ? '' : dueClass(due, DateTime.now());
    final dueColor = dueCls == 'overdue' ? c.error : (dueCls == 'soon' ? c.warn : c.muted);
    final done = checklist.where((k) => k['done'] == true).length;

    final body = Container(
      decoration: BoxDecoration(
        color: c.surfaceStrong,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
        boxShadow: lifted ? [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 18, offset: const Offset(0, 8))] : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (thumb != null) SizedBox(height: 120, child: CardImage(thumb)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (labels.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [for (final l in labels) LabelChip(text: '${l['text']}', color: '${l['color']}', small: true)],
                    ),
                  ),
                Text('${card['title']}', style: TextStyle(fontSize: 14, color: c.ink, height: 1.3)),
                if (due.isNotEmpty || priority.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (due.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIcon('clock', size: 11, color: dueColor),
                              const SizedBox(width: 4),
                              Text(start.isNotEmpty && start != due ? '$start → $due' : due, style: TextStyle(fontSize: 11, color: dueColor)),
                            ],
                          ),
                        if (priority.isNotEmpty) _Priority(priority),
                      ],
                    ),
                  ),
                if (checklist.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: progressOf(card),
                              minHeight: 4,
                              backgroundColor: c.border,
                              valueColor: AlwaysStoppedAnimation(c.brandInk),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('$done/${checklist.length}', style: TextStyle(fontSize: 11, color: c.muted)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (lifted) return body;
    // One node for a screen reader: the card's title and what's shown on it, pressed to open.
    final said = [
      '${card['title']}',
      if (labels.isNotEmpty) labels.map((l) => l['text']).join(', '),
      if (due.isNotEmpty) 'due $due${dueCls == 'overdue' ? ', overdue' : ''}',
      if (priority.isNotEmpty) '$priority priority',
      if (checklist.isNotEmpty) '$done of ${checklist.length} done',
    ].join(', ');
    return Semantics(
      button: true,
      label: said,
      excludeSemantics: true,
      onTap: () => openCardSheet(context, board, '${card['id']}'),
      child: ContextMenuRegion(
        actions: () => cardMenu(context, board, card, colId),
        child: Hoverable(radius: 12, onTap: () => openCardSheet(context, board, '${card['id']}'), child: body),
      ),
    );
  }
}

/// A card's right-click menu: open it, move it, copy it, delete it.
List<MenuAction> cardMenu(BuildContext context, Json board, Json card, String colId) {
  final cols = columnsOf(board);
  return [
    MenuAction('Open', () => openCardSheet(context, board, '${card['id']}'), icon: 'pencil'),
    for (final col in cols)
      if (col['id'] != colId) MenuAction('Move to ${col['name']}', () => AppState.I.moveCard(board, '${card['id']}', '${col['id']}'), icon: 'arrow-right'),
    MenuAction(
      'Delete card',
      () async {
        if (await AppNav.confirm('Delete this card?')) AppState.I.deleteCard(board, '${card['id']}');
      },
      icon: 'trash',
      danger: true,
    ),
  ];
}

class _Priority extends StatelessWidget {
  const _Priority(this.priority);
  final String priority;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final color = switch (priority) {
      'medium' => c.warn,
      'high' || 'urgent' => c.error,
      _ => c.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: priority == 'urgent' ? color : color.withValues(alpha: 0.45)),
      ),
      child: Text(
        priority,
        style: TextStyle(fontSize: 10.5, color: color, fontWeight: priority == 'urgent' ? FontWeight.w700 : FontWeight.w400),
      ),
    );
  }
}
