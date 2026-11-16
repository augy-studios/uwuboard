// The sidebar beside the board folds and unfolds as the site's does (main-site/style.css,
// .sidebar): its width eased over 250 ms, what's in it switched at once and clipped to the width.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwuboard/app/env.dart';
import 'package:uwuboard/app/sidebar.dart';
import 'package:uwuboard/data/store.dart';
import 'package:uwuboard/theme/theme.dart';

void main() {
  setUpAll(() {
    Store.memory();
    Env.desktopOverride = true;
  });

  /// Shows the sidebar beside an empty page and returns a function that folds it (true) or
  /// unfolds it (false). With [still], animations are turned off as the system would.
  Future<void Function(bool)> pumpSidebar(WidgetTester tester, {bool still = false}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late StateSetter setSidebarState;
    var collapsed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(look: lookUwuApps, brightness: Brightness.light, brand: colorThemes.first.color, desktop: true),
        builder: (context, child) {
          return MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: still), child: child!);
        },
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setSidebarState = setState;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Sidebar(collapsed: collapsed), const Expanded(child: SizedBox())],
              );
            },
          ),
        ),
      ),
    );
    return (value) {
      setSidebarState(() {
        collapsed = value;
      });
    };
  }

  /// How wide the sidebar is drawn right now.
  double sidebarWidth(WidgetTester tester) {
    return tester.getSize(find.byKey(const ValueKey('sidebar'))).width;
  }

  testWidgets('folds to the rail and back, its width eased and what is in it switched at once', (tester) async {
    final fold = await pumpSidebar(tester);
    expect(sidebarWidth(tester), 300);
    expect(find.text('BOARDS'), findsOneWidget);

    fold(true);
    await tester.pump();
    // The panel's words go at once; the rail is there while the width is still the panel's.
    expect(find.text('BOARDS'), findsNothing);
    expect(sidebarWidth(tester), 300);
    await tester.pump(const Duration(milliseconds: 125));
    final halfwayWidth = sidebarWidth(tester);
    expect(halfwayWidth, greaterThan(Sidebar.railWidth));
    expect(halfwayWidth, lessThan(300));
    await tester.pump(const Duration(milliseconds: 200));
    expect(sidebarWidth(tester), Sidebar.railWidth);

    fold(false);
    await tester.pump();
    // The panel at once, uncovered as the sidebar widens.
    expect(find.text('BOARDS'), findsOneWidget);
    expect(sidebarWidth(tester), Sidebar.railWidth);
    await tester.pump(const Duration(milliseconds: 125));
    expect(sidebarWidth(tester), allOf(greaterThan(Sidebar.railWidth), lessThan(300)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(sidebarWidth(tester), 300);
    // Laid out whole while narrower, so nothing in it overflowed.
    expect(tester.takeException(), isNull);
  });

  testWidgets('snaps with animations turned off', (tester) async {
    final fold = await pumpSidebar(tester, still: true);
    fold(true);
    await tester.pump();
    await tester.pump();
    expect(sidebarWidth(tester), Sidebar.railWidth);
    expect(tester.takeException(), isNull);
  });
}
