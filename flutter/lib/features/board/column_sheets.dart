// The column windows (the site's #rename-col-modal and #reorder-cols-modal), and the New Board
// window (#new-board-modal). On a timeline a column is a phase, and the words say so.
import 'package:flutter/material.dart';

import '../../app/nav.dart';
import '../../app/state.dart';
import '../../data/board.dart';
import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/sheet.dart';
import '../tour/tour.dart';

/// The Rename Column (or Phase) window: a new name to save, or the column deleted with all its
/// cards after asking.
Future<void> openRenameColumn(BuildContext context, Json board, Json column) {
  String word;
  if (AppState.instance.isTimeline(board)) {
    word = 'Phase';
  } else {
    word = 'Column';
  }
  final name = TextEditingController(text: '${column['name']}');
  return AppSheet.show(
    context,
    id: 'rename-col',
    width: 420,
    builder: (context) {
      final colors = UwuColors.of(context);
      void save() {
        AppSheet.close(context);
        AppState.instance.renameColumn(board, column, name.text);
      }

      return SheetFrame(
        title: 'Rename $word',
        footer: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: colors.error),
            onPressed: () async {
              final timeline = AppState.instance.isTimeline(board);
              String question;
              if (timeline) {
                question = 'Delete this phase and all its tasks?';
              } else {
                question = 'Delete this column and all its cards?';
              }
              final confirmed = await AppNavigation.confirm(question);
              if (!confirmed || !context.mounted) {
                return;
              }
              AppSheet.close(context);
              AppState.instance.deleteColumn(board, '${column['id']}');
            },
            child: Text('Delete $word'),
          ),
          FilledButton(onPressed: save, child: const Text('Save')),
        ],
        children: [
          FieldLabel('$word Name'),
          TextField(
            controller: name,
            autofocus: true,
            onSubmitted: (value) {
              save();
            },
          ),
        ],
      );
    },
  );
}

/// The Reorder Columns window: each column with up and down arrows, applied all at once.
Future<void> openReorderColumns(BuildContext context, Json board) {
  final order = [for (final column in columnsOf(board)) '${column['id']}'];
  final names = {for (final column in columnsOf(board)) '${column['id']}': '${column['name']}'};
  return AppSheet.show(
    context,
    id: 'reorder-cols',
    width: 420,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final colors = UwuColors.of(context);

          /// Moves the column at [index] by [offset] places (-1 up, 1 down).
          void move(int index, int offset) {
            setState(() {
              final id = order.removeAt(index);
              order.insert(index + offset, id);
            });
          }

          /// One column's row: its name and the two arrows (the top one can't go up, nor the
          /// bottom one down).
          Widget columnRow(int index) {
            VoidCallback? onMoveUp;
            if (index == 0) {
              onMoveUp = null;
            } else {
              onMoveUp = () {
                move(index, -1);
              };
            }
            VoidCallback? onMoveDown;
            if (index == order.length - 1) {
              onMoveDown = null;
            } else {
              onMoveDown = () {
                move(index, 1);
              };
            }
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                color: colors.surfaceStrong,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(names[order[index]]!, style: TextStyle(color: colors.ink)),
                  ),
                  MiniButton(icon: 'chevron-up', label: 'Move up', onPressed: onMoveUp, size: 36),
                  MiniButton(icon: 'chevron-down', label: 'Move down', onPressed: onMoveDown, size: 36),
                ],
              ),
            );
          }

          return SheetFrame(
            title: 'Reorder Columns',
            footer: [
              OutlinedButton(
                onPressed: () {
                  AppSheet.close(context);
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  AppSheet.close(context);
                  AppState.instance.reorderColumns(board, order);
                },
                child: const Text('Apply'),
              ),
            ],
            children: [
              Text('Use the arrows to reorder columns, then click Apply', style: TextStyle(color: colors.muted, fontSize: 13)),
              const SizedBox(height: 10),
              for (var index = 0; index < order.length; index = index + 1) columnRow(index),
            ],
          );
        },
      );
    },
  );
}

/// New Board: a name, Kanban or Timeline, and the columns (or phases) it starts with. The
/// starting columns follow the type, unless they've been changed by hand.
Future<void> openNewBoard(BuildContext context) {
  return AppSheet.show(
    context,
    id: 'newboard',
    width: 460,
    builder: (context) {
      return const _NewBoard();
    },
  );
}

class _NewBoard extends StatefulWidget {
  const _NewBoard();

  @override
  State<_NewBoard> createState() {
    return _NewBoardState();
  }
}

class _NewBoardState extends State<_NewBoard> {
  final _name = TextEditingController();
  final _newColumnName = TextEditingController();
  String _type = 'kanban';
  List<String> _columns = [...starting['kanban']!];
  bool _adding = false;

  /// Switches between Kanban and Timeline. The starting columns change to the new type's only
  /// if they are still the old type's, untouched.
  void _setType(String type) {
    final untouched = _columns.join('\n') == starting[_type]!.join('\n');
    setState(() {
      _type = type;
      if (untouched) {
        _columns = [...starting[type]!];
      }
    });
  }

  /// Makes the board (if it has a name) and closes the window.
  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    AppSheet.close(context);
    await AppState.instance.createBoard(name, _type, _columns);
  }

  /// The window: the name, the two board types to choose between, and the starting columns as
  /// chips (tap one to remove it) with "+ Add" to type another.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);

    /// One board type to choose: its icon, name and a line about it, filled when chosen.
    Widget option(String type, String icon, String name, String description) {
      final isSelected = _type == type;
      Color fillColor;
      Color borderColor;
      double borderWidth;
      Color foregroundColor;
      Color descriptionColor;
      if (isSelected) {
        fillColor = colors.brandFill;
        borderColor = colors.brandInk;
        borderWidth = 1.5;
        foregroundColor = colors.onBrand;
        descriptionColor = colors.onBrand;
      } else {
        fillColor = colors.surfaceStrong;
        borderColor = colors.border;
        borderWidth = 1;
        foregroundColor = colors.ink;
        descriptionColor = colors.muted;
      }
      return Expanded(
        child: Semantics(
          inMutuallyExclusiveGroup: true,
          checked: isSelected,
          button: true,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            key: ValueKey('type-$type'),
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              _setType(type);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: borderWidth),
              ),
              child: Row(
                children: [
                  AppIcon(icon, size: 22, color: foregroundColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(color: foregroundColor, fontWeight: FontWeight.w600),
                        ),
                        Text(description, style: TextStyle(color: descriptionColor, fontSize: 11.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    /// One starting column as a chip; tapping it or its cross removes it.
    Widget columnChip(int index) {
      return InputChip(
        mouseCursor: WidgetStateMouseCursor.clickable,
        label: Text(_columns[index]),
        onDeleted: () {
          setState(() {
            _columns.removeAt(index);
          });
        },
        onPressed: () {
          setState(() {
            _columns.removeAt(index);
          });
        },
        deleteIcon: AppIcon('close', size: 14, color: colors.muted),
        backgroundColor: colors.brandFill,
        side: BorderSide(color: colors.border),
        labelStyle: TextStyle(color: colors.onBrand, fontSize: 13),
      );
    }

    String startingLabel;
    String newColumnHint;
    if (_type == 'timeline') {
      startingLabel = 'Starting phases';
      newColumnHint = 'Phase name';
    } else {
      startingLabel = 'Starting columns';
      newColumnHint = 'Column name';
    }

    return SheetFrame(
      title: 'New Board',
      footer: [
        OutlinedButton(
          onPressed: () {
            AppSheet.close(context);
          },
          child: const Text('Cancel'),
        ),
        FilledButton(key: TourTargets.key('nb-create'), onPressed: _create, child: const Text('Create')),
      ],
      children: [
        const FieldLabel('Board Name'),
        TextField(
          key: TourTargets.key('nb-name'),
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Sprint 67'),
          onSubmitted: (value) {
            _create();
          },
        ),
        const FieldLabel('Type'),
        Row(
          key: TourTargets.key('nb-type'),
          children: [
            option('kanban', 'kanban', 'Kanban', 'Cards move across columns'),
            const SizedBox(width: 8),
            option('timeline', 'timeline', 'Timeline', 'Tasks as bars across dates'),
          ],
        ),
        FieldLabel(startingLabel),
        Wrap(
          key: TourTargets.key('nb-cols'),
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var index = 0; index < _columns.length; index = index + 1) columnChip(index),
            TextButton(
              onPressed: () {
                setState(() {
                  _adding = !_adding;
                });
              },
              child: const Text('+ Add'),
            ),
          ],
        ),
        if (_adding)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: _newColumnName,
              autofocus: true,
              decoration: InputDecoration(hintText: newColumnHint),
              onSubmitted: (value) {
                final trimmedName = value.trim();
                if (trimmedName.isEmpty) {
                  return;
                }
                setState(() {
                  _columns.add(trimmedName);
                  _newColumnName.clear();
                  _adding = false;
                });
              },
            ),
          ),
      ],
    );
  }
}
