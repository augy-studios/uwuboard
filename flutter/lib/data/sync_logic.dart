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
const maxImageChars = 12 * 1024 * 1024;

final _idRe = RegExp(r'^[\w-]{1,64}$');
final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _colourRe = RegExp(r'^#[0-9a-f]{6}$', caseSensitive: false);
final dataUrlRe = RegExp(r'^data:image/(png|jpeg|webp|gif);base64,[A-Za-z0-9+/=]+$');

bool isId(Object? v) => v is String && _idRe.hasMatch(v);
String _text(Object? v, int max) => v is String ? (v.length > max ? v.substring(0, max) : v) : '';
List<dynamic> _list(Object? v, int max) => v is List ? (v.length > max ? v.sublist(0, max) : v) : const [];

/// A timestamp from another device: a finite number above zero, else 0. Kept as the number it
/// came as.
num stamp(Object? v) => v is num && v.isFinite && v > 0 ? v : 0;

// JS's String.prototype.trim() takes more kinds of space than Dart's trim() on some platforms;
// both take the ones a name could carry.
String _trim(String s) => s.trim();

/// A board as another device gets it in a list: each image by id and name, no bytes.
Json listBoard(Json board) {
  final b = clone(board);
  for (final col in columnsOf(b)) {
    for (final card in cardsOf(col)) {
      card['images'] = [
        for (final img in imagesOf(card)) {'id': img['id'], 'name': img['name'] ?? ''},
      ];
    }
  }
  return b;
}

Json? cleanCard(Object? raw) {
  if (raw is! Map || !isId(raw['id'])) return null;
  final images = <Json>[
    for (final img in _list(raw['images'], maxImages))
      if (img is Map && isId(img['id'])) {'id': img['id'], 'name': _text(img['name'], 200)},
  ];
  final title = _text(raw['title'], 500);
  final deps = raw['dependsOn'];
  final cleanDeps = deps is List && deps.isNotEmpty
      ? <String>{
          for (final d in deps)
            if (isId(d) && d != raw['id']) d as String,
        }.take(50).toList()
      : null;
  return {
    'id': raw['id'],
    'title': title.isEmpty ? 'Untitled' : title,
    'description': _text(raw['description'], 20000),
    'due': raw['due'] is String && _dateRe.hasMatch(raw['due'] as String) ? raw['due'] : '',
    'priority': priorities.contains(raw['priority']) ? raw['priority'] : '',
    'labels': <dynamic>[
      for (final l in _list(raw['labels'], 30))
        if (l is Map && l['text'] is String && _trim(l['text'] as String).isNotEmpty && l['color'] is String && _colourRe.hasMatch(l['color'] as String))
          {'text': _text(_trim(l['text'] as String), 60), 'color': l['color']},
    ],
    'checklist': <dynamic>[
      for (final c in _list(raw['checklist'], 300))
        if (c is Map && c['text'] is String && _trim(c['text'] as String).isNotEmpty) {'text': _text(c['text'], 500), 'done': c['done'] == true},
    ],
    'images': images,
    'thumbnailId': images.any((img) => img['id'] == raw['thumbnailId']) ? raw['thumbnailId'] : (images.isEmpty ? null : images.first['id']),
    // A timeline's: when it starts, whether it's a milestone, and the cards it waits for, by
    // id. Only there when set, as on the board they came from.
    if (raw['start'] is String && _dateRe.hasMatch(raw['start'] as String)) 'start': raw['start'],
    if (raw['milestone'] == true) 'milestone': true,
    'dependsOn': ?cleanDeps,
    'updatedAt': stamp(raw['updatedAt']),
  };
}

/// Boards from the other device, checked field by field. They're input from another machine,
/// so anything malformed is dropped rather than stored, and duplicates go too.
List<Json>? cleanBoards(Object? raw) {
  if (raw is! List) return null;
  final seen = <String>{};
  bool once(String key) => seen.add(key);
  final out = <Json>[];
  for (final b in _list(raw, maxBoards)) {
    if (b is! Map || !isId(b['id']) || b['name'] is! String || _trim(b['name'] as String).isEmpty) continue;
    if (!once('board:${b['id']}')) continue;
    final cols = <dynamic>[];
    for (final c in _list(b['columns'], maxColumns)) {
      if (c is! Map || !isId(c['id']) || c['name'] is! String) continue;
      if (!once('col:${b['id']}/${c['id']}')) continue;
      final name = _text(_trim(c['name'] as String), 120);
      final cards = <dynamic>[];
      for (final k in _list(c['cards'], maxCards)) {
        final card = cleanCard(k);
        if (card != null && once('card:${b['id']}/${card['id']}')) cards.add(card);
      }
      cols.add(<String, dynamic>{'id': c['id'], 'name': name.isEmpty ? 'Column' : name, 'updatedAt': stamp(c['updatedAt']), 'cards': cards});
    }
    out.add({
      'id': b['id'],
      'name': _text(_trim(b['name'] as String), 120),
      // Shown as columns or as a timeline; a board from before there was a choice is columns.
      'view': b['view'] == 'timeline' ? 'timeline' : 'kanban',
      'updatedAt': stamp(b['updatedAt']),
      'columns': cols,
    });
  }
  return out;
}

/// What a card is, for telling whether two copies differ: everything but when it was stamped,
/// and its images by id.
String cardSig(Json c) => jsonEncode([
  c['title'],
  c['description'] ?? '',
  c['due'] ?? '',
  c['priority'] ?? '',
  [
    for (final l in labelsOf(c)) [l['text'], l['color']],
  ],
  [
    for (final k in checklistOf(c)) [k['text'], k['done'] == true],
  ],
  [for (final img in imagesOf(c)) img['id']],
  c['thumbnailId'],
  c['start'] ?? '',
  c['milestone'] == true,
  [...depsOf(c)]..sort(),
]);

/// Merges `src` into `dest` in place and says how many things that changed. Adds what `dest`
/// hasn't got; for what both have, the copy changed last wins. Never removes anything.
int mergeBoardInto(Json dest, Json src) {
  var changes = 0;
  if (stamp(src['updatedAt']) > stamp(dest['updatedAt'])) {
    if (src['name'] != dest['name']) {
      dest['name'] = src['name'];
      changes++;
    }
    // How it's shown goes with the name: whichever was changed last.
    if ((src['view'] ?? 'kanban') != (dest['view'] ?? 'kanban')) {
      dest['view'] = src['view'];
      changes++;
    }
    dest['updatedAt'] = src['updatedAt'];
  }

  final destCols = (dest['columns'] ??= <dynamic>[]) as List;
  final cols = <Object?, Json>{for (final c in columnsOf(dest)) c['id']: c};
  for (final sc in columnsOf(src)) {
    final dc = cols[sc['id']];
    if (dc == null) {
      final added = <String, dynamic>{'id': sc['id'], 'name': sc['name'], 'updatedAt': stamp(sc['updatedAt']), 'cards': <dynamic>[]};
      destCols.add(added);
      cols[sc['id']] = added;
      changes++;
    } else if (stamp(sc['updatedAt']) > stamp(dc['updatedAt'])) {
      if (sc['name'] != dc['name']) {
        dc['name'] = sc['name'];
        changes++;
      }
      dc['updatedAt'] = sc['updatedAt'];
    }
  }

  // Where each of dest's cards is now.
  final where = <Object?, Json>{};
  for (final col in columnsOf(dest)) {
    for (final card in cardsOf(col)) {
      where[card['id']] = col;
    }
  }

  for (final sc in columnsOf(src)) {
    final into = cols[sc['id']]!;
    final intoCards = (into['cards'] ??= <dynamic>[]) as List;
    for (final card in cardsOf(sc)) {
      final at = where[card['id']];
      if (at == null) {
        intoCards.add(clone(card));
        where[card['id']] = into;
        changes++;
        continue;
      }
      final atCards = at['cards'] as List;
      final i = atCards.indexWhere((c) => c is Map && c['id'] == card['id']);
      final mine = Map<String, dynamic>.from(atCards[i] as Map);
      if (stamp(card['updatedAt']) <= stamp(mine['updatedAt'])) continue;
      if (identical(at, into) && cardSig(mine) == cardSig(card)) {
        (atCards[i] as Map)['updatedAt'] = card['updatedAt'];
        continue;
      }
      // Its own images come along by id; the caller fills in the ones this device has.
      final copy = clone(card);
      if (identical(at, into)) {
        atCards[i] = copy;
      } else {
        atCards.removeAt(i);
        intoCards.add(copy);
        where[card['id']] = into;
      }
      changes++;
    }
  }
  return changes;
}

/// Whether merging `src` into the boards `into` would change anything there.
bool wouldChange(List<Json> into, Json src) {
  for (final b in into) {
    if (b['id'] == src['id']) return mergeBoardInto(clone(b), src) > 0;
  }
  return true;
}
