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
import '../../data/timeline_logic.dart' as timeline;
import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/sheet.dart';
import '../tour/tour.dart';

/// Opens the details drawer for a card, when the card and its column can be found.
Future<void> openCardSheet(BuildContext context, Json board, String cardId) {
  final card = findCard(board, cardId);
  final column = columnOfCard(board, cardId);
  if (card == null || column == null) {
    return Future.value();
  }
  return AppSheet.show(
    context,
    id: 'card',
    kind: SheetKind.drawer,
    width: 560,
    builder: (context) {
      return CardSheet(board: board, card: card, columnId: '${column['id']}');
    },
  );
}

/// The colours a label can be: the site's default first.
const labelColours = ['#ccffcc', '#4c9aff', '#36b37e', '#ffb31f', '#ff7452', '#998dd9', '#00b8d9', '#e74c8b', '#5b665f', '#121815'];

/// A value as text, or empty text when there is no value.
String _textOrEmpty(Object? value) {
  if (value == null) {
    return '';
  }
  return '$value';
}

class CardSheet extends StatefulWidget {
  const CardSheet({super.key, required this.board, required this.card, required this.columnId});
  final Json board;
  final Json card;
  final String columnId;

  @override
  State<CardSheet> createState() {
    return _CardSheetState();
  }
}

class _CardSheetState extends State<CardSheet> {
  late final Json _draft = clone(widget.card);
  late final _title = TextEditingController(text: _textOrEmpty(widget.card['title']));
  late final _description = TextEditingController(text: _textOrEmpty(widget.card['description']));
  final _labelText = TextEditingController();
  final _checklistText = TextEditingController();
  late String _columnId = widget.columnId;
  String _labelColour = labelColours.first;
  bool _uploading = false;

  bool get _isTimeline {
    return AppState.instance.isTimeline(widget.board);
  }

  /// The draft's list under this key, made (and kept on the draft) when there isn't one yet.
  List<dynamic> _list(String key) {
    final existing = _draft[key];
    if (existing != null) {
      return existing as List;
    }
    final created = <dynamic>[];
    _draft[key] = created;
    return created;
  }

  /// Asks for a date and puts it on the draft under this key.
  Future<void> _pickDate(String key) async {
    final current = DateTime.tryParse(_textOrEmpty(_draft[key]));
    DateTime initialDate;
    if (current == null) {
      initialDate = DateTime.now();
    } else {
      initialDate = current;
    }
    final picked = await showDatePicker(context: context, initialDate: initialDate, firstDate: DateTime(1970), lastDate: DateTime(2100));
    if (picked == null) {
      return;
    }
    setState(() {
      _draft[key] = timeline.todayIsoDate(picked);
    });
  }

  /// Picks images, shrinks each, and adds it to the draft: kept inside the card for a guest,
  /// uploaded to storage when signed in. The first image becomes the thumbnail if there's none.
  Future<void> _addImages() async {
    final files = await pickImages();
    if (files.isEmpty) {
      return;
    }
    setState(() {
      _uploading = true;
    });
    for (final file in files) {
      final data = resizeToDataUrl(await file.readAsBytes());
      if (data == null) {
        AppNavigation.toast('That image could not be read', error: true);
        continue;
      }
      if (AppState.instance.isGuest) {
        _list('images').add({'id': uniqueId(), 'data': data, 'name': file.name});
      } else {
        try {
          final response = await Api.call('POST', '/images/upload', {'imageData': data, 'fileName': file.name});
          _list('images').add({'id': uniqueId(), 'file': response['file'], 'name': file.name});
        } on ApiError {
          AppNavigation.toast('Image upload failed', error: true);
        }
      }
    }
    if (_draft['thumbnailId'] == null && _list('images').isNotEmpty) {
      _draft['thumbnailId'] = (_list('images').first as Map)['id'];
    }
    if (mounted) {
      setState(() {
        _uploading = false;
      });
    }
  }

  /// Deletes an image from storage (when signed in) and from the draft, and from the saved card
  /// straight away too, since it's gone from storage.
  Future<void> _deleteImage(Json image) async {
    if (!AppState.instance.isGuest && (image['file'] != null || image['path'] != null)) {
      try {
        Map<String, dynamic> target;
        if (image['file'] != null) {
          target = {'file': image['file']};
        } else {
          target = {'path': image['path']};
        }
        await Api.call('DELETE', '/images/delete', target);
      } on ApiError {
        AppNavigation.toast('Could not delete image from storage', error: true);
      }
    }
    setState(() {
      _list('images').removeWhere((entry) {
        return entry is Map && entry['id'] == image['id'];
      });
      if (_draft['thumbnailId'] == image['id']) {
        if (_list('images').isEmpty) {
          _draft['thumbnailId'] = null;
        } else {
          _draft['thumbnailId'] = (_list('images').first as Map)['id'];
        }
      }
    });
    // Gone from storage, so gone from the card now, not only when it's saved.
    final savedImages = imagesOf(widget.card);
    final onSavedCard = savedImages.any((savedImage) {
      return savedImage['id'] == image['id'];
    });
    if (onSavedCard) {
      widget.card['images'] = [
        for (final savedImage in savedImages)
          if (savedImage['id'] != image['id']) savedImage,
      ];
      if (widget.card['thumbnailId'] == image['id']) {
        widget.card['thumbnailId'] = _draft['thumbnailId'];
      }
      AppState.instance.persistBoard(widget.board);
    }
  }

  /// Saves an image to a file, named after the image (or its id when it has no name).
  Future<void> _saveImage(Json image) async {
    try {
      final loaded = await ImageStore.load(image);
      final extension = loaded.type.split('/').last.replaceAll('jpeg', 'jpg');
      String name;
      if (_textOrEmpty(image['name']).isNotEmpty) {
        name = '${image['name']}';
      } else {
        name = 'image-${image['id']}.$extension';
      }
      final where = await saveFile(name, loaded.bytes, mime: loaded.type);
      if (where != null) {
        AppNavigation.toast('Saved $name');
      }
    } catch (error) {
      AppNavigation.toast('That image could not be loaded', error: true);
    }
  }

  /// Shows an image full screen, zoomable, with a close button.
  void _openImage(Json image) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  maxScale: 6,
                  child: Center(child: CardImage(image, fit: BoxFit.contain)),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: SafeArea(
                  child: IconButton.filledTonal(
                    tooltip: 'Close',
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const AppIcon('close', color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Copies the draft onto the card (refusing a start date after the due date), closes the
  /// sheet, and saves the board, moving the card if its column changed.
  void _save() {
    final due = _textOrEmpty(_draft['due']);
    bool milestone;
    if (_isTimeline) {
      milestone = _draft['milestone'] == true;
    } else {
      milestone = widget.card['milestone'] == true;
    }
    String start;
    if (_isTimeline) {
      start = _textOrEmpty(_draft['start']);
    } else {
      start = _textOrEmpty(widget.card['start']);
    }
    // A milestone is one day: it starts on its due date, when it has one.
    if (milestone) {
      if (due.isNotEmpty) {
        start = due;
      }
    }
    if (start.isNotEmpty && due.isNotEmpty && start.compareTo(due) > 0) {
      AppNavigation.toast('The start date is after the due date', error: true);
      return;
    }
    final card = widget.card;
    final title = _title.text.trim();
    if (title.isNotEmpty) {
      card['title'] = title;
    }
    card['description'] = _description.text;
    if (milestone) {
      if (due.isNotEmpty) {
        card['due'] = due;
      } else {
        card['due'] = start;
      }
    } else {
      card['due'] = due;
    }
    final priority = _draft['priority'];
    if (priority == null) {
      card['priority'] = '';
    } else {
      card['priority'] = priority;
    }
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
    final dependsOn = _list('dependsOn');
    if (dependsOn.isNotEmpty) {
      card['dependsOn'] = dependsOn;
    } else {
      card.remove('dependsOn');
    }
    touch(card);
    AppSheet.close(context);
    if (_columnId != widget.columnId) {
      AppState.instance.moveCard(widget.board, '${card['id']}', _columnId);
    } else {
      AppState.instance.persistBoard(widget.board);
    }
    AppNavigation.toast('Card saved');
  }

  /// The sheet: the title on top, then description, due date and priority, the Timeline fields
  /// (on a Timeline), the column, images, labels and checklist; Delete and Save at the bottom.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final column = findColumn(widget.board, _columnId);
    String initialPriority;
    if (priorities.contains(_draft['priority'])) {
      initialPriority = '${_draft['priority']}';
    } else {
      initialPriority = '';
    }
    String columnName = 'None';
    if (column != null && column['name'] != null) {
      columnName = '${column['name']}';
    }
    return SheetFrame(
      header: TextField(
        key: const ValueKey('card-title'),
        controller: _title,
        style: TextStyle(fontSize: 18, color: colors.ink, fontWeight: FontWeight.w600),
        decoration: const InputDecoration(hintText: 'Card title', filled: false, border: InputBorder.none, enabledBorder: InputBorder.none),
      ),
      footer: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: colors.error),
          onPressed: () async {
            if (!await AppNavigation.confirm('Delete this card?') || !context.mounted) {
              return;
            }
            AppSheet.close(context);
            AppState.instance.deleteCard(widget.board, '${widget.card['id']}');
          },
          child: const Text('Delete Card'),
        ),
        FilledButton(key: TourTargets.key('card-save'), onPressed: _save, child: const Text('Save')),
      ],
      children: [
        const FieldLabel('Description'),
        TextField(
          key: TourTargets.key('card-desc'),
          controller: _description,
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
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    dropdownMenuItemMouseCursor: WidgetStateMouseCursor.clickable,
                    initialValue: initialPriority,
                    items: const [
                      DropdownMenuItem(value: '', child: Text('None')),
                      DropdownMenuItem(value: 'low', child: Text('Low')),
                      DropdownMenuItem(value: 'medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'high', child: Text('High')),
                      DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        if (value == null) {
                          _draft['priority'] = '';
                        } else {
                          _draft['priority'] = value;
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_isTimeline) Column(key: TourTargets.key('card-tl'), crossAxisAlignment: CrossAxisAlignment.stretch, children: _timelineFields(colors)),
        const FieldLabel('Move to Column'),
        OutlinedButton(
          key: TourTargets.key('card-col'),
          style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
          onPressed: _pickColumn,
          child: Row(
            children: [
              Expanded(child: Text(columnName)),
              AppIcon('chevron-down', size: 14, color: colors.muted),
            ],
          ),
        ),
        const FieldLabel('Images'),
        KeyedSubtree(key: TourTargets.key('card-images'), child: _images(colors)),
        const FieldLabel('Labels'),
        if (_list('labels').isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var labelIndex = 0; labelIndex < _list('labels').length; labelIndex = labelIndex + 1)
                LabelChip(
                  text: '${(_list('labels')[labelIndex] as Map)['text']}',
                  color: '${(_list('labels')[labelIndex] as Map)['color']}',
                  onRemove: () {
                    setState(() {
                      _list('labels').removeAt(labelIndex);
                    });
                  },
                ),
            ],
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _labelText,
                decoration: const InputDecoration(hintText: 'Label text'),
                onSubmitted: (text) {
                  _addLabel();
                },
              ),
            ),
            const SizedBox(width: 8),
            _colourPicker(colors),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _addLabel, child: const Text('Add')),
          ],
        ),
        const FieldLabel('Checklist'),
        for (var itemIndex = 0; itemIndex < _list('checklist').length; itemIndex = itemIndex + 1) _checkRow(colors, itemIndex),
        Row(
          key: TourTargets.key('card-check'),
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('check-input'),
                controller: _checklistText,
                decoration: const InputDecoration(hintText: 'Add checklist item'),
                onSubmitted: (text) {
                  _addCheck();
                },
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _addCheck, child: const Text('Add')),
          ],
        ),
      ],
    );
  }

  /// A date on the draft as a button that opens a date picker, with a cross to clear it.
  Widget _dateField(String label, String key, {bool enabled = true}) {
    final colors = UwuColors.of(context);
    final value = _textOrEmpty(_draft[key]);
    String shownText;
    Color textColour;
    if (value.isEmpty) {
      shownText = 'No date';
      textColour = colors.muted;
    } else {
      shownText = value;
      textColour = colors.ink;
    }
    VoidCallback? onPressed;
    if (enabled) {
      onPressed = () {
        _pickDate(key);
      };
    } else {
      onPressed = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(label),
        OutlinedButton(
          style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
          onPressed: onPressed,
          child: Row(
            children: [
              Expanded(
                child: Text(shownText, style: TextStyle(color: textColour)),
              ),
              if (value.isNotEmpty && enabled)
                InkWell(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  onTap: () {
                    setState(() {
                      _draft[key] = '';
                    });
                  },
                  child: AppIcon('close', size: 14, color: colors.muted),
                )
              else
                AppIcon('clock', size: 14, color: colors.muted),
            ],
          ),
        ),
      ],
    );
  }

  /// The fields only a Timeline has: the start date, Milestone, and the tasks this one waits
  /// for (red where their dates clash), with a menu to add another.
  List<Widget> _timelineFields(UwuColors colors) {
    final allTaskCards = allCards(widget.board).toList();
    final dependencyIds = [
      for (final dependencyId in _list('dependsOn'))
        if (allTaskCards.any((otherCard) {
          return otherCard['id'] == dependencyId;
        }))
          '$dependencyId',
    ];
    final blocked = timeline.waitingOn(widget.board, '${widget.card['id']}');
    final choices = allTaskCards.where((otherCard) {
      return otherCard['id'] != widget.card['id'] && !dependencyIds.contains(otherCard['id']) && !blocked.contains(otherCard['id']);
    }).toList();
    final milestone = _draft['milestone'] == true;
    final probe = {..._draft};
    String choicesHint;
    ValueChanged<String?>? onDependencyPicked;
    if (choices.isEmpty) {
      choicesHint = 'No other tasks to wait for';
      onDependencyPicked = null;
    } else {
      choicesHint = 'Add a task this one waits for…';
      onDependencyPicked = (value) {
        setState(() {
          _list('dependsOn').add(value);
        });
      };
    }
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
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  onTap: () {
                    setState(() {
                      _draft['milestone'] = !milestone;
                    });
                  },
                  child: Row(
                    children: [
                      Checkbox(
                        value: milestone,
                        onChanged: (value) {
                          setState(() {
                            _draft['milestone'] = value == true;
                          });
                        },
                      ),
                      Flexible(
                        child: Text('One day, on its due date', style: TextStyle(color: colors.ink, fontSize: 13)),
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
      if (dependencyIds.isEmpty) Text('Doesn’t wait for anything', style: TextStyle(color: colors.muted, fontSize: 13)),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final id in dependencyIds)
            Builder(
              builder: (context) {
                final other = allTaskCards.firstWhere((otherCard) {
                  return otherCard['id'] == id;
                });
                final clash = timeline.clashes(other, probe);
                String? tooltip;
                Color chipColour;
                Color textColour;
                Color edgeColour;
                if (clash) {
                  tooltip = 'Its dates clash with this task';
                  chipColour = colors.errorFill;
                  textColour = colors.error;
                  edgeColour = colors.error;
                } else {
                  tooltip = null;
                  chipColour = colors.surfaceStrong;
                  textColour = colors.ink;
                  edgeColour = colors.border;
                }
                return InputChip(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  label: Text('${other['title']}'),
                  tooltip: tooltip,
                  backgroundColor: chipColour,
                  labelStyle: TextStyle(color: textColour, fontSize: 13),
                  side: BorderSide(color: edgeColour),
                  deleteIcon: AppIcon('close', size: 14, color: colors.muted),
                  deleteButtonTooltipMessage: 'Stop waiting for ${other['title']}',
                  onDeleted: () {
                    setState(() {
                      _list('dependsOn').remove(id);
                    });
                  },
                );
              },
            ),
        ],
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: ValueKey('deps-${dependencyIds.length}'),
        mouseCursor: WidgetStateMouseCursor.clickable,
        dropdownMenuItemMouseCursor: WidgetStateMouseCursor.clickable,
        initialValue: null,
        isExpanded: true,
        hint: Text(choicesHint),
        items: [
          for (final otherCard in choices)
            DropdownMenuItem(
              value: '${otherCard['id']}',
              child: Text('${otherCard['title']}', overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onDependencyPicked,
      ),
    ];
  }

  /// A small sheet listing the board's columns; the one picked becomes the card's column.
  Future<void> _pickColumn() async {
    final columns = columnsOf(widget.board);
    final picked = await AppSheet.show<String>(
      context,
      id: 'col-picker',
      width: 360,
      builder: (context) {
        final colors = UwuColors.of(context);
        return SheetFrame(
          title: 'Move to Column',
          children: [for (final column in columns) _columnChoice(context, colors, column)],
        );
      },
    );
    if (picked != null) {
      setState(() {
        _columnId = picked;
      });
    }
  }

  /// One column in the column picker, filled with the brand colour when it's the card's column.
  Widget _columnChoice(BuildContext sheetContext, UwuColors colors, Json column) {
    Color fillColour;
    Color textColour;
    if (column['id'] == _columnId) {
      fillColour = colors.brandFill;
      textColour = colors.onBrand;
    } else {
      fillColour = colors.surfaceStrong;
      textColour = colors.ink;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: fillColour,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: Text('${column['name']}', style: TextStyle(color: textColour)),
          onTap: () {
            AppSheet.close(sheetContext, '${column['id']}');
          },
        ),
      ),
    );
  }

  /// The draft's images as tiles (the thumbnail outlined), and the Add Image button.
  Widget _images(UwuColors colors) {
    final images = [
      for (final entry in _list('images'))
        if (entry is Map) Map<String, dynamic>.from(entry),
    ];
    // The thumbnail: the one chosen, or else the first image.
    Object? thumbnailId = _draft['thumbnailId'];
    if (thumbnailId == null) {
      if (images.isEmpty) {
        thumbnailId = null;
      } else {
        thumbnailId = images.first['id'];
      }
    }
    VoidCallback? onAddPressed;
    Widget addIcon;
    if (_uploading) {
      onAddPressed = null;
      addIcon = const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2));
    } else {
      onAddPressed = _addImages;
      addIcon = AppIcon('image-add', size: 14, color: colors.ink);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (images.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final image in images) _imageTile(colors, image, thumbnailId)],
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onAddPressed,
            icon: addIcon,
            label: const Text('Add Image'),
          ),
        ),
      ],
    );
  }

  /// One image tile: the picture (tap to open it), and buttons to make it the thumbnail, save
  /// it, or delete it.
  Widget _imageTile(UwuColors colors, Map<String, dynamic> image, Object? thumbnailId) {
    final isThumbnail = image['id'] == thumbnailId;
    Color edgeColour;
    double edgeWidth;
    String starLabel;
    Color starColour;
    if (isThumbnail) {
      edgeColour = colors.brandInk;
      edgeWidth = 2;
      starLabel = 'Thumbnail';
      starColour = colors.warning;
    } else {
      edgeColour = colors.border;
      edgeWidth = 1;
      starLabel = 'Set as thumbnail';
      starColour = colors.muted;
    }
    return Container(
      width: 150,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: edgeColour, width: edgeWidth),
      ),
      child: Column(
        children: [
          InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: () {
              _openImage(image);
            },
            child: SizedBox(height: 96, width: 150, child: CardImage(image)),
          ),
          Container(
            color: colors.surfaceStrong,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                MiniButton(
                  icon: 'star',
                  label: starLabel,
                  color: starColour,
                  onPressed: () {
                    setState(() {
                      _draft['thumbnailId'] = image['id'];
                    });
                  },
                ),
                MiniButton(
                  icon: 'download',
                  label: 'Save',
                  onPressed: () {
                    _saveImage(image);
                  },
                ),
                MiniButton(
                  icon: 'trash',
                  label: 'Delete',
                  color: colors.error,
                  onPressed: () {
                    _deleteImage(image);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The swatch showing the new label's colour; pressed, it offers every label colour.
  Widget _colourPicker(UwuColors colors) {
    return PopupMenuButton<String>(
      tooltip: 'Label colour',
      onSelected: (value) {
        setState(() {
          _labelColour = value;
        });
      },
      itemBuilder: (menuContext) {
        return [
          PopupMenuItem<String>(
            enabled: false,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final hex in labelColours)
                  InkWell(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    onTap: () {
                      setState(() {
                        _labelColour = hex;
                      });
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Color(0xFF000000 | parseHexColour(hex)!),
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.border),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ];
      },
      // PopupMenuButton's own InkWell can't be given a cursor, so the swatch asks for the hand.
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Color(0xFF000000 | parseHexColour(_labelColour)!),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border, width: 1.5),
          ),
        ),
      ),
    );
  }

  void _addLabel() {
    final text = _labelText.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _list('labels').add({'text': text, 'color': _labelColour});
      _labelText.clear();
    });
  }

  void _addCheck() {
    final text = _checklistText.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _list('checklist').add({'text': text, 'done': false});
      _checklistText.clear();
    });
  }

  /// One checklist item: its tick box, its text (struck through when done), and Remove.
  Widget _checkRow(UwuColors colors, int index) {
    final item = _list('checklist')[index] as Map;
    final done = item['done'] == true;
    Color textColour;
    TextDecoration? decoration;
    if (done) {
      textColour = colors.muted;
      decoration = TextDecoration.lineThrough;
    } else {
      textColour = colors.ink;
      decoration = null;
    }
    return Row(
      children: [
        Checkbox(
          value: done,
          onChanged: (value) {
            setState(() {
              item['done'] = value == true;
            });
          },
        ),
        Expanded(
          child: Text(
            '${item['text']}',
            style: TextStyle(color: textColour, decoration: decoration, fontSize: 14),
          ),
        ),
        MiniButton(
          icon: 'close',
          label: 'Remove',
          onPressed: () {
            setState(() {
              _list('checklist').removeAt(index);
            });
          },
        ),
      ],
    );
  }
}

/// Exports the open board to a file, its images inside it.
Future<void> exportActiveBoard() async {
  final board = AppState.instance.activeBoard;
  if (board == null) {
    return;
  }
  final result = await AppState.instance.exportBoard(board);
  final where = await saveFile(exportName(board), utf8.encode(result.json), mime: 'application/json');
  if (where == null) {
    return;
  }
  if (result.missing > 0) {
    String missingText;
    if (result.missing == 1) {
      missingText = '1 image';
    } else {
      missingText = '${result.missing} images';
    }
    AppNavigation.toast('Board exported, without $missingText that wouldn’t load');
  } else {
    AppNavigation.toast('Board exported');
  }
}

/// Imports a board file over the open board (or as a new one, with none open).
Future<void> importOverActiveBoard() async {
  final file = await pickJson();
  if (file == null) {
    return;
  }
  Object? json;
  try {
    json = jsonDecode(await file.readAsString());
  } catch (error) {
    AppNavigation.toast('Invalid JSON file', error: true);
    return;
  }
  await AppState.instance.importBoard(json, asNew: false);
}
