// What device sync does to boards, ported from main-site/js/sync.js: checking what another
// device sent field by field, and merging it in. Copying merges and never removes: a board this
// device hasn't got is added, and for one it has, missing columns and cards are added and a
// card on both keeps whichever copy was edited last. test/sync_logic_test.dart checks it
// against the site's own answers (tool/expected.mjs).
import 'dart:convert';

import 'board.dart';

// Caps on what's taken from another device, generous enough that nobody meets them.
const maxBoards = 200;
const maxColumns = 60;
const maxCards = 2000;
const maxImages = 40;

/// An image's chunks: a data URL split into pieces under the 16 KB PeerJS would split again.
const chunkSize = 12000;
const maxImageCharacters = 12 * 1024 * 1024;

final _identifierPattern = RegExp(r'^[\w-]{1,64}$');
final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _colourPattern = RegExp(r'^#[0-9a-f]{6}$', caseSensitive: false);
final dataUrlPattern = RegExp(r'^data:image/(png|jpeg|webp|gif);base64,[A-Za-z0-9+/=]+$');

bool isId(Object? value) {
  return value is String && _identifierPattern.hasMatch(value);
}

// The value if it's a string, cut to `maximumLength` characters; anything else is ''.
String _cappedText(Object? value, int maximumLength) {
  if (value is String) {
    if (value.length > maximumLength) {
      return value.substring(0, maximumLength);
    } else {
      return value;
    }
  } else {
    return '';
  }
}

// The value if it's a list, cut to `maximumLength` items; anything else is an empty list.
List<dynamic> _cappedList(Object? value, int maximumLength) {
  if (value is List) {
    if (value.length > maximumLength) {
      return value.sublist(0, maximumLength);
    } else {
      return value;
    }
  } else {
    return const [];
  }
}

// The value, or `fallback` when the value is null (JavaScript's `value ?? fallback`).
dynamic _withDefault(dynamic value, dynamic fallback) {
  if (value == null) {
    return fallback;
  }
  return value;
}

/// A timestamp from another device: a finite number above zero, else 0. Kept as the number it
/// came as.
num stamp(Object? value) {
  if (value is num && value.isFinite && value > 0) {
    return value;
  } else {
    return 0;
  }
}

// JS's String.prototype.trim() takes more kinds of space than Dart's trim() on some platforms;
// both take the ones a name could carry.
String _trim(String text) {
  return text.trim();
}

/// A board as another device gets it in a list: each image by id and name, no bytes.
Json listBoard(Json board) {
  final boardCopy = clone(board);
  for (final column in columnsOf(boardCopy)) {
    for (final card in cardsOf(column)) {
      card['images'] = [
        for (final image in imagesOf(card)) {'id': image['id'], 'name': _withDefault(image['name'], '')},
      ];
    }
  }
  return boardCopy;
}

/// One card from another device, checked field by field: only the fields a card has, each cut
/// to a sensible size and of the right kind. Null when it isn't a card at all.
Json? cleanCard(Object? raw) {
  if (raw is! Map || !isId(raw['id'])) {
    return null;
  }
  final images = <Json>[
    for (final image in _cappedList(raw['images'], maxImages))
      if (image is Map && isId(image['id'])) {'id': image['id'], 'name': _cappedText(image['name'], 200)},
  ];
  final title = _cappedText(raw['title'], 500);
  final dependsOn = raw['dependsOn'];
  final List<String>? cleanDependsOn;
  if (dependsOn is List && dependsOn.isNotEmpty) {
    cleanDependsOn = <String>{
      for (final dependency in dependsOn)
        if (isId(dependency) && dependency != raw['id']) dependency as String,
    }.take(50).toList();
  } else {
    cleanDependsOn = null;
  }
  final String cleanTitle;
  if (title.isEmpty) {
    cleanTitle = 'Untitled';
  } else {
    cleanTitle = title;
  }
  final Object? due;
  if (raw['due'] is String && _datePattern.hasMatch(raw['due'] as String)) {
    due = raw['due'];
  } else {
    due = '';
  }
  final Object? priority;
  if (priorities.contains(raw['priority'])) {
    priority = raw['priority'];
  } else {
    priority = '';
  }
  final hasThumbnail = images.any((image) {
    return image['id'] == raw['thumbnailId'];
  });
  final Object? thumbnailId;
  if (hasThumbnail) {
    thumbnailId = raw['thumbnailId'];
  } else if (images.isEmpty) {
    thumbnailId = null;
  } else {
    thumbnailId = images.first['id'];
  }
  return {
    'id': raw['id'],
    'title': cleanTitle,
    'description': _cappedText(raw['description'], 20000),
    'due': due,
    'priority': priority,
    'labels': <dynamic>[
      for (final label in _cappedList(raw['labels'], 30))
        if (label is Map && label['text'] is String && _trim(label['text'] as String).isNotEmpty && label['color'] is String && _colourPattern.hasMatch(label['color'] as String))
          {'text': _cappedText(_trim(label['text'] as String), 60), 'color': label['color']},
    ],
    'checklist': <dynamic>[
      for (final item in _cappedList(raw['checklist'], 300))
        if (item is Map && item['text'] is String && _trim(item['text'] as String).isNotEmpty) {'text': _cappedText(item['text'], 500), 'done': item['done'] == true},
    ],
    'images': images,
    'thumbnailId': thumbnailId,
    // A timeline's: when it starts, whether it's a milestone, when it was completed, and the
    // cards it waits for, by id. Only there when set, as on the board they came from.
    if (raw['start'] is String && _datePattern.hasMatch(raw['start'] as String)) 'start': raw['start'],
    if (raw['milestone'] == true) 'milestone': true,
    if (raw['completed'] is String && _datePattern.hasMatch(raw['completed'] as String)) 'completed': raw['completed'],
    if (cleanDependsOn != null) 'dependsOn': cleanDependsOn,
    'updatedAt': stamp(raw['updatedAt']),
  };
}

/// Boards from the other device, checked field by field. They're input from another machine,
/// so anything malformed is dropped rather than stored, and duplicates go too.
List<Json>? cleanBoards(Object? raw) {
  if (raw is! List) {
    return null;
  }
  final seen = <String>{};
  // True the first time a key is seen, false every time after.
  bool once(String key) {
    return seen.add(key);
  }

  final cleaned = <Json>[];
  for (final board in _cappedList(raw, maxBoards)) {
    if (board is! Map || !isId(board['id']) || board['name'] is! String || _trim(board['name'] as String).isEmpty) {
      continue;
    }
    if (!once('board:${board['id']}')) {
      continue;
    }
    final columns = <dynamic>[];
    for (final column in _cappedList(board['columns'], maxColumns)) {
      if (column is! Map || !isId(column['id']) || column['name'] is! String) {
        continue;
      }
      if (!once('col:${board['id']}/${column['id']}')) {
        continue;
      }
      final name = _cappedText(_trim(column['name'] as String), 120);
      final cards = <dynamic>[];
      for (final rawCard in _cappedList(column['cards'], maxCards)) {
        final card = cleanCard(rawCard);
        if (card != null && once('card:${board['id']}/${card['id']}')) {
          cards.add(card);
        }
      }
      final String columnName;
      if (name.isEmpty) {
        columnName = 'Column';
      } else {
        columnName = name;
      }
      columns.add(<String, dynamic>{'id': column['id'], 'name': columnName, 'updatedAt': stamp(column['updatedAt']), 'cards': cards});
    }
    final boardName = _cappedText(_trim(board['name'] as String), 120);
    // Shown as columns or as a timeline; a board from before there was a choice is columns.
    final String view;
    if (board['view'] == 'timeline') {
      view = 'timeline';
    } else {
      view = 'kanban';
    }
    cleaned.add({
      'id': board['id'],
      'name': boardName,
      'view': view,
      'updatedAt': stamp(board['updatedAt']),
      'columns': columns,
    });
  }
  return cleaned;
}

/// What a card is, for telling whether two copies differ: everything but when it was stamped,
/// and its images by id.
String cardSignature(Json card) {
  final sortedDependsOn = [...dependenciesOf(card)];
  sortedDependsOn.sort();
  return jsonEncode([
    card['title'],
    _withDefault(card['description'], ''),
    _withDefault(card['due'], ''),
    _withDefault(card['priority'], ''),
    [
      for (final label in labelsOf(card)) [label['text'], label['color']],
    ],
    [
      for (final item in checklistOf(card)) [item['text'], item['done'] == true],
    ],
    [for (final image in imagesOf(card)) image['id']],
    card['thumbnailId'],
    _withDefault(card['start'], ''),
    card['milestone'] == true,
    sortedDependsOn,
    _withDefault(card['completed'], ''),
  ]);
}

/// Merges `source` into `destination` in place and says how many things that changed. Adds
/// what `destination` hasn't got; for what both have, the copy changed last wins. Never removes
/// anything.
int mergeBoardInto(Json destination, Json source) {
  var changes = 0;
  // The board's own name and view.
  if (stamp(source['updatedAt']) > stamp(destination['updatedAt'])) {
    if (source['name'] != destination['name']) {
      destination['name'] = source['name'];
      changes = changes + 1;
    }
    // How it's shown goes with the name: whichever was changed last.
    if (_withDefault(source['view'], 'kanban') != _withDefault(destination['view'], 'kanban')) {
      destination['view'] = source['view'];
      changes = changes + 1;
    }
    destination['updatedAt'] = source['updatedAt'];
  }

  // The columns: new ones added (empty for now), and renamed ones renamed.
  if (destination['columns'] == null) {
    destination['columns'] = <dynamic>[];
  }
  final destinationColumns = destination['columns'] as List;
  final columnsById = <Object?, Json>{for (final column in columnsOf(destination)) column['id']: column};
  for (final sourceColumn in columnsOf(source)) {
    final destinationColumn = columnsById[sourceColumn['id']];
    if (destinationColumn == null) {
      final added = <String, dynamic>{'id': sourceColumn['id'], 'name': sourceColumn['name'], 'updatedAt': stamp(sourceColumn['updatedAt']), 'cards': <dynamic>[]};
      destinationColumns.add(added);
      columnsById[sourceColumn['id']] = added;
      changes = changes + 1;
    } else if (stamp(sourceColumn['updatedAt']) > stamp(destinationColumn['updatedAt'])) {
      if (sourceColumn['name'] != destinationColumn['name']) {
        destinationColumn['name'] = sourceColumn['name'];
        changes = changes + 1;
      }
      destinationColumn['updatedAt'] = sourceColumn['updatedAt'];
    }
  }

  // Where each of destination's cards is now.
  final columnOfCardId = <Object?, Json>{};
  for (final column in columnsOf(destination)) {
    for (final card in cardsOf(column)) {
      columnOfCardId[card['id']] = column;
    }
  }

  // The cards: new ones added, and for one on both, the newer copy kept (moved to the column
  // the other device has it in).
  for (final sourceColumn in columnsOf(source)) {
    final targetColumn = columnsById[sourceColumn['id']]!;
    if (targetColumn['cards'] == null) {
      targetColumn['cards'] = <dynamic>[];
    }
    final targetCards = targetColumn['cards'] as List;
    for (final card in cardsOf(sourceColumn)) {
      final currentColumn = columnOfCardId[card['id']];
      if (currentColumn == null) {
        targetCards.add(clone(card));
        columnOfCardId[card['id']] = targetColumn;
        changes = changes + 1;
        continue;
      }
      final currentCards = currentColumn['cards'] as List;
      final cardIndex = currentCards.indexWhere((item) {
        return item is Map && item['id'] == card['id'];
      });
      final ownCard = Map<String, dynamic>.from(currentCards[cardIndex] as Map);
      if (stamp(card['updatedAt']) <= stamp(ownCard['updatedAt'])) {
        continue;
      }
      if (identical(currentColumn, targetColumn) && cardSignature(ownCard) == cardSignature(card)) {
        (currentCards[cardIndex] as Map)['updatedAt'] = card['updatedAt'];
        continue;
      }
      // Its own images come along by id; the caller fills in the ones this device has.
      final copy = clone(card);
      if (identical(currentColumn, targetColumn)) {
        currentCards[cardIndex] = copy;
      } else {
        currentCards.removeAt(cardIndex);
        targetCards.add(copy);
        columnOfCardId[card['id']] = targetColumn;
      }
      changes = changes + 1;
    }
  }
  return changes;
}

/// Whether merging `source` into the boards `into` would change anything there.
bool wouldChange(List<Json> into, Json source) {
  for (final board in into) {
    if (board['id'] == source['id']) {
      return mergeBoardInto(clone(board), source) > 0;
    }
  }
  return true;
}
