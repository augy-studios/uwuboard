// The desktop's title bar sits above the navigator: its tooltips need an overlay of their own,
// or showing one throws and the release build's grey error box fills the bar.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwuboard/app/env.dart';
import 'package:uwuboard/app/nav.dart';
import 'package:uwuboard/data/store.dart';
import 'package:uwuboard/desktop/chrome.dart';
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
}
