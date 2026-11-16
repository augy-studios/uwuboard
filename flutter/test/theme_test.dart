// The desktop's native glass (lib/theme/theme.dart): in place of Material You there, one per
// system, and readable whatever the system's accent colour.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwuboard/data/store.dart';
import 'package:uwuboard/theme/theme.dart';
import 'package:uwuboard/widgets/common.dart';
import 'package:uwuboard/widgets/glass.dart';

void main() {
  setUp(() {
    Store.memory();
    ThemeController.isDesktop = () => true;
    ThemeController.isAndroid = () => false;
  });

  test('each desktop has its own glass', () {
    expect(glassStyleFor(TargetPlatform.windows), GlassStyle.fluent);
    expect(glassStyleFor(TargetPlatform.macOS), GlassStyle.tahoe);
    expect(glassStyleFor(TargetPlatform.linux), GlassStyle.frosted);
    expect(GlassStyle.fluent.label, 'Fluent 2');
    expect(GlassStyle.tahoe.label, 'macOS Tahoe');
    expect(GlassStyle.frosted.material, 'Deepin (DDE) & COSMIC');
  });

  test('on the desktop, the second look is native glass, and Material You kept from before means it', () {
    final t = ThemeController.I;
    expect(t.look, lookUwuApps);
    t.setLook(lookNative);
    expect(t.look, lookNative);
    expect(t.isNative, isTrue);
    Store.I.put(keyLook, lookMaterial);
    expect(t.look, lookNative);
    t.setLook(lookUwuApps);
    expect(t.look, lookUwuApps);
  });

  test('on a phone, native glass kept from a desktop means Material You', () {
    ThemeController.isDesktop = () => false;
    Store.I.put(keyLook, lookNative);
    expect(ThemeController.I.look, lookMaterial);
  });

  group('readable in every glass, mode and accent', () {
    const accents = <Color?>[null, Color(0xFF0078D4), Color(0xFFFFCC00), Color(0xFF34C759), Color(0xFFFF2D55), Color(0xFF8E8E93), Color(0xFF63D0DF)];
    for (final style in GlassStyle.values) {
      for (final b in Brightness.values) {
        for (final accent in accents) {
          test('${style.name}, ${b.name}, ${accent ?? 'default accent'}', () {
            final c = glassColors(style, b, accent: accent);
            expect(c.native, style);
            final strong = Color.alphaBlend(c.surfaceStrong, c.bg);
            final soft = Color.alphaBlend(c.surface, c.bg);
            for (final on in [c.bg, strong, soft]) {
              expect(contrastRatio(c.ink, on), greaterThanOrEqualTo(4.5), reason: 'ink');
              expect(contrastRatio(c.muted, on), greaterThanOrEqualTo(4.5), reason: 'muted');
              expect(contrastRatio(c.border, on), greaterThanOrEqualTo(3), reason: 'border');
              expect(contrastRatio(c.error, on), greaterThanOrEqualTo(4.5), reason: 'error');
            }
            for (final on in [c.bg, strong]) {
              expect(contrastRatio(c.brandInk, on), greaterThanOrEqualTo(4.5), reason: 'accent words');
            }
            expect(contrastRatio(c.onBrand, c.brandFill), greaterThanOrEqualTo(4.5), reason: 'on accent fill');
            expect(contrastRatio(c.onBrand, c.brandFillStrong), greaterThanOrEqualTo(4.5), reason: 'on strong accent fill');
            expect(contrastRatio(onColor(c.brandInk), c.brandInk), greaterThanOrEqualTo(4.5), reason: 'accent button');
          });
        }
      }
    }
  });

  testWidgets('native glass: a see-through page, the system font, accent buttons, glass panels', (tester) async {
    final theme = buildTheme(
      look: lookNative,
      brightness: Brightness.light,
      brand: colorThemes.first.color,
      desktop: true,
      glassStyle: GlassStyle.fluent,
      accent: const Color(0xFF0078D4),
    );
    expect(theme.scaffoldBackgroundColor, Colors.transparent);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Segoe UI Variable Text');
    expect(theme.colorScheme.primary, theme.extension<UwuColors>()!.brandInk);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const GlassBackdrop(
          child: Scaffold(body: Center(child: GlassPanel(child: Text('Hello')))),
        ),
      ),
    );
    expect(find.text('Hello'), findsOneWidget);
    expect(find.byType(NativeGlass), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('the UwU Apps look and Material You draw no native glass', (tester) async {
    for (final look in [lookUwuApps, lookMaterial]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(look: look, brightness: Brightness.light, brand: colorThemes.first.color),
          home: const GlassBackdrop(
            child: Scaffold(body: Center(child: GlassPanel(child: Text('Hello')))),
          ),
        ),
      );
      expect(find.byType(NativeGlass), findsNothing);
    }
  });
}
