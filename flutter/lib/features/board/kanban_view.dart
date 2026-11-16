// A board as columns (the site's renderBoard, buildColumn and buildCard): cards dragged from
// column to column, a card's details on a tap, an inline box to add one, and a round button to
// add a column. On a phone a card is picked up with a long press, so a swipe still scrolls; with
// a mouse it's dragged straight away.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/edge_tray.dart' show TrayClearance;
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
  State<KanbanView> createState() {
    return _KanbanViewState();
  }
}

class _KanbanViewState extends State<KanbanView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The columns side by side, scrolling sideways, with the round Add Column button at the end.
  /// Drawn whole instead (no scrolling, no button) for a long screenshot.
  @override
  Widget build(BuildContext context) {
    final columns = columnsOf(widget.board);
    final narrow = MediaQuery.sizeOf(context).width <= Env.phoneWidth;
    // On a phone a column is most of the screen's width; otherwise a fixed width.
    double columnWidth;
    if (narrow) {
      columnWidth = (MediaQuery.sizeOf(context).width * 0.82).clamp(240.0, 300.0);
    } else {
      columnWidth = 280.0;
    }
    if (widget.fullHeight) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final column in columns) ...[
              SizedBox(
                width: columnWidth,
                child: _Column(board: widget.board, column: column, fullHeight: true),
              ),
              const SizedBox(width: 14),
            ],
          ],
        ),
      );
    }
    double leftPadding;
    if (narrow) {
      leftPadding = 12;
    } else {
      leftPadding = 20;
    }
    return Scrollbar(
      controller: _scroll,
      thumbVisibility: Env.desktop,
      child: SingleChildScrollView(
        key: const ValueKey('columns'),
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        // On a phone, room at the end for the last column to come out from under the open tray.
        padding: EdgeInsets.fromLTRB(leftPadding, 4, 20 + TrayClearance.of(context), 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final column in columns) ...[
              SizedBox(
                width: columnWidth,
                child: _Column(board: widget.board, column: column, first: identical(column, columns.first)),
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
                  if (name != null) {
                    AppState.I.addColumn(widget.board, name);
                  }
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
  const DragCard(this.cardId, this.columnId);
  final String cardId;
  final String columnId;
}

class _Column extends StatefulWidget {
  const _Column({required this.board, required this.column, this.first = false, this.fullHeight = false});
  final Json board;
  final Json column;
  final bool fullHeight;

  /// The first column carries the tour's targets.
  final bool first;

  @override
  State<_Column> createState() {
    return _ColumnState();
  }
}

class _ColumnState extends State<_Column> {
  bool _adding = false;
  final _newCardTitle = TextEditingController();
  final _newCardFocus = FocusNode();

  /// Where a dragged card would land: before this card id, or at the end ('').
  String? _dropBefore;

  /// Adds a card with the typed title (if any) at the end of this column and closes the box.
  void _submitAdd() {
    final title = _newCardTitle.text.trim();
    if (title.isEmpty) {
      return;
    }
    AppState.I.addCard(widget.board, '${widget.column['id']}', title);
    _newCardTitle.clear();
    setState(() {
      _adding = false;
    });
  }

  @override
  void dispose() {
    _newCardTitle.dispose();
    _newCardFocus.dispose();
    super.dispose();
  }

  /// A card dropped on this column: moved here, before the card it was over or at the end.
  void _drop(DragCard draggedCard) {
    String? before;
    if (_dropBefore == '') {
      before = null;
    } else {
      before = _dropBefore;
    }
    setState(() {
      _dropBefore = null;
    });
    AppState.I.moveCard(widget.board, draggedCard.cardId, '${widget.column['id']}', beforeId: before);
  }

  /// The column: its name, card count and menu button; its cards (each a drop target, with a
  /// gap shown where a dragged card would land); the inline add box; and the Add card and
  /// Reorder buttons. The whole column is a drop target too, for dropping at the end.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final cards = cardsOf(widget.column);
    final columnId = '${widget.column['id']}';
    Key menuKey;
    Key addCardKey;
    if (widget.first) {
      menuKey = TourTargets.key('col-menu');
      addCardKey = TourTargets.key('add-card');
    } else {
      menuKey = ValueKey('col-menu-$columnId');
      addCardKey = ValueKey('add-card-$columnId');
    }

    /// One card, and the drop target over it that puts a dragged card before it. The first
    /// card of the first column carries the tour's target.
    Widget cardDropTarget(Json card) {
      return DragTarget<DragCard>(
        onWillAcceptWithDetails: (details) {
          return details.data.cardId != card['id'];
        },
        onMove: (details) {
          if (_dropBefore != card['id']) {
            setState(() {
              _dropBefore = '${card['id']}';
            });
          }
        },
        onAcceptWithDetails: (details) {
          _drop(details.data);
        },
        builder: (context, candidateData, rejectedData) {
          Widget cardWidget;
          if (widget.first && identical(card, cards.first)) {
            cardWidget = KeyedSubtree(
              key: TourTargets.key('first-card'),
              child: _DraggableCard(board: widget.board, card: card, columnId: columnId),
            );
          } else {
            cardWidget = _DraggableCard(board: widget.board, card: card, columnId: columnId);
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: cardWidget,
          );
        },
      );
    }

    return DragTarget<DragCard>(
      onWillAcceptWithDetails: (details) {
        return true;
      },
      onMove: (details) {
        if (_dropBefore == null) {
          setState(() {
            _dropBefore = '';
          });
        }
      },
      onLeave: (data) {
        setState(() {
          _dropBefore = null;
        });
      },
      onAcceptWithDetails: (details) {
        _drop(details.data);
      },
      builder: (context, candidates, rejected) {
        final over = candidates.isNotEmpty;
        Color cardsBackground;
        if (over) {
          cardsBackground = colors.brandFill.withValues(alpha: 0.35);
        } else {
          cardsBackground = Colors.transparent;
        }
        return GlassPanel(
          key: ValueKey('column-$columnId'),
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
                      '${widget.column['name']}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: colors.ink, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    decoration: BoxDecoration(color: colors.brandFill, borderRadius: BorderRadius.circular(10)),
                    child: Text('${cards.length}', style: TextStyle(fontSize: 12, color: colors.onBrand)),
                  ),
                  const Spacer(),
                  MiniButton(
                    key: menuKey,
                    icon: 'dots',
                    label: 'Column options',
                    onPressed: () {
                      openRenameColumn(context, widget.board, widget.column);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _scrollIfNeeded(
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  constraints: const BoxConstraints(minHeight: 40),
                  decoration: BoxDecoration(color: cardsBackground, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final card in cards) ...[
                        if (over && _dropBefore == card['id']) const _Placeholder(),
                        cardDropTarget(card),
                      ],
                      if (over && _dropBefore == '') const _Placeholder(),
                    ],
                  ),
                ),
              ),
              if (_adding) _inlineAdd(colors),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      key: addCardKey,
                      style: TextButton.styleFrom(foregroundColor: colors.muted, alignment: Alignment.centerLeft),
                      onPressed: () {
                        setState(() {
                          _adding = true;
                        });
                        WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
                          _newCardFocus.requestFocus();
                        });
                      },
                      icon: AppIcon('plus', size: 14, color: colors.muted),
                      label: const Text('Add card'),
                    ),
                  ),
                  MiniButton(
                    icon: 'reorder',
                    label: 'Reorder columns',
                    onPressed: () {
                      openReorderColumns(context, widget.board);
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// The cards scroll within the column, unless the column's drawn whole (a long screenshot).
  Widget _scrollIfNeeded(Widget cards) {
    if (widget.fullHeight) {
      return cards;
    } else {
      return Flexible(child: SingleChildScrollView(child: cards));
    }
  }

  /// The box to type a new card's title, with Add and Cancel. Escape closes it too.
  Widget _inlineAdd(UwuColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CallbackShortcutsEscape(
            onEscape: () {
              setState(() {
                _adding = false;
              });
            },
            child: TextField(
              controller: _newCardTitle,
              focusNode: _newCardFocus,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (value) {
                _submitAdd();
              },
              decoration: const InputDecoration(hintText: 'Card title…'),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              FilledButton(onPressed: _submitAdd, child: const Text('Add')),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _adding = false;
                  });
                },
                child: const Text('Cancel'),
              ),
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
  Widget build(BuildContext context) {
    return CallbackShortcuts(bindings: {const SingleActivator(LogicalKeyboardKey.escape): onEscape}, child: child);
  }
}

/// The gap shown where a dragged card would land.
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.brandInk.withValues(alpha: 0.5), width: 1.5),
        color: colors.brandFill.withValues(alpha: 0.3),
      ),
    );
  }
}

/// A card that can be picked up and dragged to another place: straight away with a mouse on
/// the desktop, after a long press on a phone (so a swipe still scrolls).
class _DraggableCard extends StatelessWidget {
  const _DraggableCard({required this.board, required this.card, required this.columnId});
  final Json board;
  final Json card;
  final String columnId;

  @override
  Widget build(BuildContext context) {
    final tile = CardTile(board: board, card: card, columnId: columnId);
    // The lifted copy under the finger is as wide as the card was last drawn.
    final renderObject = context.findRenderObject();
    double width;
    if (renderObject is RenderBox) {
      width = renderObject.size.width;
    } else {
      width = 260.0;
    }
    final feedback = Material(
      color: Colors.transparent,
      child: SizedBox(
        width: width,
        child: Opacity(
          opacity: 0.9,
          child: Transform.rotate(
            angle: 0.02,
            child: CardTile(board: board, card: card, columnId: columnId, lifted: true),
          ),
        ),
      ),
    );
    final data = DragCard('${card['id']}', columnId);
    final ghost = Opacity(opacity: 0.35, child: tile);
    if (Env.desktop) {
      return Draggable<DragCard>(data: data, feedback: feedback, childWhenDragging: ghost, child: tile);
    }
    return LongPressDraggable<DragCard>(data: data, feedback: feedback, childWhenDragging: ghost, child: tile);
  }
}

/// A value as text, or '' when there is none.
String _textOrEmpty(Object? value) {
  if (value == null) {
    return '';
  }
  return '$value';
}

/// One card on the board (the site's .card).
class CardTile extends StatelessWidget {
  const CardTile({super.key, required this.board, required this.card, required this.columnId, this.lifted = false});
  final Json board;
  final Json card;
  final String columnId;
  final bool lifted;

  /// The card: its picture, labels, title, dates (coloured and worded when overdue or due
  /// soon), priority and checklist progress. Read out as one sentence by a screen reader, and
  /// opened with a tap; right-click (or long press) gives its menu.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final labels = labelsOf(card);
    final checklist = checklistOf(card);
    final thumb = thumbOf(card);
    final due = _textOrEmpty(card['due']);
    final start = _textOrEmpty(card['start']);
    final priority = _textOrEmpty(card['priority']);
    // 'overdue', 'soon' or '' for the due date.
    String dueState;
    if (due.isEmpty) {
      dueState = '';
    } else {
      dueState = dueClass(due, DateTime.now());
    }
    Color dueColor;
    if (dueState == 'overdue') {
      dueColor = colors.error;
    } else if (dueState == 'soon') {
      dueColor = colors.warn;
    } else {
      dueColor = colors.muted;
    }
    final doneCount = checklist.where((item) {
      return item['done'] == true;
    }).length;

    // The dates as shown: "start → due" when there's a different start date, then the state in
    // words.
    String datesText;
    if (start.isNotEmpty && start != due) {
      datesText = '$start → $due';
    } else {
      datesText = due;
    }
    String dueStateText;
    if (dueState == 'overdue') {
      dueStateText = ' · overdue';
    } else if (dueState == 'soon') {
      dueStateText = ' · due soon';
    } else {
      dueStateText = '';
    }
    FontWeight? dueWeight;
    if (dueState == 'overdue') {
      dueWeight = FontWeight.w700;
    } else {
      dueWeight = null;
    }
    List<BoxShadow>? shadows;
    if (lifted) {
      shadows = [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 18, offset: const Offset(0, 8))];
    } else {
      shadows = null;
    }

    final body = Container(
      decoration: BoxDecoration(
        color: colors.surfaceStrong,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
        boxShadow: shadows,
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
                      children: [for (final label in labels) LabelChip(text: '${label['text']}', color: '${label['color']}', small: true)],
                    ),
                  ),
                Text('${card['title']}', style: TextStyle(fontSize: 14, color: colors.ink, height: 1.3)),
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
                              Text(
                                // Said in words too, not by colour alone (WCAG 1.4.1).
                                '$datesText$dueStateText',
                                style: TextStyle(fontSize: 11, color: dueColor, fontWeight: dueWeight),
                              ),
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
                              backgroundColor: colors.border,
                              valueColor: AlwaysStoppedAnimation(colors.brandInk),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('$doneCount/${checklist.length}', style: TextStyle(fontSize: 11, color: colors.muted)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (lifted) {
      return body;
    }
    // One node for a screen reader: the card's title and what's shown on it, pressed to open.
    String overdueNote;
    if (dueState == 'overdue') {
      overdueNote = ', overdue';
    } else {
      overdueNote = '';
    }
    final spokenLabel = [
      '${card['title']}',
      if (labels.isNotEmpty)
        labels.map((label) {
          return label['text'];
        }).join(', '),
      if (due.isNotEmpty) 'due $due$overdueNote',
      if (priority.isNotEmpty) '$priority priority',
      if (checklist.isNotEmpty) '$doneCount of ${checklist.length} done',
    ].join(', ');
    return Semantics(
      button: true,
      label: spokenLabel,
      excludeSemantics: true,
      onTap: () {
        openCardSheet(context, board, '${card['id']}');
      },
      child: ContextMenuRegion(
        actions: () {
          return cardMenu(context, board, card, columnId);
        },
        child: Hoverable(
          radius: 12,
          onTap: () {
            openCardSheet(context, board, '${card['id']}');
          },
          child: body,
        ),
      ),
    );
  }
}

/// A card's right-click menu: open it, move it, copy it, delete it.
List<MenuAction> cardMenu(BuildContext context, Json board, Json card, String columnId) {
  final columns = columnsOf(board);
  return [
    MenuAction('Open', () {
      openCardSheet(context, board, '${card['id']}');
    }, icon: 'pencil'),
    for (final column in columns)
      if (column['id'] != columnId)
        MenuAction('Move to ${column['name']}', () {
          AppState.I.moveCard(board, '${card['id']}', '${column['id']}');
        }, icon: 'arrow-right'),
    MenuAction(
      'Delete card',
      () async {
        if (await AppNav.confirm('Delete this card?')) {
          AppState.I.deleteCard(board, '${card['id']}');
        }
      },
      icon: 'trash',
      danger: true,
    ),
  ];
}

/// A card's priority as a small outlined tag: amber for medium, red for high and urgent (urgent
/// in bold with a solid outline).
class _Priority extends StatelessWidget {
  const _Priority(this.priority);
  final String priority;

  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    Color color;
    switch (priority) {
      case 'medium':
        color = colors.warn;
      case 'high' || 'urgent':
        color = colors.error;
      default:
        color = colors.muted;
    }
    Color borderColor;
    FontWeight fontWeight;
    if (priority == 'urgent') {
      borderColor = color;
      fontWeight = FontWeight.w700;
    } else {
      borderColor = color.withValues(alpha: 0.45);
      fontWeight = FontWeight.w400;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        priority,
        style: TextStyle(fontSize: 10.5, color: color, fontWeight: fontWeight),
      ),
    );
  }
}
