// The Theme window (the site's #themeModal): light, dark or time-based, and the brand colour.
// The app adds the look: Material You (the device's own colours, the default on Android 12+) or
// the UwU Apps look (the site's swatches and font). On the desktop, whose default is the UwU Apps
// look, the second look is the system's own glass instead of Material You: Fluent 2 on Windows,
// macOS Tahoe on a Mac, DDE and COSMIC's frosted glass on Linux. In the UwU Apps look there, the
// system's accent colour can stand in for the brand colour.
import 'package:flutter/material.dart';

import '../../app/env.dart';
import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/sheet.dart';

/// Set by the desktop layer: whether "Use system accent colour" is on, and how to change it.
bool Function()? desktopAccentGet;
void Function(bool on)? desktopAccentSet;

Future<void> openThemeSheet(BuildContext context) => AppSheet.show(context, id: 'theme', width: 460, builder: (context) => const ThemeSheet());

/// What native glass is on this computer, and whether the window's glass is the system's own.
String _glassNote(GlassStyle style, bool windowMaterial) {
  switch (style) {
    case GlassStyle.fluent:
      return 'Windows 11’s Fluent 2: Mica behind the window and Acrylic on what opens over it, in your accent colour and Segoe UI.'
          '${windowMaterial ? '' : ' This version of Windows has no Mica to give, so uwuBoard frosts its own.'}';
    case GlassStyle.tahoe:
      return 'The glass of macOS Tahoe: your desktop through the window, rounded glass and capsule buttons, in your accent colour and the system font.'
          '${windowMaterial ? '' : ' Your Mac isn’t showing the desktop through windows (Reduce transparency may be on), so uwuBoard frosts its own.'}';
    case GlassStyle.frosted:
      return 'The frosted glass of Deepin (DDE) and COSMIC, in your accent colour and the system font.'
          '${windowMaterial ? ' Your desktop blurs what’s behind the window.' : ' Your desktop doesn’t blur behind windows, so uwuBoard frosts its own.'}';
  }
}

class ThemeSheet extends StatelessWidget {
  const ThemeSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.I,
      builder: (context, _) {
        final t = ThemeController.I;
        final c = UwuColors.of(context);
        final material = t.isMaterial;
        final native = t.isNative;
        final glass = t.glassStyle;
        final accent = desktopAccentGet?.call() ?? false;

        Widget section(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            text,
            style: TextStyle(color: c.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        );

        Widget seg<T>(List<(T, String, String)> options, T value, ValueChanged<T> pick, {String key = ''}) => Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              for (final o in options)
                Expanded(
                  child: Semantics(
                    selected: o.$1 == value,
                    button: true,
                    child: InkWell(
                      mouseCursor: WidgetStateMouseCursor.clickable,
                      key: ValueKey('$key-${o.$1}'),
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => pick(o.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(color: o.$1 == value ? c.brandFill : null, borderRadius: BorderRadius.circular(9)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AppIcon(o.$2, size: 16, color: o.$1 == value ? c.onBrand : c.ink),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(o.$3, style: TextStyle(fontSize: 13, color: o.$1 == value ? c.onBrand : c.ink)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

        return SheetFrame(
          title: 'Theme',
          children: [
            section('Look'),
            seg<String>(
              [
                if (Env.desktop) (lookNative, 'monitor', glass.label) else (lookMaterial, 'palette', 'Material You'),
                (lookUwuApps, 'sun', 'UwU Apps'),
              ],
              t.look,
              t.setLook,
              key: 'look',
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                native
                    ? _glassNote(glass, t.windowMaterial)
                    : material
                    ? (t.hasDynamic
                          ? 'Colours and fonts from your device.'
                          : 'Material You’s colours and fonts. This device has no palette of its own to share, so it uses uwuBoard’s green.')
                    : 'uwuBoard’s own colours and font, as on the website.',
                style: TextStyle(color: c.muted, fontSize: 12.5),
              ),
            ),
            section('Mode'),
            seg<String>([('light', 'sun', 'Light'), ('dark', 'moon', 'Dark'), ('time', 'clock', 'Time-based')], t.modePreference, t.setMode, key: 'mode'),
            if (t.modePreference == 'time')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Following the clock. Currently ${t.mode}.', style: TextStyle(color: c.muted, fontSize: 12.5)),
              ),
            if (!material && !native) ...[
              if (Env.desktop && desktopAccentSet != null) ...[
                section('System accent'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Use system accent colour', style: TextStyle(color: c.ink, fontSize: 14)),
                  subtitle: Text(
                    'Your computer’s accent for highlights, with uwuBoard’s own surfaces and font.',
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                  value: accent,
                  onChanged: (v) => desktopAccentSet!(v),
                ),
              ],
              section('Brand colour'),
              Opacity(
                opacity: accent ? 0.45 : 1,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final ct in colorThemes)
                      Tooltip(
                        excludeFromSemantics: true,
                        message: ct.label,
                        child: Semantics(
                          label: ct.label,
                          selected: ct.id == t.colorThemeId,
                          button: true,
                          excludeSemantics: true,
                          child: InkWell(
                            mouseCursor: WidgetStateMouseCursor.clickable,
                            key: ValueKey('swatch-${ct.id}'),
                            customBorder: const CircleBorder(),
                            onTap: accent ? null : () => t.setColorTheme(ct.id),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: ct.color,
                                shape: BoxShape.circle,
                                border: Border.all(color: ct.id == t.colorThemeId ? c.brandInk : c.border, width: ct.id == t.colorThemeId ? 3 : 1),
                              ),
                              child: ct.id == t.colorThemeId ? const Center(child: AppIcon('check', size: 18, color: Color(0xFF121815))) : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
