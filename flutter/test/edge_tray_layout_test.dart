// On a phone the edge tray floats over the board instead of taking a strip of the screen: the
// board takes the whole width, open or closed, and scrolls far enough for its last column to come
// out from under the open tray. On a wider screen the board keeps its strip clear, as before.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwuboard/app/edge_tray.dart';
import 'package:uwuboard/app/home.dart';
import 'package:uwuboard/app/state.dart';
import 'package:uwuboard/data/store.dart';
import 'package:uwuboard/features/board/kanban_view.dart';
import 'package:uwuboard/theme/theme.dart';

void main() {
  setUp(() {
    final board = {
      'id': 'b1',
      'name': 'Plans',
      'columns': [
        for (final n in ['To Do', 'Doing', 'Done', 'Later'])
          {'id': n, 'name': n, 'cards': <Object>[]},
      ],
    };
    Store.memory({
      keyGuestBoards: jsonEncode([board]),
      'uwuboard.tour.welcome': 'done',
      'uwuboard.tour.pages': jsonEncode(['kanban', 'timeline', 'newboard', 'card']),
    });
    EdgeTray.open.value = true;
    AppState.I.setGuest();
  });

  Future<void> pumpHome(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(look: lookUwuApps, brightness: Brightness.light, brand: colorThemes.first.color),
        home: const HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  double boardWidth(WidgetTester tester) => tester.getSize(find.byType(KanbanView)).width;
  ScrollPosition columns(WidgetTester tester) =>
      tester.widget<SingleChildScrollView>(find.byKey(const ValueKey('columns'))).controller!.position;
  Future<void> toggleTray(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel(RegExp('^(Hide|Show) menu\$')));
    await tester.pumpAndSettle();
  }

  testWidgets('on a phone the board takes the whole width, open or closed', (tester) async {
    await pumpHome(tester, const Size(400, 800));
    expect(EdgeTray.open.value, isTrue);
    expect(boardWidth(tester), 400);
    final openEnd = columns(tester).maxScrollExtent;

    await toggleTray(tester);
    expect(EdgeTray.open.value, isFalse);
    expect(boardWidth(tester), 400);
    // Open, the board scrolls further by the tray's width, so its last column comes out from under it.
    expect(openEnd - columns(tester).maxScrollExtent, EdgeTray.openWidth);

    // The title runs up to the tab, closed, and stops short of the tray, open.
    expect(tester.getRect(find.text('Plans')).right, lessThan(400 - EdgeTray.tabWidth));
    await toggleTray(tester);
    expect(tester.getRect(find.text('Plans')).right, lessThan(400 - EdgeTray.openWidth));
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a wider screen the board keeps its strip clear for the tray', (tester) async {
    await pumpHome(tester, const Size(1000, 800));
    final open = boardWidth(tester);
    await toggleTray(tester);
    final closed = boardWidth(tester);
    expect(closed - open, 84 - 30);
    expect(tester.takeException(), isNull);
  });
}
