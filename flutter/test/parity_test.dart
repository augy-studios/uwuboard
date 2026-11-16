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

  /// Makes a card with every field the site gives a new card, plus whatever is in [extra].
  Json card(String id, String title, [Json extra = const {}]) {
    return {
      'id': id, 'title': title, 'description': '', 'labels': <dynamic>[], 'checklist': <dynamic>[], 'due': '', 'priority': '',
      'images': <dynamic>[], 'thumbnailId': null, 'updatedAt': 10, ...extra,
    };
  }

  final spanCards = [
    card('a', 'Both', {'start': '2026-03-01', 'due': '2026-03-05'}),
    card('b', 'Due only', {'due': '2026-03-07'}),
    card('c', 'Start only', {'start': '2026-02-27'}),
    card('d', 'Backwards', {'start': '2026-03-09', 'due': '2026-03-02'}),
    card('e', 'Milestone', {'start': '2026-03-01', 'due': '2026-03-10', 'milestone': true}),
    card('f', 'None'),
    card('g', 'Bad dates', {'start': '2026-3-1', 'due': 'soon'}),
  ];

  /// A fresh copy of a two-column board holding the cards above, where some wait for others.
  Json board() {
    return clone(<String, dynamic>{
      'id': 'b1', 'name': 'Plan', 'view': 'timeline',
      'columns': [
        {'id': 'p1', 'name': 'Design', 'cards': [spanCards[0], {...spanCards[1], 'dependsOn': ['a']}]},
        {'id': 'p2', 'name': 'Build', 'cards': [{...spanCards[2], 'dependsOn': ['b']}, spanCards[3], spanCards[4], spanCards[5]]},
      ],
    });
  }

  group('Timeline, as main-site/js/timeline.js', () {
    test('spans', () {
      for (final entry in timeline['spans'] as List) {
        final spanCard = spanCards.firstWhere((candidate) {
          return candidate['id'] == entry['id'];
        });
        final span = spanOf(spanCard);
        final want = entry['span'];
        // No span is compared as null; a span as a map of its start and end.
        Object? actualSpan;
        if (span == null) {
          actualSpan = null;
        } else {
          actualSpan = {'start': span.start, 'end': span.end};
        }
        expect(actualSpan, want, reason: '${entry['id']}');
      }
    });

    test('clashes', () {
      final everyCard = allCards(board()).toList();
      for (final entry in timeline['clashes'] as List) {
        final predecessor = everyCard.firstWhere((candidate) {
          return candidate['id'] == entry['pred'];
        });
        final dependentCard = everyCard.firstWhere((candidate) {
          return candidate['id'] == entry['card'];
        });
        expect(clashes(predecessor, dependentCard), entry['clash'], reason: '${entry['pred']} → ${entry['card']}');
      }
    });

    test('what waits for what', () {
      for (final entry in timeline['waitingOn'] as List) {
        final waiting = waitingOn(board(), entry['id'] as String).toList();
        waiting.sort();
        expect(waiting, entry['waiting']);
      }
    });

    test('a card gone is waited for by nobody', () {
      final prunedBoard = board();
      // Take away the first card of the first column, then drop the links to it.
      ((prunedBoard['columns'] as List)[0]['cards'] as List).removeAt(0);
      pruneDeps(prunedBoard);
      final got = [
        for (final remainingCard in allCards(prunedBoard)) {'id': remainingCard['id'], 'dependsOn': remainingCard['dependsOn']},
      ];
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
      final sourceBoard = Map<String, dynamic>.from(sync['src'] as Map);
      expect(wouldChange([clone(Map<String, dynamic>.from(sync['merged'] as Map))], sourceBoard), sync['wouldChangeSame']);
      expect(wouldChange([], sourceBoard), sync['wouldChangeNew']);
    });
  });

  group('The site and the app keep the same things', () {
    test('every storage key the site uses is one the app uses', () {
      final siteKeys = <String>{};
      final keyPattern = RegExp(r'''['"`]((?:uwuboard[._][\w.]*)|kanbanflow_guest_boards)['"`]''');
      // Collect every storage key named in the site's own scripts and pages (not its server code).
      for (final file in Directory('../main-site').listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.js') && !file.path.endsWith('.html')) {
          continue;
        }
        if (file.path.contains('${Platform.pathSeparator}api${Platform.pathSeparator}') || file.path.contains('node_modules')) {
          continue;
        }
        for (final match in keyPattern.allMatches(file.readAsStringSync())) {
          siteKeys.add(match.group(1)!);
        }
      }
      // The pre-paint script builds its keys from a prefix; the avatar key was the site's own
      // cache, retired when images were hidden; the theme's legacy key is migrated (theme.dart).
      final dartSource = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) {
            return file.path.endsWith('.dart');
          })
          .map((file) {
            return file.readAsStringSync();
          })
          .join('\n');
      final missing = siteKeys.where((key) {
        return key != 'uwuboard' && key != 'uwuboard_avatar_' && !dartSource.contains("'$key'");
      }).toList();
      expect(siteKeys, isNotEmpty);
      expect(missing, isEmpty, reason: 'Keys the site keeps that the app never reads: $missing');
    });
  });
}
