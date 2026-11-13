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
  final r = [for (var i = 0; i < 8; i++) digits[_random.nextInt(36)]].join();
  return r + DateTime.now().millisecondsSinceEpoch.toRadixString(36);
}

/// When a card, a column or a board's name was last changed. Syncing with another device keeps
/// whichever copy of a thing on both was changed last.
T touch<T extends Json>(T obj) {
  obj['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
  return obj;
}

/// What each type of board starts with: a kanban's columns, a timeline's waterfall phases.
const starting = {
  'kanban': ['To Do', 'In Progress', 'Done'],
  'timeline': ['Requirements', 'Design', 'Build', 'Test', 'Release'],
};

const priorities = ['', 'low', 'medium', 'high', 'urgent'];

Json newCard(String title) => touch<Json>({
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

Json newColumn(String name) => touch<Json>({'id': uid(), 'name': name, 'cards': <dynamic>[]});

Json newBoard(String name, String type, List<String> columns) => touch<Json>({
  'id': uid(),
  'name': name,
  'view': type == 'timeline' ? 'timeline' : 'kanban',
  'columns': <dynamic>[for (final n in columns) newColumn(n)],
});

/* ---- reading a board ---- */

List<Json> columnsOf(Json board) => _maps(board['columns']);
List<Json> cardsOf(Json column) => _maps(column['cards']);
List<Json> imagesOf(Json card) => _maps(card['images']);
List<Json> labelsOf(Json card) => _maps(card['labels']);
List<Json> checklistOf(Json card) => _maps(card['checklist']);
List<String> depsOf(Json card) => [
  for (final d in (card['dependsOn'] as List?) ?? const [])
    if (d is String) d,
];

List<Json> _maps(Object? v) => [
  for (final e in (v as List?) ?? const [])
    if (e is Map) _json(e),
];

// The same map where it already is one, so a change made through it lands in the board.
Json _json(Map m) => m is Json ? m : Map<String, dynamic>.from(m);

/// A deep copy, as the site's JSON.parse(JSON.stringify()).
T clone<T>(T v) {
  Object? copy(Object? x) {
    if (x is Map) return <String, dynamic>{for (final e in x.entries) '${e.key}': copy(e.value)};
    if (x is List) return <dynamic>[for (final e in x) copy(e)];
    return x;
  }

  return copy(v) as T;
}

/// Boards as decoded from JSON, made of growable lists and string-keyed maps all the way down.
List<Json> boardsFromJson(Object? v) => [
  for (final b in (v as List?) ?? const [])
    if (b is Map) clone(_json(b)),
];

Iterable<Json> allCards(Json board) sync* {
  for (final col in columnsOf(board)) {
    yield* cardsOf(col);
  }
}

Json? findCard(Json board, String id) {
  for (final card in allCards(board)) {
    if (card['id'] == id) return card;
  }
  return null;
}

Json? findColumn(Json board, String id) {
  for (final col in columnsOf(board)) {
    if (col['id'] == id) return col;
  }
  return null;
}

Json? columnOfCard(Json board, String cardId) {
  for (final col in columnsOf(board)) {
    if (cardsOf(col).any((c) => c['id'] == cardId)) return col;
  }
  return null;
}

bool isTimelineBoard(Json board) => board['view'] == 'timeline';

/// The image a card shows: the one starred, or its first.
Json? thumbOf(Json card) {
  final images = imagesOf(card);
  if (images.isEmpty) return null;
  for (final i in images) {
    if (i['id'] == card['thumbnailId']) return i;
  }
  return images.first;
}

/// How a card's due date reads beside now: 'overdue', 'soon' (under two days) or ''.
String dueClass(String due, DateTime now) {
  final d = DateTime.tryParse(due);
  if (d == null) return '';
  // The site's new Date('YYYY-MM-DD') is midnight UTC.
  final at = DateTime.utc(d.year, d.month, d.day);
  final diff = at.difference(now.toUtc()).inMilliseconds / 86400000;
  return diff < 0 ? 'overdue' : (diff < 2 ? 'soon' : '');
}

/// Whether a label's colour wants white words on it (the site's isDark()).
bool isDarkHex(String hex) {
  final c = parseHex(hex);
  if (c == null) return false;
  final r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
  return (r * 0.299 + g * 0.587 + b * 0.114) < 140;
}

/// #rrggbb as 0xRRGGBB, or null.
int? parseHex(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return int.parse(hex.substring(1), radix: 16);
}

/// The file an export is saved as (the site's `${name}_kanban.json`).
String exportName(Json board) => '${'${board['name']}'.replaceAll(RegExp(r'\s+'), '_')}_kanban.json';

/// Whether a file's JSON is a board (the site's importBoardFromJSON's test).
bool isBoardFile(Object? json) => json is Map && _truthy(json['id']) && _truthy(json['name']) && json['columns'] is List;

bool _truthy(Object? v) => v != null && v != false && v != '' && v != 0;

/// How many columns, cards and images, as the Sync window says under a board's name.
String boardSub(Json board) {
  final cols = columnsOf(board);
  final cards = cols.fold<int>(0, (n, c) => n + cardsOf(c).length);
  final images = cols.fold<int>(0, (n, c) => n + cardsOf(c).fold<int>(0, (m, k) => m + imagesOf(k).length));
  return [
    cols.length == 1 ? '1 column' : '${cols.length} columns',
    cards == 1 ? '1 card' : '$cards cards',
    if (images > 0) images == 1 ? '1 image' : '$images images',
  ].join(' · ');
}
