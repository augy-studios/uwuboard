// Boards, columns and cards, as the site keeps them (main-site/script.js): plain JSON, so a
// board goes to the API, into the guest's storage, into an export file and across a sync
// exactly as the site's does, and anything a newer site adds to one survives a round trip.
//
//   board  { id, name, view: 'kanban'|'timeline', updatedAt, columns: [column] }
//   column { id, name, updatedAt, cards: [card] }
//   card   { id, title, description, labels: [{text,color}], checklist: [{text,done}], due,
//            priority, images: [{id,name, file|data|url}], thumbnailId, updatedAt,
//            start?, milestone?, dependsOn? }
import 'dart:math' as math;

typedef Json = Map<String, dynamic>;

final _random = math.Random();

/// The site's uid(): random base 36, then the time in base 36.
String uid() {
  const digits = '0123456789abcdefghijklmnopqrstuvwxyz';
  final randomPart = [for (var index = 0; index < 8; index = index + 1) digits[_random.nextInt(36)]].join();
  return randomPart + DateTime.now().millisecondsSinceEpoch.toRadixString(36);
}

/// When a card, a column or a board's name was last changed. Syncing with another device keeps
/// whichever copy of a thing on both was changed last.
T touch<T extends Json>(T item) {
  item['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
  return item;
}

/// What each type of board starts with: a kanban's columns, a timeline's waterfall phases.
const starting = {
  'kanban': ['To Do', 'In Progress', 'Done'],
  'timeline': ['Requirements', 'Design', 'Build', 'Test', 'Release'],
};

const priorities = ['', 'low', 'medium', 'high', 'urgent'];

Json newCard(String title) {
  return touch<Json>({
    'id': uid(),
    'title': title,
    'description': '',
    'labels': <dynamic>[],
    'checklist': <dynamic>[],
    'due': '',
    'priority': '',
    'images': <dynamic>[],
    'thumbnailId': null,
  });
}

Json newColumn(String name) {
  return touch<Json>({'id': uid(), 'name': name, 'cards': <dynamic>[]});
}

Json newBoard(String name, String type, List<String> columns) {
  final String view;
  if (type == 'timeline') {
    view = 'timeline';
  } else {
    view = 'kanban';
  }
  return touch<Json>({
    'id': uid(),
    'name': name,
    'view': view,
    'columns': <dynamic>[for (final columnName in columns) newColumn(columnName)],
  });
}

/* ---- reading a board ---- */

List<Json> columnsOf(Json board) {
  return _mapsInList(board['columns']);
}

List<Json> cardsOf(Json column) {
  return _mapsInList(column['cards']);
}

List<Json> imagesOf(Json card) {
  return _mapsInList(card['images']);
}

List<Json> labelsOf(Json card) {
  return _mapsInList(card['labels']);
}

List<Json> checklistOf(Json card) {
  return _mapsInList(card['checklist']);
}

/// The ids of the cards this card waits for (a timeline's `dependsOn`).
List<String> depsOf(Json card) {
  return [
    for (final dependency in _listOrEmpty(card['dependsOn']))
      if (dependency is String) dependency,
  ];
}

// The value as a list, or an empty list when there is none. (Anything else that isn't a list
// throws, as the cast always did.)
List<dynamic> _listOrEmpty(Object? value) {
  final list = value as List?;
  if (list == null) {
    return const [];
  }
  return list;
}

// Every map in a list, skipping anything that isn't one.
List<Json> _mapsInList(Object? value) {
  return [
    for (final item in _listOrEmpty(value))
      if (item is Map) _asJson(item),
  ];
}

// The same map where it already is one, so a change made through it lands in the board.
Json _asJson(Map map) {
  if (map is Json) {
    return map;
  } else {
    return Map<String, dynamic>.from(map);
  }
}

/// A deep copy, as the site's JSON.parse(JSON.stringify()).
T clone<T>(T value) {
  Object? copy(Object? original) {
    if (original is Map) {
      return <String, dynamic>{for (final entry in original.entries) '${entry.key}': copy(entry.value)};
    }
    if (original is List) {
      return <dynamic>[for (final item in original) copy(item)];
    }
    return original;
  }

  return copy(value) as T;
}

/// Boards as decoded from JSON, made of growable lists and string-keyed maps all the way down.
List<Json> boardsFromJson(Object? value) {
  return [
    for (final board in _listOrEmpty(value))
      if (board is Map) clone(_asJson(board)),
  ];
}

Iterable<Json> allCards(Json board) sync* {
  for (final column in columnsOf(board)) {
    yield* cardsOf(column);
  }
}

Json? findCard(Json board, String id) {
  for (final card in allCards(board)) {
    if (card['id'] == id) {
      return card;
    }
  }
  return null;
}

Json? findColumn(Json board, String id) {
  for (final column in columnsOf(board)) {
    if (column['id'] == id) {
      return column;
    }
  }
  return null;
}

Json? columnOfCard(Json board, String cardId) {
  for (final column in columnsOf(board)) {
    final hasCard = cardsOf(column).any((card) {
      return card['id'] == cardId;
    });
    if (hasCard) {
      return column;
    }
  }
  return null;
}

bool isTimelineBoard(Json board) {
  return board['view'] == 'timeline';
}

/// The image a card shows: the one starred, or its first.
Json? thumbOf(Json card) {
  final images = imagesOf(card);
  if (images.isEmpty) {
    return null;
  }
  for (final image in images) {
    if (image['id'] == card['thumbnailId']) {
      return image;
    }
  }
  return images.first;
}

/// How a card's due date reads beside now: 'overdue', 'soon' (under two days) or ''.
String dueClass(String due, DateTime now) {
  final dueDate = DateTime.tryParse(due);
  if (dueDate == null) {
    return '';
  }
  // The site's new Date('YYYY-MM-DD') is midnight UTC.
  final dueMidnight = DateTime.utc(dueDate.year, dueDate.month, dueDate.day);
  final daysLeft = dueMidnight.difference(now.toUtc()).inMilliseconds / 86400000;
  if (daysLeft < 0) {
    return 'overdue';
  } else if (daysLeft < 2) {
    return 'soon';
  } else {
    return '';
  }
}

/// Whether a label's colour wants white words on it (the site's isDark()).
bool isDarkHex(String hex) {
  final colour = parseHex(hex);
  if (colour == null) {
    return false;
  }
  final red = (colour >> 16) & 255;
  final green = (colour >> 8) & 255;
  final blue = colour & 255;
  return (red * 0.299 + green * 0.587 + blue * 0.114) < 140;
}

/// #rrggbb as 0xRRGGBB, or null.
int? parseHex(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) {
    return null;
  }
  return int.parse(hex.substring(1), radix: 16);
}

/// The file an export is saved as (the site's `${name}_kanban.json`).
String exportName(Json board) {
  return '${'${board['name']}'.replaceAll(RegExp(r'\s+'), '_')}_kanban.json';
}

/// Whether a file's JSON is a board (the site's importBoardFromJSON's test).
bool isBoardFile(Object? json) {
  return json is Map && _truthy(json['id']) && _truthy(json['name']) && json['columns'] is List;
}

// Whether JavaScript would count the value as true (not null, false, '' or 0).
bool _truthy(Object? value) {
  return value != null && value != false && value != '' && value != 0;
}

/// How many columns, cards and images, as the Sync window says under a board's name.
String boardSub(Json board) {
  final columns = columnsOf(board);
  final cards = columns.fold<int>(0, (total, column) {
    return total + cardsOf(column).length;
  });
  final images = columns.fold<int>(0, (total, column) {
    final imagesInColumn = cardsOf(column).fold<int>(0, (columnTotal, card) {
      return columnTotal + imagesOf(card).length;
    });
    return total + imagesInColumn;
  });
  final String columnsText;
  if (columns.length == 1) {
    columnsText = '1 column';
  } else {
    columnsText = '${columns.length} columns';
  }
  final String cardsText;
  if (cards == 1) {
    cardsText = '1 card';
  } else {
    cardsText = '$cards cards';
  }
  final String imagesText;
  if (images == 1) {
    imagesText = '1 image';
  } else {
    imagesText = '$images images';
  }
  return [
    columnsText,
    cardsText,
    if (images > 0) imagesText,
  ].join(' · ');
}
