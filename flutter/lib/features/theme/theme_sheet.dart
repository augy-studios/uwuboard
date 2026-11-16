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

/// Opens the Theme window.
Future<void> openThemeSheet(BuildContext context) {
  return AppSheet.show(
    context,
    id: 'theme',
    width: 460,
    builder: (context) {
      return const ThemeSheet();
    },
  );
}

/// What native glass is on this computer, and whether the window's glass is the system's own.
String _glassNote(GlassStyle style, bool windowMaterial) {
  switch (style) {
    case GlassStyle.fluent:
      String fluentExtra;
      if (windowMaterial) {
        fluentExtra = '';
      } else {
        fluentExtra = ' This version of Windows has no Mica to give, so uwuBoard frosts its own.';
      }
      return 'Windows 11’s Fluent 2: Mica behind the window and Acrylic on what opens over it, in your accent colour and Segoe UI.'
          '$fluentExtra';
    case GlassStyle.tahoe:
      String tahoeExtra;
      if (windowMaterial) {
        tahoeExtra = '';
      } else {
        tahoeExtra = ' Your Mac isn’t showing the desktop through windows (Reduce transparency may be on), so uwuBoard frosts its own.';
      }
      return 'The glass of macOS Tahoe: your desktop through the window, rounded glass and capsule buttons, in your accent colour and the system font.'
          '$tahoeExtra';
    case GlassStyle.frosted:
      String frostedExtra;
      if (windowMaterial) {
        frostedExtra = ' Your desktop blurs what’s behind the window.';
      } else {
        frostedExtra = ' Your desktop doesn’t blur behind windows, so uwuBoard frosts its own.';
      }
      return 'The frosted glass of Deepin (DDE) and COSMIC, in your accent colour and the system font.'
          '$frostedExtra';
  }
}

class ThemeSheet extends StatelessWidget {
  const ThemeSheet({super.key});

  /// The window's contents: the Look, Mode and (in the UwU Apps look) the system accent switch
  /// and brand colour swatches. Rebuilt whenever the theme changes.
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.I,
      builder: (context, child) {
        final themeController = ThemeController.I;
        final colors = UwuColors.of(context);
        final material = themeController.isMaterial;
        final native = themeController.isNative;
        final glass = themeController.glassStyle;
        final accentGetter = desktopAccentGet;
        bool? accentValue;
        if (accentGetter != null) {
          accentValue = accentGetter.call();
        }
        bool accent;
        if (accentValue == null) {
          accent = false;
        } else {
          accent = accentValue;
        }

        /// A small grey heading above a group of settings.
        Widget section(String text) {
          return Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              text,
              style: TextStyle(color: colors.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          );
        }

        /// One choice in a segmented control: its icon and label, filled in the brand colour
        /// when it is the chosen one.
        Widget segmentOption<T>((T, String, String) option, T value, ValueChanged<T> onPick, String key) {
          final isSelected = option.$1 == value;
          Color? fillColor;
          Color foregroundColor;
          if (isSelected) {
            fillColor = colors.brandFill;
            foregroundColor = colors.onBrand;
          } else {
            fillColor = null;
            foregroundColor = colors.ink;
          }
          return Expanded(
            child: Semantics(
              selected: isSelected,
              button: true,
              child: InkWell(
                mouseCursor: WidgetStateMouseCursor.clickable,
                key: ValueKey('$key-${option.$1}'),
                borderRadius: BorderRadius.circular(9),
                onTap: () {
                  onPick(option.$1);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: fillColor, borderRadius: BorderRadius.circular(9)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppIcon(option.$2, size: 16, color: foregroundColor),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(option.$3, style: TextStyle(fontSize: 13, color: foregroundColor)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        /// A row of choices (value, icon, label) where one is picked, like the site's
        /// segmented buttons.
        Widget segmentedControl<T>(List<(T, String, String)> options, T value, ValueChanged<T> onPick, {String key = ''}) {
          return Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                for (final option in options) segmentOption<T>(option, value, onPick, key),
              ],
            ),
          );
        }

        /// One round brand colour swatch, ticked when it is the chosen colour. Can't be picked
        /// while the system accent colour stands in for it.
        Widget swatch(ColorTheme colorTheme) {
          final isSelected = colorTheme.id == themeController.colorThemeId;
          VoidCallback? onTap;
          if (accent) {
            onTap = null;
          } else {
            onTap = () {
              themeController.setColorTheme(colorTheme.id);
            };
          }
          Color borderColor;
          double borderWidth;
          Widget? tick;
          if (isSelected) {
            borderColor = colors.brandInk;
            borderWidth = 3;
            tick = const Center(child: AppIcon('check', size: 18, color: Color(0xFF121815)));
          } else {
            borderColor = colors.border;
            borderWidth = 1;
            tick = null;
          }
          return Tooltip(
            excludeFromSemantics: true,
            message: colorTheme.label,
            child: Semantics(
              label: colorTheme.label,
              selected: isSelected,
              button: true,
              excludeSemantics: true,
              child: InkWell(
                mouseCursor: WidgetStateMouseCursor.clickable,
                key: ValueKey('swatch-${colorTheme.id}'),
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorTheme.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor, width: borderWidth),
                  ),
                  child: tick,
                ),
              ),
            ),
          );
        }

        // The line under the Look choices, saying what the chosen look is.
        String lookNote;
        if (native) {
          lookNote = _glassNote(glass, themeController.windowMaterial);
        } else if (material) {
          if (themeController.hasDynamic) {
            lookNote = 'Colours and fonts from your device.';
          } else {
            lookNote = 'Material You’s colours and fonts. This device has no palette of its own to share, so it uses uwuBoard’s green.';
          }
        } else {
          lookNote = 'uwuBoard’s own colours and font, as on the website.';
        }

        double swatchesOpacity;
        if (accent) {
          swatchesOpacity = 0.45;
        } else {
          swatchesOpacity = 1;
        }

        return SheetFrame(
          title: 'Theme',
          children: [
            section('Look'),
            segmentedControl<String>(
              [
                if (Env.desktop) (lookNative, 'monitor', glass.label) else (lookMaterial, 'palette', 'Material You'),
                (lookUwuApps, 'sun', 'UwU Apps'),
              ],
              themeController.look,
              themeController.setLook,
              key: 'look',
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                lookNote,
                style: TextStyle(color: colors.muted, fontSize: 12.5),
              ),
            ),
            section('Mode'),
            segmentedControl<String>([('light', 'sun', 'Light'), ('dark', 'moon', 'Dark'), ('time', 'clock', 'Time-based')], themeController.modePreference, themeController.setMode, key: 'mode'),
            if (themeController.modePreference == 'time')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Following the clock. Currently ${themeController.mode}.', style: TextStyle(color: colors.muted, fontSize: 12.5)),
              ),
            if (!material && !native) ...[
              if (Env.desktop && desktopAccentSet != null) ...[
                section('System accent'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Use system accent colour', style: TextStyle(color: colors.ink, fontSize: 14)),
                  subtitle: Text(
                    'Your computer’s accent for highlights, with uwuBoard’s own surfaces and font.',
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                  value: accent,
                  onChanged: (value) {
                    desktopAccentSet!(value);
                  },
                ),
              ],
              section('Brand colour'),
              Opacity(
                opacity: swatchesOpacity,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final colorTheme in colorThemes) swatch(colorTheme),
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
