// The desktop's title bar sits above the navigator: its tooltips need an overlay of their own,
// or showing one throws and the release build's grey error box fills the bar.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwuboard/app/app.dart';
import 'package:uwuboard/app/env.dart';
import 'package:uwuboard/app/nav.dart';
import 'package:uwuboard/data/store.dart';
import 'package:uwuboard/desktop/chrome.dart';
import 'package:uwuboard/features/bug/bug_report.dart';
import 'package:uwuboard/theme/theme.dart';

void main() {
  setUpAll(() {
    Store.memory();
    Env.desktopOverride = true;
  });

  testWidgets('a title bar button shows its tooltip on hover', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: AppNav.navigatorKey,
        theme: buildTheme(look: lookUwuApps, brightness: Brightness.light, brand: colorThemes.first.color, desktop: true),
        builder: (context, child) => DesktopChrome(child: child!),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    await tester.pump();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byTooltip('Reload')));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('Reload'), findsOneWidget);
  });

  // 1.0.2 shipped a black window: the app's Stack (for the bug report's bar) sized itself by the
  // hidden bar, 0 wide, in the title bar's Column. The app has to fill the window under the bar.
  testWidgets('the app fills the window under the title bar, and the screenshot bar sits on it', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    desktopChrome = (context, child) => DesktopChrome(child: child);
    addTearDown(() => desktopChrome = null);
    await tester.pumpWidget(const UwuBoardApp());
    await tester.pump();

    final page = tester.getRect(find.byKey(AppNav.repaintKey));
    expect(page.width, 1400);
    expect(page.bottom, 900);
    expect(page.height, greaterThan(800));
    // And what's on it is drawn across the whole of it: the navigator's page is as wide.
    expect(tester.getSize(find.byType(Navigator).first).width, 1400);

    BugShot.shooting.value = true;
    addTearDown(() => BugShot.shooting.value = false);
    await tester.pump();
    final bar = tester.getRect(find.byType(BugShotBar));
    expect(bar.width, 1400);
    expect(bar.bottom, 900);
    expect(tester.takeException(), isNull);
  });
}
