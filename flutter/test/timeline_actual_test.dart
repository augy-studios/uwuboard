// A task started after its due date (work that's very late) draws on the Timeline: a bar from the
// due date on, a line at the due date, and a solid stripe for the work from its start to today, or
// to the day it was completed. Such a bar moves whole, every date with it.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwuboard/app/home.dart';
import 'package:uwuboard/app/state.dart';
import 'package:uwuboard/data/store.dart';
import 'package:uwuboard/data/timeline_logic.dart';
import 'package:uwuboard/theme/theme.dart';

void main() {
  String iso(int days) => isoOf(dayOf(todayIso()) + days);

  setUp(() {
    final board = {
      'id': 'b1',
      'name': 'Plan',
      'view': 'timeline',
      'columns': [
        {
          'id': 'p1',
          'name': 'Build',
          'cards': [
            {'id': 'late', 'title': 'Very late', 'start': iso(-4), 'due': iso(-12)},
            {'id': 'done', 'title': 'Started late, done', 'start': iso(-15), 'due': iso(-20), 'completed': iso(-8)},
            {'id': 'plain', 'title': 'On time', 'start': iso(-2), 'due': iso(3)},
          ],
        },
      ],
    };
    Store.memory({
      keyGuestBoards: jsonEncode([board]),
      'uwuboard.tour.welcome': 'done',
      'uwuboard.tour.pages': jsonEncode(['kanban', 'timeline', 'newboard', 'card']),
    });
    AppState.I.setGuest();
  });

  testWidgets('a task started after its due date shows the work as it went', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(look: lookUwuApps, brightness: Brightness.light, brand: colorThemes.first.color),
        home: const HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Two bars show the work as it went, each with its due date marked; the plain one doesn't.
    expect(find.byKey(const ValueKey('tl-actual')), findsNWidgets(2));
    expect(find.byKey(const ValueKey('tl-due-mark')), findsNWidgets(2));
    expect(find.text('Due ${fmtDay(dayOf(iso(-12)))} · ${fmtDay(dayOf(iso(-4)))} – now'), findsOneWidget);
    expect(find.textContaining('Very late (late)'), findsOneWidget);
    expect(find.textContaining('Started late, done (late)'), findsNothing);

    // The late bar runs from its due date to today.
    final bar = tester.getSize(find.byKey(const ValueKey('tl-bar-late')));
    final ppd = zooms['months']!.ppd;
    expect(bar.width, greaterThanOrEqualTo(13 * ppd));

    // Dragged, it moves whole: start and due by the same days, still a start after the due date.
    // From inside the bar itself: the middle of bar and title together can miss it.
    final at = tester.getTopLeft(find.byKey(const ValueKey('tl-bar-late'))) + const Offset(40, 20);
    await tester.dragFrom(at, Offset(6 * ppd, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final card = AppState.I.boards.first['columns'][0]['cards'][0] as Map<String, dynamic>;
    final moved = dayOf(card['start'] as String) - dayOf(iso(-4));
    expect(moved, greaterThan(0));
    expect(dayOf(card['due'] as String) - dayOf(iso(-12)), moved);
  });

  test('moved into the last column (Done), a card is completed today; moved out, it isn\'t', () {
    final board = AppState.I.boards.first;
    AppState.I.addColumn(board, 'Done');
    final done = '${(board['columns'] as List).last['id']}';
    final card = (board['columns'] as List).first['cards'][2] as Map<String, dynamic>;
    expect(card['completed'], isNull);

    AppState.I.moveCard(board, 'plain', done);
    expect(card['completed'], todayIso());
    AppState.I.moveCard(board, 'plain', 'p1');
    expect(card.containsKey('completed'), isFalse);

    // A date typed in the card window as it moves wins over today.
    card['completed'] = iso(-1);
    AppState.I.moveCard(board, 'plain', done, keepCompleted: true);
    expect(card['completed'], iso(-1));

    // Added straight into Done: done today.
    expect(AppState.I.addCard(board, done, 'Already done')!['completed'], todayIso());
  });
}
