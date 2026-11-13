// A card's details (the site's #card-modal): title, description, due date and priority; on a
// Timeline its start date, whether it's a milestone and what it waits for; the column it's in;
// its images, labels and checklist. Edited on a copy and kept with Save, as on the site, except
// images, which go to storage (and leave it) as they're added and removed.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../api/api.dart';
import '../../app/files.dart';
import '../../app/nav.dart';
import '../../app/state.dart';
import '../../data/board.dart';
import '../../data/images.dart';
import '../../data/timeline_logic.dart' as tl;
import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/sheet.dart';
import '../tour/tour.dart';

Future<void> openCardSheet(BuildContext context, Json board, String cardId) {
  final card = findCard(board, cardId);
  final col = columnOfCard(board, cardId);
  if (card == null || col == null) return Future.value();
  return AppSheet.show(
    context,
    id: 'card',
    kind: SheetKind.drawer,
    width: 560,
    builder: (context) => CardSheet(board: board, card: card, colId: '${col['id']}'),
  );
}

/// The colours a label can be: the site's default first.
const labelColours = ['#ccffcc', '#4c9aff', '#36b37e', '#ffb31f', '#ff7452', '#998dd9', '#00b8d9', '#e74c8b', '#5b665f', '#121815'];

class CardSheet extends StatefulWidget {
  const CardSheet({super.key, required this.board, required this.card, required this.colId});
  final Json board;
  final Json card;
  final String colId;

  @override
  State<CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<CardSheet> {
  late final Json _draft = clone(widget.card);
  late final _title = TextEditingController(text: '${widget.card['title'] ?? ''}');
  late final _desc = TextEditingController(text: '${widget.card['description'] ?? ''}');
  final _label = TextEditingController();
  final _check = TextEditingController();
  late String _colId = widget.colId;
  String _labelColour = labelColours.first;
  bool _uploading = false;

  bool get _timeline => AppState.I.isTimeline(widget.board);

  List<dynamic> _list(String key) => (_draft[key] ??= <dynamic>[]) as List;

  Future<void> _pickDate(String key) async {
    final current = DateTime.tryParse('${_draft[key] ?? ''}');
    final picked = await showDatePicker(context: context, initialDate: current ?? DateTime.now(), firstDate: DateTime(1970), lastDate: DateTime(2100));
    if (picked == null) return;
    setState(() => _draft[key] = tl.todayIso(picked));
  }

  Future<void> _addImages() async {
    final files = await pickImages();
    if (files.isEmpty) return;
    setState(() => _uploading = true);
    for (final f in files) {
      final data = resizeToDataUrl(await f.readAsBytes());
      if (data == null) {
        AppNav.toast('That image could not be read', error: true);
        continue;
      }
      if (AppState.I.isGuest) {
        _list('images').add({'id': uid(), 'data': data, 'name': f.name});
      } else {
        try {
          final r = await Api.call('POST', '/images/upload', {'imageData': data, 'fileName': f.name});
          _list('images').add({'id': uid(), 'file': r['file'], 'name': f.name});
        } on ApiError {
          AppNav.toast('Image upload failed', error: true);
        }
      }
    }
    if (_draft['thumbnailId'] == null && _list('images').isNotEmpty) _draft['thumbnailId'] = (_list('images').first as Map)['id'];
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _deleteImage(Json img) async {
    if (!AppState.I.isGuest && (img['file'] != null || img['path'] != null)) {
      try {
        await Api.call('DELETE', '/images/delete', img['file'] != null ? {'file': img['file']} : {'path': img['path']});
      } on ApiError {
        AppNav.toast('Could not delete image from storage', error: true);
      }
    }
    setState(() {
      _list('images').removeWhere((i) => i is Map && i['id'] == img['id']);
      if (_draft['thumbnailId'] == img['id']) {
        _draft['thumbnailId'] = _list('images').isEmpty ? null : (_list('images').first as Map)['id'];
      }
    });
    // Gone from storage, so gone from the card now, not only when it's saved.
    final real = imagesOf(widget.card);
    if (real.any((i) => i['id'] == img['id'])) {
      widget.card['images'] = [
        for (final i in real)
          if (i['id'] != img['id']) i,
      ];
      if (widget.card['thumbnailId'] == img['id']) widget.card['thumbnailId'] = _draft['thumbnailId'];
      AppState.I.persistBoard(widget.board);
    }
  }

  Future<void> _saveImage(Json img) async {
    try {
      final loaded = await ImageStore.load(img);
      final ext = loaded.type.split('/').last.replaceAll('jpeg', 'jpg');
      final name = '${img['name'] ?? ''}'.isNotEmpty ? '${img['name']}' : 'image-${img['id']}.$ext';
      final where = await saveFile(name, loaded.bytes, mime: loaded.type);
      if (where != null) AppNav.toast('Saved $name');
    } catch (_) {
      AppNav.toast('That image could not be loaded', error: true);
    }
  }

  void _openImage(Json img) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 6,
                child: Center(child: CardImage(img, fit: BoxFit.contain)),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: IconButton.filledTonal(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const AppIcon('close', color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final due = '${_draft['due'] ?? ''}';
    final milestone = _timeline ? _draft['milestone'] == true : widget.card['milestone'] == true;
    var start = _timeline ? '${_draft['start'] ?? ''}' : '${widget.card['start'] ?? ''}';
    if (milestone) start = due.isNotEmpty ? due : start;
    if (start.isNotEmpty && due.isNotEmpty && start.compareTo(due) > 0) {
      AppNav.toast('The start date is after the due date', error: true);
      return;
    }
    final card = widget.card;
    final title = _title.text.trim();
    if (title.isNotEmpty) card['title'] = title;
    card['description'] = _desc.text;
    card['due'] = milestone ? (due.isNotEmpty ? due : start) : due;
    card['priority'] = _draft['priority'] ?? '';
    card['labels'] = _list('labels');
    card['checklist'] = _list('checklist');
    card['images'] = _list('images');
    card['thumbnailId'] = _draft['thumbnailId'];
    if (start.isNotEmpty) {
      card['start'] = start;
    } else {
      card.remove('start');
    }
    if (milestone) {
      card['milestone'] = true;
    } else {
      card.remove('milestone');
    }
    final deps = _list('dependsOn');
    if (deps.isNotEmpty) {
      card['dependsOn'] = deps;
    } else {
      card.remove('dependsOn');
    }
    touch(card);
    AppSheet.close(context);
    if (_colId != widget.colId) {
      AppState.I.moveCard(widget.board, '${card['id']}', _colId);
    } else {
      AppState.I.persistBoard(widget.board);
    }
    AppNav.toast('Card saved');
  }

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final col = findColumn(widget.board, _colId);
    return SheetFrame(
      header: TextField(
        key: const ValueKey('card-title'),
        controller: _title,
        style: TextStyle(fontSize: 18, color: c.ink, fontWeight: FontWeight.w600),
        decoration: const InputDecoration(hintText: 'Card title', filled: false, border: InputBorder.none, enabledBorder: InputBorder.none),
      ),
      footer: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: c.error),
          onPressed: () async {
            if (!await AppNav.confirm('Delete this card?') || !context.mounted) return;
            AppSheet.close(context);
            AppState.I.deleteCard(widget.board, '${widget.card['id']}');
          },
          child: const Text('Delete Card'),
        ),
        FilledButton(key: TourTargets.key('card-save'), onPressed: _save, child: const Text('Save')),
      ],
      children: [
        const FieldLabel('Description'),
        TextField(
          key: TourTargets.key('card-desc'),
          controller: _desc,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Add a description…'),
        ),
        Row(
          key: TourTargets.key('card-dates'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _dateField('Due Date', 'due')),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel('Priority'),
                  DropdownButtonFormField<String>(
                    initialValue: priorities.contains(_draft['priority']) ? '${_draft['priority']}' : '',
                    items: const [
                      DropdownMenuItem(value: '', child: Text('None')),
                      DropdownMenuItem(value: 'low', child: Text('Low')),
                      DropdownMenuItem(value: 'medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'high', child: Text('High')),
                      DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                    ],
                    onChanged: (v) => setState(() => _draft['priority'] = v ?? ''),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_timeline) Column(key: TourTargets.key('card-tl'), crossAxisAlignment: CrossAxisAlignment.stretch, children: _timelineFields(c)),
        const FieldLabel('Move to Column'),
        OutlinedButton(
          key: TourTargets.key('card-col'),
          style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
          onPressed: _pickColumn,
          child: Row(
            children: [
              Expanded(child: Text('${col?['name'] ?? 'None'}')),
              AppIcon('chevron-down', size: 14, color: c.muted),
            ],
          ),
        ),
        const FieldLabel('Images'),
        KeyedSubtree(key: TourTargets.key('card-images'), child: _images(c)),
        const FieldLabel('Labels'),
        if (_list('labels').isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _list('labels').length; i++)
                LabelChip(
                  text: '${(_list('labels')[i] as Map)['text']}',
                  color: '${(_list('labels')[i] as Map)['color']}',
                  onRemove: () => setState(() => _list('labels').removeAt(i)),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _label,
                decoration: const InputDecoration(hintText: 'Label text'),
                onSubmitted: (_) => _addLabel(),
              ),
            ),
            const SizedBox(width: 8),
            _colourPicker(c),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _addLabel, child: const Text('Add')),
          ],
        ),
        const FieldLabel('Checklist'),
        for (var i = 0; i < _list('checklist').length; i++) _checkRow(c, i),
        Row(
          key: TourTargets.key('card-check'),
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('check-input'),
                controller: _check,
                decoration: const InputDecoration(hintText: 'Add checklist item'),
                onSubmitted: (_) => _addCheck(),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _addCheck, child: const Text('Add')),
          ],
        ),
      ],
    );
  }

  Widget _dateField(String label, String key, {bool enabled = true}) {
    final c = UwuColors.of(context);
    final v = '${_draft[key] ?? ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(label),
        OutlinedButton(
          style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
          onPressed: enabled ? () => _pickDate(key) : null,
          child: Row(
            children: [
              Expanded(
                child: Text(v.isEmpty ? 'No date' : v, style: TextStyle(color: v.isEmpty ? c.muted : c.ink)),
              ),
              if (v.isNotEmpty && enabled)
                InkWell(
                  onTap: () => setState(() => _draft[key] = ''),
                  child: AppIcon('close', size: 14, color: c.muted),
                )
              else
                AppIcon('clock', size: 14, color: c.muted),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _timelineFields(UwuColors c) {
    final all = allCards(widget.board).toList();
    final deps = [
      for (final d in _list('dependsOn'))
        if (all.any((k) => k['id'] == d)) '$d',
    ];
    final blocked = tl.waitingOn(widget.board, '${widget.card['id']}');
    final choices = all.where((k) => k['id'] != widget.card['id'] && !deps.contains(k['id']) && !blocked.contains(k['id'])).toList();
    final milestone = _draft['milestone'] == true;
    final probe = {..._draft};
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _dateField('Start Date', 'start', enabled: !milestone)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('Milestone'),
                InkWell(
                  onTap: () => setState(() => _draft['milestone'] = !milestone),
                  child: Row(
                    children: [
                      Checkbox(value: milestone, onChanged: (v) => setState(() => _draft['milestone'] = v == true)),
                      Flexible(
                        child: Text('One day, on its due date', style: TextStyle(color: c.ink, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const FieldLabel('Waits For'),
      if (deps.isEmpty) Text('Doesn’t wait for anything', style: TextStyle(color: c.muted, fontSize: 13)),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final id in deps)
            Builder(
              builder: (context) {
                final other = all.firstWhere((k) => k['id'] == id);
                final clash = tl.clashes(other, probe);
                return InputChip(
                  label: Text('${other['title']}'),
                  tooltip: clash ? 'Its dates clash with this task' : null,
                  backgroundColor: clash ? c.errorFill : c.surfaceStrong,
                  labelStyle: TextStyle(color: clash ? c.error : c.ink, fontSize: 13),
                  side: BorderSide(color: clash ? c.error : c.border),
                  deleteIcon: AppIcon('close', size: 14, color: c.muted),
                  deleteButtonTooltipMessage: 'Stop waiting for ${other['title']}',
                  onDeleted: () => setState(() => _list('dependsOn').remove(id)),
                );
              },
            ),
        ],
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: ValueKey('deps-${deps.length}'),
        initialValue: null,
        isExpanded: true,
        hint: Text(choices.isEmpty ? 'No other tasks to wait for' : 'Add a task this one waits for…'),
        items: [
          for (final k in choices)
            DropdownMenuItem(
              value: '${k['id']}',
              child: Text('${k['title']}', overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: choices.isEmpty ? null : (v) => setState(() => _list('dependsOn').add(v)),
      ),
    ];
  }

  Future<void> _pickColumn() async {
    final cols = columnsOf(widget.board);
    final picked = await AppSheet.show<String>(
      context,
      id: 'col-picker',
      width: 360,
      builder: (context) {
        final c = UwuColors.of(context);
        return SheetFrame(
          title: 'Move to Column',
          children: [
            for (final col in cols)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: col['id'] == _colId ? c.brandFill : c.surfaceStrong,
                  borderRadius: BorderRadius.circular(10),
                  child: ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    title: Text('${col['name']}', style: TextStyle(color: col['id'] == _colId ? c.onBrand : c.ink)),
                    onTap: () => AppSheet.close(context, '${col['id']}'),
                  ),
                ),
              ),
          ],
        );
      },
    );
    if (picked != null) setState(() => _colId = picked);
  }

  Widget _images(UwuColors c) {
    final images = [
      for (final i in _list('images'))
        if (i is Map) Map<String, dynamic>.from(i),
    ];
    final thumbId = _draft['thumbnailId'] ?? (images.isEmpty ? null : images.first['id']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (images.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final img in images)
                Container(
                  width: 150,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: img['id'] == thumbId ? c.brandInk : c.border, width: img['id'] == thumbId ? 2 : 1),
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () => _openImage(img),
                        child: SizedBox(height: 96, width: 150, child: CardImage(img)),
                      ),
                      Container(
                        color: c.surfaceStrong,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            MiniButton(
                              icon: 'star',
                              label: img['id'] == thumbId ? 'Thumbnail' : 'Set as thumbnail',
                              color: img['id'] == thumbId ? c.warn : c.muted,
                              onPressed: () => setState(() => _draft['thumbnailId'] = img['id']),
                            ),
                            MiniButton(icon: 'download', label: 'Save', onPressed: () => _saveImage(img)),
                            MiniButton(icon: 'trash', label: 'Delete', color: c.error, onPressed: () => _deleteImage(img)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _uploading ? null : _addImages,
            icon: _uploading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : AppIcon('image-add', size: 14, color: c.ink),
            label: const Text('Add Image'),
          ),
        ),
      ],
    );
  }

  Widget _colourPicker(UwuColors c) {
    return PopupMenuButton<String>(
      tooltip: 'Label colour',
      onSelected: (v) => setState(() => _labelColour = v),
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final hex in labelColours)
                InkWell(
                  onTap: () {
                    setState(() => _labelColour = hex);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Color(0xFF000000 | parseHex(hex)!),
                      shape: BoxShape.circle,
                      border: Border.all(color: c.border),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Color(0xFF000000 | parseHex(_labelColour)!),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border, width: 1.5),
        ),
      ),
    );
  }

  void _addLabel() {
    final t = _label.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _list('labels').add({'text': t, 'color': _labelColour});
      _label.clear();
    });
  }

  void _addCheck() {
    final t = _check.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _list('checklist').add({'text': t, 'done': false});
      _check.clear();
    });
  }

  Widget _checkRow(UwuColors c, int i) {
    final item = _list('checklist')[i] as Map;
    final done = item['done'] == true;
    return Row(
      children: [
        Checkbox(value: done, onChanged: (v) => setState(() => item['done'] = v == true)),
        Expanded(
          child: Text(
            '${item['text']}',
            style: TextStyle(color: done ? c.muted : c.ink, decoration: done ? TextDecoration.lineThrough : null, fontSize: 14),
          ),
        ),
        MiniButton(icon: 'close', label: 'Remove', onPressed: () => setState(() => _list('checklist').removeAt(i))),
      ],
    );
  }
}

/// Exports the open board to a file, its images inside it.
Future<void> exportActiveBoard() async {
  final board = AppState.I.activeBoard;
  if (board == null) return;
  final r = await AppState.I.exportBoard(board);
  final where = await saveFile(exportName(board), utf8.encode(r.json), mime: 'application/json');
  if (where == null) return;
  AppNav.toast(r.missing > 0 ? 'Board exported, without ${r.missing == 1 ? '1 image' : '${r.missing} images'} that wouldn’t load' : 'Board exported');
}

/// Imports a board file over the open board (or as a new one, with none open).
Future<void> importOverActiveBoard() async {
  final f = await pickJson();
  if (f == null) return;
  Object? json;
  try {
    json = jsonDecode(await f.readAsString());
  } catch (_) {
    AppNav.toast('Invalid JSON file', error: true);
    return;
  }
  await AppState.I.importBoard(json, asNew: false);
}
