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
    ThemeController.isDesktop = () {
      return true;
    };
    ThemeController.isAndroid = () {
      return false;
    };
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
    final themeController = ThemeController.I;
    expect(themeController.look, lookUwuApps);
    themeController.setLook(lookNative);
    expect(themeController.look, lookNative);
    expect(themeController.isNative, isTrue);
    Store.I.put(keyLook, lookMaterial);
    expect(themeController.look, lookNative);
    themeController.setLook(lookUwuApps);
    expect(themeController.look, lookUwuApps);
  });

  test('on a phone, native glass kept from a desktop means Material You', () {
    ThemeController.isDesktop = () {
      return false;
    };
    Store.I.put(keyLook, lookNative);
    expect(ThemeController.I.look, lookMaterial);
  });

  // One test for every combination of glass style, light/dark mode and accent colour (null is the
  // default accent): each text and border colour must stand out enough from what it's drawn on.
  group('readable in every glass, mode and accent', () {
    const accents = <Color?>[null, Color(0xFF0078D4), Color(0xFFFFCC00), Color(0xFF34C759), Color(0xFFFF2D55), Color(0xFF8E8E93), Color(0xFF63D0DF)];
    for (final style in GlassStyle.values) {
      for (final brightness in Brightness.values) {
        for (final accent in accents) {
          String accentLabel;
          if (accent == null) {
            accentLabel = 'default accent';
          } else {
            accentLabel = '$accent';
          }
          test('${style.name}, ${brightness.name}, $accentLabel', () {
            final colors = glassColors(style, brightness, accent: accent);
            expect(colors.native, style);
            final strong = Color.alphaBlend(colors.surfaceStrong, colors.bg);
            final soft = Color.alphaBlend(colors.surface, colors.bg);
            for (final background in [colors.bg, strong, soft]) {
              expect(contrastRatio(colors.ink, background), greaterThanOrEqualTo(4.5), reason: 'ink');
              expect(contrastRatio(colors.muted, background), greaterThanOrEqualTo(4.5), reason: 'muted');
              expect(contrastRatio(colors.border, background), greaterThanOrEqualTo(3), reason: 'border');
              expect(contrastRatio(colors.error, background), greaterThanOrEqualTo(4.5), reason: 'error');
            }
            for (final background in [colors.bg, strong]) {
              expect(contrastRatio(colors.brandInk, background), greaterThanOrEqualTo(4.5), reason: 'accent words');
            }
            expect(contrastRatio(colors.onBrand, colors.brandFill), greaterThanOrEqualTo(4.5), reason: 'on accent fill');
            expect(contrastRatio(colors.onBrand, colors.brandFillStrong), greaterThanOrEqualTo(4.5), reason: 'on strong accent fill');
            expect(contrastRatio(onColor(colors.brandInk), colors.brandInk), greaterThanOrEqualTo(4.5), reason: 'accent button');
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
    final bodyMedium = theme.textTheme.bodyMedium;
    String? bodyFontFamily;
    if (bodyMedium == null) {
      bodyFontFamily = null;
    } else {
      bodyFontFamily = bodyMedium.fontFamily;
    }
    expect(bodyFontFamily, 'Segoe UI Variable Text');
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
