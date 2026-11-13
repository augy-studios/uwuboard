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

Future<void> openRenameColumn(BuildContext context, Json board, Json col) {
  final word = AppState.I.isTimeline(board) ? 'Phase' : 'Column';
  final name = TextEditingController(text: '${col['name']}');
  return AppSheet.show(
    context,
    id: 'rename-col',
    width: 420,
    builder: (context) {
      final c = UwuColors.of(context);
      void save() {
        AppSheet.close(context);
        AppState.I.renameColumn(board, col, name.text);
      }

      return SheetFrame(
        title: 'Rename $word',
        footer: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: c.error),
            onPressed: () async {
              final timeline = AppState.I.isTimeline(board);
              final ok = await AppNav.confirm(timeline ? 'Delete this phase and all its tasks?' : 'Delete this column and all its cards?');
              if (!ok || !context.mounted) return;
              AppSheet.close(context);
              AppState.I.deleteColumn(board, '${col['id']}');
            },
            child: Text('Delete $word'),
          ),
          FilledButton(onPressed: save, child: const Text('Save')),
        ],
        children: [
          FieldLabel('$word Name'),
          TextField(controller: name, autofocus: true, onSubmitted: (_) => save()),
        ],
      );
    },
  );
}

Future<void> openReorderColumns(BuildContext context, Json board) {
  final order = [for (final c in columnsOf(board)) '${c['id']}'];
  final names = {for (final c in columnsOf(board)) '${c['id']}': '${c['name']}'};
  return AppSheet.show(
    context,
    id: 'reorder-cols',
    width: 420,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final c = UwuColors.of(context);
        void move(int i, int d) => setState(() {
          final id = order.removeAt(i);
          order.insert(i + d, id);
        });
        return SheetFrame(
          title: 'Reorder Columns',
          footer: [
            OutlinedButton(onPressed: () => AppSheet.close(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                AppSheet.close(context);
                AppState.I.reorderColumns(board, order);
              },
              child: const Text('Apply'),
            ),
          ],
          children: [
            Text('Use the arrows to reorder columns, then click Apply', style: TextStyle(color: c.muted, fontSize: 13)),
            const SizedBox(height: 10),
            for (var i = 0; i < order.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(
                  color: c.surfaceStrong,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(names[order[i]]!, style: TextStyle(color: c.ink)),
                    ),
                    MiniButton(icon: 'chevron-up', label: 'Move up', onPressed: i == 0 ? null : () => move(i, -1), size: 36),
                    MiniButton(icon: 'chevron-down', label: 'Move down', onPressed: i == order.length - 1 ? null : () => move(i, 1), size: 36),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// New Board: a name, Kanban or Timeline, and the columns (or phases) it starts with. The
/// starting columns follow the type, unless they've been changed by hand.
Future<void> openNewBoard(BuildContext context) {
  return AppSheet.show(context, id: 'newboard', width: 460, builder: (context) => const _NewBoard());
}

class _NewBoard extends StatefulWidget {
  const _NewBoard();

  @override
  State<_NewBoard> createState() => _NewBoardState();
}

class _NewBoardState extends State<_NewBoard> {
  final _name = TextEditingController();
  final _chip = TextEditingController();
  String _type = 'kanban';
  List<String> _cols = [...starting['kanban']!];
  bool _adding = false;

  void _setType(String type) {
    final untouched = _cols.join('\n') == starting[_type]!.join('\n');
    setState(() {
      _type = type;
      if (untouched) _cols = [...starting[type]!];
    });
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    AppSheet.close(context);
    await AppState.I.createBoard(name, _type, _cols);
  }

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    Widget option(String type, String icon, String name, String sub) {
      final on = _type == type;
      return Expanded(
        child: Semantics(
          inMutuallyExclusiveGroup: true,
          checked: on,
          button: true,
          child: InkWell(
            key: ValueKey('type-$type'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => _setType(type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: on ? c.brandFill : c.surfaceStrong,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: on ? c.brandInk : c.border, width: on ? 1.5 : 1),
              ),
              child: Row(
                children: [
                  AppIcon(icon, size: 22, color: on ? c.onBrand : c.ink),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(color: on ? c.onBrand : c.ink, fontWeight: FontWeight.w600),
                        ),
                        Text(sub, style: TextStyle(color: on ? c.onBrand : c.muted, fontSize: 11.5)),
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

    return SheetFrame(
      title: 'New Board',
      footer: [
        OutlinedButton(onPressed: () => AppSheet.close(context), child: const Text('Cancel')),
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
          onSubmitted: (_) => _create(),
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
        FieldLabel(_type == 'timeline' ? 'Starting phases' : 'Starting columns'),
        Wrap(
          key: TourTargets.key('nb-cols'),
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < _cols.length; i++)
              InputChip(
                label: Text(_cols[i]),
                onDeleted: () => setState(() => _cols.removeAt(i)),
                onPressed: () => setState(() => _cols.removeAt(i)),
                deleteIcon: AppIcon('close', size: 14, color: c.muted),
                backgroundColor: c.brandFill,
                side: BorderSide(color: c.border),
                labelStyle: TextStyle(color: c.onBrand, fontSize: 13),
              ),
            TextButton(onPressed: () => setState(() => _adding = !_adding), child: const Text('+ Add')),
          ],
        ),
        if (_adding)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: _chip,
              autofocus: true,
              decoration: InputDecoration(hintText: _type == 'timeline' ? 'Phase name' : 'Column name'),
              onSubmitted: (v) {
                final t = v.trim();
                if (t.isEmpty) return;
                setState(() {
                  _cols.add(t);
                  _chip.clear();
                  _adding = false;
                });
              },
            ),
          ),
      ],
    );
  }
}
