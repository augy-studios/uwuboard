// On a phone a sheet's buttons stop above the system's navigation bar (Android 15 and later draw
// the app edge to edge, under the gesture pill or the three buttons), and with the keyboard up,
// which covers the bar, they sit on top of the keyboard with nothing extra in between.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwuboard/app/env.dart';
import 'package:uwuboard/theme/theme.dart';
import 'package:uwuboard/widgets/sheet.dart';

void main() {
  const navBar = 48.0, keyboard = 300.0;

  Future<void> openSheet(WidgetTester tester) async {
    Environment.desktopOverride = false;
    addTearDown(() {
      Environment.desktopOverride = null;
      AppSheet.open.value = const [];
    });
    tester.view.physicalSize = const Size(354, 792);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(look: lookUwuApps, brightness: Brightness.light, brand: colorThemes.first.color),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => AppSheet.show(
                  context,
                  id: 'test',
                  builder: (context) => SheetFrame(
                    title: 'New Board',
                    footer: [FilledButton(key: const ValueKey('create'), onPressed: () {}, child: const Text('Create'))],
                    children: const [Text('Board Name')],
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a sheet\'s buttons stop above the navigation bar', (tester) async {
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
    tester.view.padding = const FakeViewPadding(bottom: navBar);
    await openSheet(tester);
    expect(tester.getRect(find.byKey(const ValueKey('create'))).bottom, lessThanOrEqualTo(792 - navBar));
    expect(tester.takeException(), isNull);
  });

  testWidgets('with the keyboard up, the buttons sit on the keyboard', (tester) async {
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    await openSheet(tester);
    final bottom = tester.getRect(find.byKey(const ValueKey('create'))).bottom;
    expect(bottom, lessThanOrEqualTo(792 - keyboard));
    // Only the footer's own padding below the button: no navigation bar's worth on top of it.
    expect(792 - keyboard - bottom, lessThan(navBar));
    expect(tester.takeException(), isNull);
  });
}
