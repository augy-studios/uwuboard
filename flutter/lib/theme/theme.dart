// The theme, built in one place for every look and both modes.
//
//   The UwU Apps look   the site's own (main-site/style.css and js/theme.js): seven brand
//                       swatches, the Jua font, flat tinted pages and glass panels.
//   Material You        the phone's palette and fonts. On by default on Android 12+, where the
//                       system has a palette to give.
//   Native glass        the desktop's second look, in place of Material You: the system's own
//                       materials, accent colour and font, as near to glass as each desktop
//                       draws it. Fluent 2 on Windows (Mica behind the window, Acrylic on what
//                       floats over it), macOS Tahoe on a Mac (the desktop through the window,
//                       rounded glass and capsule buttons), and DDE and COSMIC's frosted glass
//                       on Linux. The desktop apps still open in the UwU Apps look.
//
// Mode is the site's: light, dark, or time-based (light from 09:00 to 18:00), kept under the
// site's keys so a synced theme means the same on every device. Colours reach widgets as
// tokens (UwuColors), never as literals.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';

class ColorTheme {
  const ColorTheme(this.id, this.label, this.hex);
  final String id;
  final String label;
  final int hex;
  Color get color {
    return Color(0xFF000000 | hex);
  }
}

/// The site's swatches, by the site's ids and names.
const colorThemes = [
  ColorTheme('classic', 'Classic', 0xccffcc),
  ColorTheme('not-green-1', 'Not green 1', 0xffcccc),
  ColorTheme('not-green-2', 'Not green 2', 0xccccff),
  ColorTheme('not-green-3', 'Not green 3', 0xffffcc),
  ColorTheme('not-green-4', 'Not green 4', 0xffccff),
  ColorTheme('not-green-5', 'Not green 5', 0xccffff),
  ColorTheme('really-light-green', 'Really really light green', 0xffffff),
];

const modePreferences = ['light', 'dark', 'time'];
const lightFromHour = 9;
const lightUntilHour = 18;

const _keyColor = 'uwuboard.colorTheme';
const _keyMode = 'uwuboard.mode';
const _keyLegacy = 'uwuboard_theme';
const _legacyColors = {
  'classic': 'classic',
  'pink': 'not-green-1',
  'blue': 'not-green-2',
  'yellow': 'not-green-3',
  'magenta': 'not-green-4',
  'cyan': 'not-green-5',
  'white': 'really-light-green',
};

/// The app's own key: which look, 'material', 'native' or 'uwuapps'. Unset follows the platform.
const keyLook = 'app.look';
const lookMaterial = 'material';
const lookNative = 'native';
const lookUwuApps = 'uwuapps';

/// The desktop's native glass, one per system: what it's called in Theme, and what it's made of.
enum GlassStyle {
  /// Windows 11: Mica behind the window, Acrylic on dialogs and panels, Segoe UI.
  fluent('Fluent 2', 'Acrylic & Mica'),

  /// macOS 26: the desktop through the window, rounded glass, capsule buttons, the system font.
  tahoe('macOS Tahoe', 'Liquid Glass'),

  /// Linux: Deepin's DDE and System76's COSMIC, frosted glass.
  frosted('Frosted Glass', 'Deepin (DDE) & COSMIC');

  const GlassStyle(this.label, this.material);
  final String label;
  final String material;
}

GlassStyle glassStyleFor(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.windows:
      return GlassStyle.fluent;
    case TargetPlatform.macOS:
    case TargetPlatform.iOS:
      return GlassStyle.tahoe;
    default:
      return GlassStyle.frosted;
  }
}

bool isDaylightHours([DateTime? now]) {
  final DateTime time;
  if (now != null) {
    time = now;
  } else {
    time = DateTime.now();
  }
  final hour = time.hour;
  return hour >= lightFromHour && hour < lightUntilHour;
}

String resolveMode(String preference, [DateTime? now]) {
  if (preference == 'time') {
    if (isDaylightHours(now)) {
      return 'light';
    } else {
      return 'dark';
    }
  }
  if (preference == 'dark') {
    return 'dark';
  } else {
    return 'light';
  }
}

/// How long until the next 09:00 or 18:00, whichever comes first, with a second of slack.
Duration untilNextBoundary([DateTime? at]) {
  final DateTime now;
  if (at != null) {
    now = at;
  } else {
    now = DateTime.now();
  }
  DateTime next;
  if (now.hour < lightFromHour) {
    next = DateTime(now.year, now.month, now.day, lightFromHour);
  } else if (now.hour < lightUntilHour) {
    next = DateTime(now.year, now.month, now.day, lightUntilHour);
  } else {
    next = DateTime(now.year, now.month, now.day + 1, lightFromHour);
  }
  final milliseconds = next.difference(now).inMilliseconds + 1000;
  if (milliseconds < 1000) {
    return const Duration(milliseconds: 1000);
  } else {
    return Duration(milliseconds: milliseconds);
  }
}

/// The theme settings: the colour swatch, light/dark/time mode and the look, all kept on this
/// device. Widgets listen to it and rebuild when any of them change.
class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  ThemeController._();
  static final ThemeController I = ThemeController._();

  Timer? _timer;
  bool _watching = false;

  /// Whether the device has a palette of its own to give (Android 12+). Set by the app's root
  /// once the system has answered.
  bool hasDynamic = false;

  /// The desktop's "Use system accent colour", kept in its settings file.
  bool systemAccent = false;

  /// Whether this is the Android app (Env.android, given here to keep the theme free of the app).
  static bool Function() isAndroid = () {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  };

  /// Whether this is a desktop app (Env.desktop), whose second look is native glass, not
  /// Material You.
  static bool Function() isDesktop = () {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux);
  };

  /// Which native glass this desktop draws. For tests and screenshots, any of them.
  static GlassStyle Function() glassStyleOf = () {
    return glassStyleFor(defaultTargetPlatform);
  };

  GlassStyle get glassStyle {
    return glassStyleOf();
  }

  /// Whether the window has the system's own material behind it (Mica, the macOS desktop, the
  /// compositor's blur), as the desktop's runner said. Without one, native glass draws its own
  /// frosted backdrop inside the window.
  bool windowMaterial = false;

  /// For tests and screenshots: the clock the time-based mode reads.
  DateTime Function() clock = DateTime.now;

  /// Moves a colour saved under the site's old key to the new one, starts the time-based mode's
  /// timer, and starts listening for the app coming back to the front.
  void init() {
    final legacyTheme = Store.I.get(_keyLegacy);
    if (legacyTheme != null) {
      if (!Store.I.has(_keyColor) && _legacyColors[legacyTheme] != null) {
        Store.I.put(_keyColor, _legacyColors[legacyTheme]);
      }
      Store.I.remove(_keyLegacy);
    }
    _schedule();
    if (!_watching) {
      _watching = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  String get colorThemeId {
    final stored = Store.I.get(_keyColor);
    final known = colorThemes.any((theme) {
      return theme.id == stored;
    });
    if (known) {
      return stored!;
    } else {
      return 'classic';
    }
  }

  ColorTheme get colorTheme {
    return colorThemes.firstWhere((theme) {
      return theme.id == colorThemeId;
    });
  }

  /// What the person chose, which can be "time".
  String get modePreference {
    final stored = Store.I.get(_keyMode);
    if (modePreferences.contains(stored)) {
      return stored!;
    } else {
      return 'light';
    }
  }

  /// What the app is in right now: only ever light or dark.
  String get mode {
    return resolveMode(modePreference, clock());
  }

  Brightness get brightness {
    if (mode == 'dark') {
      return Brightness.dark;
    } else {
      return Brightness.light;
    }
  }

  /// The look in use: what was chosen, or what suits the platform when nothing was.
  String get look {
    final stored = Store.I.get(keyLook);
    if (isDesktop()) {
      // The desktop's second look is native glass. Material You, kept by an older version,
      // means it now.
      if (stored == lookNative || stored == lookMaterial) {
        return lookNative;
      } else {
        return lookUwuApps;
      }
    }
    if (stored == lookMaterial || stored == lookUwuApps) {
      return stored!;
    }
    if (stored == lookNative) {
      return lookMaterial;
    }
    if (isAndroid() && hasDynamic) {
      return lookMaterial;
    } else {
      return lookUwuApps;
    }
  }

  bool get isMaterial {
    return look == lookMaterial;
  }

  bool get isNative {
    return look == lookNative;
  }

  void setColorTheme(String id) {
    final known = colorThemes.any((theme) {
      return theme.id == id;
    });
    if (!known) {
      return;
    }
    Store.I.put(_keyColor, id);
    notifyListeners();
  }

  void setMode(String preference) {
    final String savedPreference;
    if (modePreferences.contains(preference)) {
      savedPreference = preference;
    } else {
      savedPreference = 'light';
    }
    Store.I.put(_keyMode, savedPreference);
    _schedule();
    notifyListeners();
  }

  void setLook(String look) {
    final String savedLook;
    if (look == lookMaterial || look == lookNative) {
      savedLook = look;
    } else {
      savedLook = lookUwuApps;
    }
    Store.I.put(keyLook, savedLook);
    notifyListeners();
  }

  void setWindowMaterial(bool on) {
    if (windowMaterial == on) {
      return;
    }
    windowMaterial = on;
    notifyListeners();
  }

  void setSystemAccent(bool on) {
    systemAccent = on;
    notifyListeners();
  }

  void setHasDynamic(bool has) {
    if (hasDynamic == has) {
      return;
    }
    hasDynamic = has;
    // After this frame: it's learnt while building.
    scheduleMicrotask(notifyListeners);
  }

  /// Something else changed the stored theme (a sync, the welcome window).
  void refresh() {
    _schedule();
    notifyListeners();
  }

  // Keeping the time-based mode honest while the app stays open.
  void _schedule() {
    final previousTimer = _timer;
    if (previousTimer != null) {
      previousTimer.cancel();
    }
    _timer = null;
    if (modePreference != 'time') {
      return;
    }
    _timer = Timer(untilNextBoundary(clock()), () {
      _schedule();
      notifyListeners();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && modePreference == 'time') {
      _schedule();
      notifyListeners();
    }
  }
}

/// The colours widgets draw with, by what they're for.
@immutable
class UwuColors extends ThemeExtension<UwuColors> {
  const UwuColors({
    required this.bg,
    required this.surface,
    required this.surfaceStrong,
    required this.border,
    required this.ink,
    required this.muted,
    required this.brand,
    required this.brandInk,
    required this.brandFill,
    required this.brandFillStrong,
    required this.onBrand,
    required this.ok,
    required this.warn,
    required this.busy,
    required this.error,
    required this.errorFill,
    required this.scrim,
    required this.glass,
    Color? edge,
    this.native,
  }) : _edge = edge;

  final Color bg;
  final Color surface;
  final Color surfaceStrong;
  final Color border;
  final Color ink;
  final Color muted;
  final Color brand;
  final Color brandInk;
  final Color brandFill;
  final Color brandFillStrong;
  final Color onBrand;
  final Color ok;
  final Color warn;
  final Color busy;
  final Color error;
  final Color errorFill;
  final Color scrim;

  /// Whether panels are glass (blurred, see-through) or solid.
  final bool glass;

  /// The edge colour given when this was made, or null to use [border].
  final Color? _edge;

  /// The outline of what only holds things (panels, windows, the sidebar, dividers), as opposed
  /// to [border], round what's pressed or typed in. The same colour but in native glass, whose
  /// panels have a fine bright rim instead.
  Color get edge {
    final givenEdge = _edge;
    if (givenEdge != null) {
      return givenEdge;
    } else {
      return border;
    }
  }

  /// The native glass this is, or null for the UwU Apps look and Material You.
  final GlassStyle? native;

  /// A corner radius as the look rounds it: Fluent's small and even, Tahoe's generous.
  double round(double radius) {
    switch (native) {
      case GlassStyle.fluent:
        if (radius > 8) {
          return 8;
        } else {
          return radius;
        }
      case GlassStyle.tahoe:
        if (radius < 12) {
          return radius;
        } else {
          return radius * 1.15;
        }
      case GlassStyle.frosted:
        if (radius > 16) {
          return 16;
        } else {
          return radius;
        }
      case null:
        return radius;
    }
  }

  /// A window's corners over the page: a dialog's, a sheet's.
  double get windowRadius {
    switch (native) {
      case GlassStyle.fluent:
        return 8;
      case GlassStyle.tahoe:
        return 26;
      case GlassStyle.frosted:
        return 16;
      case null:
        return 18;
    }
  }

  static UwuColors of(BuildContext context) {
    return Theme.of(context).extension<UwuColors>()!;
  }

  @override
  UwuColors copyWith() {
    return this;
  }

  @override
  UwuColors lerp(ThemeExtension<UwuColors>? other, double t) {
    if (t < 0.5 || other is! UwuColors) {
      return this;
    } else {
      return other;
    }
  }
}

/// [foreground] laid over [background] by [amount] (0 is all background, 1 all foreground).
Color _mix(Color foreground, double amount, Color background) {
  return Color.lerp(background, foreground, amount)!;
}

const _ink = Color(0xFF121815);

/// The site's tokens, for one swatch and mode.
UwuColors uwuAppsColors(Color brand, Brightness brightness, {Color? accent}) {
  final dark = brightness == Brightness.dark;
  final Color base;
  if (dark) {
    base = const Color(0xFF0C100E);
  } else {
    base = const Color(0xFFEEF2F0);
  }
  final background = _mix(brand, 0.10, base);
  // The site's surfaces are white at an opacity over the page. Here they're laid over the page
  // colour once, so words on them keep the contrast the site measured.
  Color over(double alpha) {
    return Color.alphaBlend(Colors.white.withValues(alpha: alpha), background);
  }

  final double surfaceAlpha;
  final double surfaceStrongAlpha;
  if (dark) {
    surfaceAlpha = 0.06;
    surfaceStrongAlpha = 0.11;
  } else {
    surfaceAlpha = 0.55;
    surfaceStrongAlpha = 0.78;
  }
  final surface = over(surfaceAlpha);
  final surfaceStrong = over(surfaceStrongAlpha);
  Color brandInk;
  if (dark) {
    brandInk = const Color(0xFFBFF5CF);
  } else {
    brandInk = const Color(0xFF1F6B3D);
  }
  if (accent != null) {
    final hsl = HSLColor.fromColor(accent);
    final double accentLightness;
    if (dark) {
      accentLightness = 0.82;
    } else {
      accentLightness = 0.28;
    }
    brandInk = hsl.withLightness(accentLightness).withSaturation(hsl.saturation.clamp(0.3, 0.75)).toColor();
  }
  final Color tint;
  if (accent == null) {
    tint = brand;
  } else {
    tint = HSLColor.fromColor(accent).withLightness(0.88).toColor();
  }
  // The fixed colours for this mode.
  final Color error;
  final Color border;
  final Color ink;
  final Color muted;
  final Color ok;
  final Color warn;
  final Color busy;
  final double scrimAlpha;
  if (dark) {
    error = const Color(0xFFFA9696);
    border = const Color(0xFF84938A);
    ink = const Color(0xFFEEF2EF);
    muted = const Color(0xFFB4BEB8);
    ok = const Color(0xFF4ADE80);
    warn = const Color(0xFFFBBF24);
    busy = const Color(0xFF94A3B8);
    scrimAlpha = 0.6;
  } else {
    error = const Color(0xFFB91C1C);
    border = const Color(0xFF6F7E75);
    ink = _ink;
    muted = const Color(0xFF4A554E);
    ok = const Color(0xFF0F7234);
    warn = const Color(0xFFA24B08);
    busy = const Color(0xFF627288);
    scrimAlpha = 0.35;
  }
  return UwuColors(
    bg: background,
    surface: surface,
    surfaceStrong: surfaceStrong,
    // Component edges at 3:1 or more against every surface, for all seven brand colours (WCAG
    // 1.4.11): the site's white-on-white glass edges vanish in light mode.
    border: border,
    ink: ink,
    muted: muted,
    brand: tint,
    brandInk: brandInk,
    brandFill: _mix(tint, 0.55, surfaceStrong),
    brandFillStrong: _mix(tint, 0.75, surfaceStrong),
    onBrand: _ink,
    ok: ok,
    warn: warn,
    busy: busy,
    error: error,
    errorFill: _mix(error, 0.14, background),
    scrim: Colors.black.withValues(alpha: scrimAlpha),
    glass: true,
  );
}

/// The same tokens from a Material colour scheme.
UwuColors materialColors(ColorScheme scheme) {
  final dark = scheme.brightness == Brightness.dark;
  final Color ok;
  final Color warn;
  final double scrimAlpha;
  if (dark) {
    ok = const Color(0xFF7DDC9A);
    warn = const Color(0xFFFBBF24);
    scrimAlpha = 0.6;
  } else {
    ok = const Color(0xFF0F7234);
    warn = const Color(0xFFA24B08);
    scrimAlpha = 0.4;
  }
  return UwuColors(
    bg: scheme.surface,
    surface: scheme.surfaceContainerLow,
    surfaceStrong: scheme.surfaceContainerHigh,
    // outline, not outlineVariant: Material's outline is the one made for 3:1 edges (WCAG 1.4.11).
    border: scheme.outline,
    ink: scheme.onSurface,
    muted: scheme.onSurfaceVariant,
    brand: scheme.primaryContainer,
    brandInk: scheme.primary,
    brandFill: scheme.primaryContainer,
    brandFillStrong: _mix(scheme.primary, 0.18, scheme.primaryContainer),
    onBrand: scheme.onPrimaryContainer,
    ok: ok,
    warn: warn,
    busy: scheme.onSurfaceVariant,
    error: scheme.error,
    errorFill: scheme.errorContainer,
    scrim: scheme.scrim.withValues(alpha: scrimAlpha),
    glass: false,
  );
}

/// WCAG's contrast ratio between two colours, from 1 to 21.
double contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final double lighter;
  final double darker;
  if (firstLuminance > secondLuminance) {
    lighter = firstLuminance + 0.05;
    darker = secondLuminance + 0.05;
  } else {
    lighter = secondLuminance + 0.05;
    darker = firstLuminance + 0.05;
  }
  return lighter / darker;
}

/// The accent, darkened (lightened, in dark mode) until words in it read at 4.5:1 on each of
/// `backgrounds`: any accent the system has, yellow included, still makes readable links and labels.
Color _readableAccent(Color accent, List<Color> backgrounds, bool dark) {
  var hsl = HSLColor.fromColor(accent);
  final double lightnessStep;
  if (dark) {
    lightnessStep = 0.015;
  } else {
    lightnessStep = -0.015;
  }
  for (var attempt = 0; attempt < 60; attempt = attempt + 1) {
    final candidate = hsl.toColor();
    final readsOnAll = backgrounds.every((background) {
      return contrastRatio(candidate, background) >= 4.5;
    });
    if (readsOnAll) {
      return candidate;
    }
    hsl = hsl.withLightness((hsl.lightness + lightnessStep).clamp(0.0, 1.0));
  }
  return hsl.toColor();
}

/// The accent laid over `over`, as much as `amount` of it, less if `ink` would no longer read on it.
Color _accentFill(Color accent, double amount, Color over, Color ink) {
  var currentAmount = amount;
  var fill = _mix(accent, currentAmount, over);
  while (currentAmount > 0.04 && contrastRatio(ink, fill) < 4.5) {
    currentAmount = currentAmount - 0.02;
    fill = _mix(accent, currentAmount, over);
  }
  return fill;
}

/// White or near-black, whichever reads better on `background`: the words on an accent-coloured button.
Color onColor(Color background) {
  if (contrastRatio(Colors.white, background) >= contrastRatio(_ink, background)) {
    return Colors.white;
  } else {
    return _ink;
  }
}

/// The system's own accent where it has none to give: Windows', macOS' and DDE's blue.
Color defaultAccent(GlassStyle style) {
  switch (style) {
    case GlassStyle.fluent:
      return const Color(0xFF0078D4);
    case GlassStyle.tahoe:
      return const Color(0xFF007AFF);
    case GlassStyle.frosted:
      return const Color(0xFF0081FF);
  }
}

/// How much of the window colour lies over the system's material, when there is one: Mica is
/// already tinted, macOS' sidebar glass a little, a compositor's blur not at all.
double glassWindowAlpha(GlassStyle style) {
  switch (style) {
    case GlassStyle.fluent:
      return 0.3;
    case GlassStyle.tahoe:
      return 0.45;
    case GlassStyle.frosted:
      return 0.62;
  }
}

/// Native glass's tokens, for one system and mode, in the system's accent colour.
///
/// `bg` is the system's own window colour, solid: what words and fills are measured against.
/// The window itself is drawn see-through over the system's material (lib/widgets/glass.dart),
/// and the surfaces are white at an opacity over it, so the glass shows through what holds
/// things while words keep the contrast measured here.
UwuColors glassColors(GlassStyle style, Brightness brightness, {Color? accent}) {
  final dark = brightness == Brightness.dark;
  // Per system and mode: the window colour, how white the surfaces are (light and strong), the
  // words, quieter words, and the edges of what's pressed or typed in, at 3:1 or more (WCAG
  // 1.4.11): Fluent's strong control stroke, Apple's secondary grey, DDE's slate. Then the fine
  // edge round what only holds things.
  final int backgroundValue;
  final double lowAlpha;
  final double highAlpha;
  final int inkValue;
  final int mutedValue;
  final int borderValue;
  final Color edge;
  switch (style) {
    case GlassStyle.fluent:
      if (dark) {
        backgroundValue = 0xFF202020;
        lowAlpha = 0.05;
        highAlpha = 0.09;
        inkValue = 0xFFFFFFFF;
        mutedValue = 0xFFC5C5C5;
        borderValue = 0xFF9A9A9A;
        edge = Colors.white.withValues(alpha: 0.10);
      } else {
        backgroundValue = 0xFFF3F3F3;
        lowAlpha = 0.70;
        highAlpha = 0.90;
        inkValue = 0xFF1B1B1B;
        mutedValue = 0xFF5C5C5C;
        borderValue = 0xFF8A8A8A;
        edge = Colors.black.withValues(alpha: 0.09);
      }
    case GlassStyle.tahoe:
      if (dark) {
        backgroundValue = 0xFF1C1C1E;
        lowAlpha = 0.08;
        highAlpha = 0.14;
        inkValue = 0xFFF5F5F7;
        mutedValue = 0xFFAEAEB2;
        borderValue = 0xFF8E8E93;
        edge = Colors.white.withValues(alpha: 0.14);
      } else {
        backgroundValue = 0xFFF5F5F7;
        lowAlpha = 0.55;
        highAlpha = 0.80;
        inkValue = 0xFF1D1D1F;
        mutedValue = 0xFF5E5E63;
        borderValue = 0xFF86868B;
        edge = Colors.black.withValues(alpha: 0.10);
      }
    case GlassStyle.frosted:
      if (dark) {
        backgroundValue = 0xFF1E2025;
        lowAlpha = 0.06;
        highAlpha = 0.11;
        inkValue = 0xFFE8EBF0;
        mutedValue = 0xFFAAB2BE;
        borderValue = 0xFF8A93A0;
        edge = Colors.white.withValues(alpha: 0.12);
      } else {
        backgroundValue = 0xFFF7F8FA;
        lowAlpha = 0.60;
        highAlpha = 0.85;
        inkValue = 0xFF1E2330;
        mutedValue = 0xFF4F5A6B;
        borderValue = 0xFF7F8896;
        edge = Colors.black.withValues(alpha: 0.08);
      }
  }
  final background = Color(backgroundValue);
  final surface = Colors.white.withValues(alpha: lowAlpha);
  final surfaceStrong = Colors.white.withValues(alpha: highAlpha);
  final strong = Color.alphaBlend(surfaceStrong, background);
  final inkColor = Color(inkValue);
  final Color tint;
  if (accent != null) {
    tint = accent;
  } else {
    tint = defaultAccent(style);
  }
  // The fixed colours for this mode, and how strongly the accent fills buttons.
  final Color error;
  final double brandFillAmount;
  final double brandFillStrongAmount;
  final Color ok;
  final Color warn;
  final double scrimAlpha;
  if (dark) {
    error = const Color(0xFFFF99A4);
    brandFillAmount = 0.32;
    brandFillStrongAmount = 0.48;
    ok = const Color(0xFF6CCB5F);
    warn = const Color(0xFFFBBF24);
    scrimAlpha = 0.5;
  } else {
    error = const Color(0xFFC42B1C);
    brandFillAmount = 0.20;
    brandFillStrongAmount = 0.32;
    ok = const Color(0xFF0F7B0F);
    warn = const Color(0xFFA24B08);
    scrimAlpha = 0.28;
  }
  return UwuColors(
    bg: background,
    surface: surface,
    surfaceStrong: surfaceStrong,
    border: Color(borderValue),
    edge: edge,
    ink: inkColor,
    muted: Color(mutedValue),
    brand: tint,
    brandInk: _readableAccent(tint, [background, strong], dark),
    brandFill: _accentFill(tint, brandFillAmount, strong, inkColor),
    brandFillStrong: _accentFill(tint, brandFillStrongAmount, strong, inkColor),
    onBrand: inkColor,
    ok: ok,
    warn: warn,
    busy: Color(mutedValue),
    error: error,
    errorFill: _mix(error, 0.14, background),
    scrim: Colors.black.withValues(alpha: scrimAlpha),
    glass: true,
    native: style,
  );
}

/// Native glass's font: Windows 11's Segoe UI Variable; on a Mac and on Linux, the system's own.
String? glassFont(GlassStyle style) {
  if (style == GlassStyle.fluent) {
    return 'Segoe UI Variable Text';
  } else {
    return null;
  }
}

/// The whole theme. `dynamicScheme` is the device's palette (Material You), or the desktop's
/// accent as a scheme, when there is one. Native glass takes the desktop's accent as it is
/// (`accent`) and its `glassStyle`.
ThemeData buildTheme({
  required String look,
  required Brightness brightness,
  required Color brand,
  ColorScheme? dynamicScheme,
  bool systemAccent = false,
  bool highContrast = false,
  bool desktop = false,
  GlassStyle glassStyle = GlassStyle.frosted,
  Color? accent,
}) {
  final material = look == lookMaterial;
  final native = look == lookNative;
  late final ColorScheme scheme;
  late final UwuColors colors;
  // The colours: Material You's from its scheme; the other looks' tokens, with a scheme made
  // from them so Flutter's own widgets match.
  if (material) {
    final ColorScheme baseScheme;
    if (dynamicScheme != null) {
      baseScheme = dynamicScheme;
    } else {
      final double contrastLevel;
      if (highContrast) {
        contrastLevel = 1.0;
      } else {
        contrastLevel = 0.0;
      }
      baseScheme = ColorScheme.fromSeed(seedColor: const Color(0xFF22A85A), brightness: brightness, contrastLevel: contrastLevel);
    }
    scheme = baseScheme.copyWith(brightness: brightness);
    colors = materialColors(scheme);
  } else {
    if (native) {
      colors = glassColors(glassStyle, brightness, accent: accent);
    } else {
      Color? systemAccentColour;
      if (systemAccent && dynamicScheme != null) {
        systemAccentColour = dynamicScheme.primary;
      } else {
        systemAccentColour = null;
      }
      colors = uwuAppsColors(brand, brightness, accent: systemAccentColour);
    }
    final Color onPrimary;
    if (native) {
      onPrimary = onColor(colors.brandInk);
    } else {
      onPrimary = colors.bg;
    }
    scheme = ColorScheme.fromSeed(seedColor: colors.brandInk, brightness: brightness).copyWith(
      primary: colors.brandInk,
      onPrimary: onPrimary,
      primaryContainer: colors.brandFill,
      onPrimaryContainer: colors.onBrand,
      secondaryContainer: colors.brandFill,
      onSecondaryContainer: colors.onBrand,
      surface: colors.bg,
      onSurface: colors.ink,
      onSurfaceVariant: colors.muted,
      surfaceContainerLowest: colors.bg,
      surfaceContainerLow: colors.surface,
      surfaceContainer: colors.surface,
      surfaceContainerHigh: colors.surfaceStrong,
      surfaceContainerHighest: colors.surfaceStrong,
      outline: colors.muted,
      outlineVariant: colors.border,
      error: colors.error,
      onError: colors.bg,
      errorContainer: colors.errorFill,
      onErrorContainer: colors.error,
    );
  }

  // The font: the system's in Material You, the desktop's own in native glass, else Jua.
  final String? font;
  if (material) {
    font = null;
  } else if (native) {
    font = glassFont(glassStyle);
  } else {
    font = 'Jua';
  }
  final List<String>? fallback;
  if (native && glassStyle == GlassStyle.fluent) {
    fallback = const ['Segoe UI Variable', 'Segoe UI'];
  } else {
    fallback = null;
  }
  final tahoe = native && glassStyle == GlassStyle.tahoe;
  // Corners: a control's, a window's over the page, and a tooltip's. Fluent 2 rounds little and
  // evenly; Tahoe's glass a lot, its buttons into capsules; DDE and COSMIC between the two.
  final double controlRadius;
  if (material) {
    controlRadius = 14.0;
  } else if (native) {
    switch (glassStyle) {
      case GlassStyle.fluent:
        controlRadius = 4.0;
      case GlassStyle.tahoe:
        controlRadius = 10.0;
      case GlassStyle.frosted:
        controlRadius = 8.0;
    }
  } else {
    controlRadius = 10.0;
  }
  final double windowRadius;
  if (material) {
    windowRadius = 28.0;
  } else {
    windowRadius = colors.windowRadius;
  }
  final radius = BorderRadius.circular(controlRadius);
  final OutlinedBorder buttonShape;
  if (tahoe) {
    buttonShape = const StadiumBorder();
  } else {
    buttonShape = RoundedRectangleBorder(borderRadius: radius);
  }
  // Windows over the page: nearly solid, so they read wherever they open; the desktop's own
  // dialogs and panels blur what's behind them as well (lib/desktop/adaptive.dart).
  final Color overlay;
  if (native) {
    overlay = Color.alphaBlend(colors.surfaceStrong, colors.bg).withValues(alpha: 0.94);
  } else {
    overlay = Color.alphaBlend(colors.surfaceStrong.withValues(alpha: 0.9), colors.bg);
  }
  final Color scaffoldBackground;
  if (native) {
    scaffoldBackground = Colors.transparent;
  } else {
    scaffoldBackground = colors.bg;
  }
  final VisualDensity density;
  if (desktop) {
    density = VisualDensity.compact;
  } else {
    density = VisualDensity.standard;
  }
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: font,
    fontFamilyFallback: fallback,
    // Native glass's page is the window, see-through to the system's material: the backdrop
    // under the whole app (lib/widgets/glass.dart) draws it.
    scaffoldBackgroundColor: scaffoldBackground,
    // A computer's rows and buttons are closer set than a phone's.
    visualDensity: density,
    extensions: [colors],
  );

  // Sizes and colours for each kind of widget below.
  final double tooltipRadius;
  if (native && controlRadius < 8) {
    tooltipRadius = controlRadius;
  } else {
    tooltipRadius = 8;
  }
  final double inputVerticalPadding;
  final double filledVerticalPadding;
  final double outlinedVerticalPadding;
  if (desktop) {
    inputVerticalPadding = 10;
    filledVerticalPadding = 12;
    outlinedVerticalPadding = 10;
  } else {
    inputVerticalPadding = 13;
    filledVerticalPadding = 14;
    outlinedVerticalPadding = 12;
  }
  Color? filledBackground;
  Color? filledForeground;
  OutlinedBorder filledShape;
  if (material || native) {
    filledBackground = null;
    filledForeground = null;
    filledShape = buttonShape;
  } else {
    filledBackground = colors.brandFill;
    filledForeground = colors.onBrand;
    filledShape = buttonShape.copyWith(side: BorderSide(color: colors.border));
  }
  final FontWeight filledWeight;
  if (material) {
    filledWeight = FontWeight.w600;
  } else if (native) {
    filledWeight = FontWeight.w500;
  } else {
    filledWeight = FontWeight.w400;
  }
  Color? outlinedBackground;
  if (material) {
    outlinedBackground = null;
  } else {
    outlinedBackground = colors.surfaceStrong;
  }
  SwitchThemeData? switchTheme;
  if (material || native) {
    switchTheme = null;
  } else {
    switchTheme = SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.brandInk;
        } else {
          return colors.surfaceStrong;
        }
      }),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.bg;
        } else {
          return colors.muted;
        }
      }),
      trackOutlineColor: WidgetStatePropertyAll(colors.border),
    );
  }
  final Color dialogBackground;
  final Color sheetBackground;
  if (colors.glass) {
    dialogBackground = overlay;
    sheetBackground = overlay;
  } else {
    dialogBackground = scheme.surfaceContainerHigh;
    sheetBackground = scheme.surfaceContainerLow;
  }
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: colors.ink, displayColor: colors.ink),
    iconTheme: IconThemeData(color: colors.ink, size: 20),
    dividerTheme: DividerThemeData(color: colors.edge, space: 1, thickness: 1),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(color: colors.ink, borderRadius: BorderRadius.circular(tooltipRadius)),
      textStyle: TextStyle(color: colors.bg, fontSize: 12, fontFamily: font),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: colors.surfaceStrong,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: inputVerticalPadding),
      hintStyle: TextStyle(color: colors.muted),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.brandInk, width: 2),
      ),
    ),
    // Flutter gives buttons a pointing hand only on the web, and the arrow everywhere else; the
    // site points at what can be pressed, so every button here does the same, on the desktop too.
    // InkWells, dropdowns and chips can't take this from the theme, so they name it themselves.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Native glass's are in the accent colour, as the system's own default buttons are.
        backgroundColor: filledBackground,
        foregroundColor: filledForeground,
        shape: filledShape,
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: filledVerticalPadding),
        textStyle: TextStyle(fontFamily: font, fontSize: 14, fontWeight: filledWeight),
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.ink,
        backgroundColor: outlinedBackground,
        side: BorderSide(color: colors.border),
        shape: buttonShape,
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: outlinedVerticalPadding),
        textStyle: TextStyle(fontFamily: font, fontSize: 13),
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.brandInk,
        textStyle: TextStyle(fontFamily: font, fontSize: 13),
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),
    iconButtonTheme: const IconButtonThemeData(style: ButtonStyle(mouseCursor: WidgetStateMouseCursor.clickable)),
    popupMenuTheme: const PopupMenuThemeData(mouseCursor: WidgetStateMouseCursor.clickable),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.brandInk;
        } else {
          return null;
        }
      }),
      checkColor: WidgetStatePropertyAll(colors.bg),
      side: BorderSide(color: colors.muted, width: 1.5),
      mouseCursor: WidgetStateMouseCursor.clickable,
    ),
    switchTheme: switchTheme,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.ink,
      contentTextStyle: TextStyle(color: colors.bg, fontFamily: font, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(colors.round(12))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dialogBackground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(windowRadius),
        side: BorderSide(color: colors.edge),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: sheetBackground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(windowRadius))),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(colors.muted.withValues(alpha: 0.5)),
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(4),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.brandFill,
      selectedIconTheme: IconThemeData(color: colors.onBrand, size: 20),
      unselectedIconTheme: IconThemeData(color: colors.ink, size: 20),
      selectedLabelTextStyle: TextStyle(color: colors.ink, fontSize: 11, fontFamily: font),
      unselectedLabelTextStyle: TextStyle(color: colors.muted, fontSize: 11, fontFamily: font),
    ),
  );
}
