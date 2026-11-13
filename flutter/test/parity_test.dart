// The Dart ports against the site's own JavaScript (docs/flutter-android-app-spec.md §11):
// tool/expected.mjs runs main-site/js/timeline.js and sync.js on fixed inputs and writes their
// answers to test/fixtures/expected.json; these tests give the same inputs to
// lib/data/timeline_logic.dart and lib/data/sync_logic.dart and expect the same answers.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uwuboard/data/board.dart';
import 'package:uwuboard/data/sync_logic.dart';
import 'package:uwuboard/data/timeline_logic.dart';

void main() {
  final expected = jsonDecode(File('test/fixtures/expected.json').readAsStringSync()) as Map<String, dynamic>;
  final timeline = expected['timeline'] as Map<String, dynamic>;
  final sync = expected['sync'] as Map<String, dynamic>;

  Json card(String id, String title, [Json extra = const {}]) => {
        'id': id, 'title': title, 'description': '', 'labels': <dynamic>[], 'checklist': <dynamic>[], 'due': '', 'priority': '',
        'images': <dynamic>[], 'thumbnailId': null, 'updatedAt': 10, ...extra,
      };
  final spanCards = [
    card('a', 'Both', {'start': '2026-03-01', 'due': '2026-03-05'}),
    card('b', 'Due only', {'due': '2026-03-07'}),
    card('c', 'Start only', {'start': '2026-02-27'}),
    card('d', 'Backwards', {'start': '2026-03-09', 'due': '2026-03-02'}),
    card('e', 'Milestone', {'start': '2026-03-01', 'due': '2026-03-10', 'milestone': true}),
    card('f', 'None'),
    card('g', 'Bad dates', {'start': '2026-3-1', 'due': 'soon'}),
  ];
  Json board() => clone(<String, dynamic>{
        'id': 'b1', 'name': 'Plan', 'view': 'timeline',
        'columns': [
          {'id': 'p1', 'name': 'Design', 'cards': [spanCards[0], {...spanCards[1], 'dependsOn': ['a']}]},
          {'id': 'p2', 'name': 'Build', 'cards': [{...spanCards[2], 'dependsOn': ['b']}, spanCards[3], spanCards[4], spanCards[5]]},
        ],
      });

  group('Timeline, as main-site/js/timeline.js', () {
    test('spans', () {
      for (final e in timeline['spans'] as List) {
        final c = spanCards.firstWhere((k) => k['id'] == e['id']);
        final s = spanOf(c);
        final want = e['span'];
        expect(s == null ? null : {'start': s.start, 'end': s.end}, want, reason: '${e['id']}');
      }
    });

    test('clashes', () {
      final all = allCards(board()).toList();
      for (final e in timeline['clashes'] as List) {
        final pred = all.firstWhere((k) => k['id'] == e['pred']);
        final c = all.firstWhere((k) => k['id'] == e['card']);
        expect(clashes(pred, c), e['clash'], reason: '${e['pred']} → ${e['card']}');
      }
    });

    test('what waits for what', () {
      for (final e in timeline['waitingOn'] as List) {
        expect(waitingOn(board(), e['id'] as String).toList()..sort(), e['waiting']);
      }
    });

    test('a card gone is waited for by nobody', () {
      final b = board();
      ((b['columns'] as List)[0]['cards'] as List).removeAt(0);
      pruneDeps(b);
      final got = [for (final c in allCards(b)) {'id': c['id'], 'dependsOn': c['dependsOn']}];
      expect(got, timeline['pruned']);
    });
  });

  group('Sync, as main-site/js/sync.js', () {
    test('what comes from another device is checked field by field', () {
      expect(cleanBoards(sync['raw']), sync['cleaned']);
    });

    test('merging adds and keeps the newest, never removes', () {
      final merged = clone(Map<String, dynamic>.from(sync['dest'] as Map));
      final changes = mergeBoardInto(merged, clone(Map<String, dynamic>.from(sync['src'] as Map)));
      expect(changes, sync['changes']);
      expect(merged, sync['merged']);
    });

    test('whether a board would change anything', () {
      final src = Map<String, dynamic>.from(sync['src'] as Map);
      expect(wouldChange([clone(Map<String, dynamic>.from(sync['merged'] as Map))], src), sync['wouldChangeSame']);
      expect(wouldChange([], src), sync['wouldChangeNew']);
    });
  });

  group('The site and the app keep the same things', () {
    test('every storage key the site uses is one the app uses', () {
      final siteKeys = <String>{};
      final keyRe = RegExp(r'''['"`]((?:uwuboard[._][\w.]*)|kanbanflow_guest_boards)['"`]''');
      for (final f in Directory('../main-site').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.js') && !f.path.endsWith('.html')) continue;
        if (f.path.contains('${Platform.pathSeparator}api${Platform.pathSeparator}') || f.path.contains('node_modules')) continue;
        for (final m in keyRe.allMatches(f.readAsStringSync())) {
          siteKeys.add(m.group(1)!);
        }
      }
      // The pre-paint script builds its keys from a prefix; the avatar key was the site's own
      // cache, retired when images were hidden; the theme's legacy key is migrated (theme.dart).
      final dart = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).map((f) => f.readAsStringSync()).join('\n');
      final missing = siteKeys.where((k) => k != 'uwuboard' && k != 'uwuboard_avatar_' && !dart.contains("'$k'")).toList();
      expect(siteKeys, isNotEmpty);
      expect(missing, isEmpty, reason: 'Keys the site keeps that the app never reads: $missing');
    });
  });
}
