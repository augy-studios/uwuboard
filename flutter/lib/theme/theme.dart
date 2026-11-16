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
  Color get color => Color(0xFF000000 | hex);
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

GlassStyle glassStyleFor(TargetPlatform platform) => switch (platform) {
  TargetPlatform.windows => GlassStyle.fluent,
  TargetPlatform.macOS || TargetPlatform.iOS => GlassStyle.tahoe,
  _ => GlassStyle.frosted,
};

bool isDaylightHours([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  return h >= lightFromHour && h < lightUntilHour;
}

String resolveMode(String preference, [DateTime? now]) {
  if (preference == 'time') return isDaylightHours(now) ? 'light' : 'dark';
  return preference == 'dark' ? 'dark' : 'light';
}

/// How long until the next 09:00 or 18:00, whichever comes first, with a second of slack.
Duration untilNextBoundary([DateTime? at]) {
  final now = at ?? DateTime.now();
  DateTime next;
  if (now.hour < lightFromHour) {
    next = DateTime(now.year, now.month, now.day, lightFromHour);
  } else if (now.hour < lightUntilHour) {
    next = DateTime(now.year, now.month, now.day, lightUntilHour);
  } else {
    next = DateTime(now.year, now.month, now.day + 1, lightFromHour);
  }
  final ms = next.difference(now).inMilliseconds + 1000;
  return Duration(milliseconds: ms < 1000 ? 1000 : ms);
}

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
  static bool Function() isAndroid = () => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether this is a desktop app (Env.desktop), whose second look is native glass, not
  /// Material You.
  static bool Function() isDesktop = () =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux);

  /// Which native glass this desktop draws. For tests and screenshots, any of them.
  static GlassStyle Function() glassStyleOf = () => glassStyleFor(defaultTargetPlatform);

  GlassStyle get glassStyle => glassStyleOf();

  /// Whether the window has the system's own material behind it (Mica, the macOS desktop, the
  /// compositor's blur), as the desktop's runner said. Without one, native glass draws its own
  /// frosted backdrop inside the window.
  bool windowMaterial = false;

  /// For tests and screenshots: the clock the time-based mode reads.
  DateTime Function() clock = DateTime.now;

  void init() {
    final old = Store.I.get(_keyLegacy);
    if (old != null) {
      if (!Store.I.has(_keyColor) && _legacyColors[old] != null) Store.I.put(_keyColor, _legacyColors[old]);
      Store.I.remove(_keyLegacy);
    }
    _schedule();
    if (!_watching) {
      _watching = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  String get colorThemeId {
    final v = Store.I.get(_keyColor);
    return colorThemes.any((t) => t.id == v) ? v! : 'classic';
  }

  ColorTheme get colorTheme => colorThemes.firstWhere((t) => t.id == colorThemeId);

  /// What the person chose, which can be "time".
  String get modePreference {
    final v = Store.I.get(_keyMode);
    return modePreferences.contains(v) ? v! : 'light';
  }

  /// What the app is in right now: only ever light or dark.
  String get mode => resolveMode(modePreference, clock());
  Brightness get brightness => mode == 'dark' ? Brightness.dark : Brightness.light;

  String get look {
    final v = Store.I.get(keyLook);
    if (isDesktop()) {
      // The desktop's second look is native glass. Material You, kept by an older version,
      // means it now.
      return v == lookNative || v == lookMaterial ? lookNative : lookUwuApps;
    }
    if (v == lookMaterial || v == lookUwuApps) return v!;
    if (v == lookNative) return lookMaterial;
    return isAndroid() && hasDynamic ? lookMaterial : lookUwuApps;
  }

  bool get isMaterial => look == lookMaterial;
  bool get isNative => look == lookNative;

  void setColorTheme(String id) {
    if (!colorThemes.any((t) => t.id == id)) return;
    Store.I.put(_keyColor, id);
    notifyListeners();
  }

  void setMode(String preference) {
    Store.I.put(_keyMode, modePreferences.contains(preference) ? preference : 'light');
    _schedule();
    notifyListeners();
  }

  void setLook(String look) {
    Store.I.put(keyLook, look == lookMaterial || look == lookNative ? look : lookUwuApps);
    notifyListeners();
  }

  void setWindowMaterial(bool on) {
    if (windowMaterial == on) return;
    windowMaterial = on;
    notifyListeners();
  }

  void setSystemAccent(bool on) {
    systemAccent = on;
    notifyListeners();
  }

  void setHasDynamic(bool has) {
    if (hasDynamic == has) return;
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
    _timer?.cancel();
    _timer = null;
    if (modePreference != 'time') return;
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
  }) : edge = edge ?? border;

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

  /// The outline of what only holds things (panels, windows, the sidebar, dividers), as opposed
  /// to [border], round what's pressed or typed in. The same colour but in native glass, whose
  /// panels have a fine bright rim instead.
  final Color edge;

  /// The native glass this is, or null for the UwU Apps look and Material You.
  final GlassStyle? native;

  /// A corner radius as the look rounds it: Fluent's small and even, Tahoe's generous.
  double round(double r) => switch (native) {
    GlassStyle.fluent => r > 8 ? 8 : r,
    GlassStyle.tahoe => r < 12 ? r : r * 1.15,
    GlassStyle.frosted => r > 16 ? 16 : r,
    null => r,
  };

  /// A window's corners over the page: a dialog's, a sheet's.
  double get windowRadius => switch (native) {
    GlassStyle.fluent => 8,
    GlassStyle.tahoe => 26,
    GlassStyle.frosted => 16,
    null => 18,
  };

  static UwuColors of(BuildContext context) => Theme.of(context).extension<UwuColors>()!;

  @override
  UwuColors copyWith() => this;

  @override
  UwuColors lerp(ThemeExtension<UwuColors>? other, double t) => t < 0.5 || other is! UwuColors ? this : other;
}

Color _mix(Color a, double amount, Color b) => Color.lerp(b, a, amount)!;

const _ink = Color(0xFF121815);

/// The site's tokens, for one swatch and mode.
UwuColors uwuAppsColors(Color brand, Brightness brightness, {Color? accent}) {
  final dark = brightness == Brightness.dark;
  final base = dark ? const Color(0xFF0C100E) : const Color(0xFFEEF2F0);
  final bg = _mix(brand, 0.10, base);
  // The site's surfaces are white at an opacity over the page. Here they're laid over the page
  // colour once, so words on them keep the contrast the site measured.
  Color over(double a) => Color.alphaBlend(Colors.white.withValues(alpha: a), bg);
  final surface = over(dark ? 0.06 : 0.55);
  final surfaceStrong = over(dark ? 0.11 : 0.78);
  var brandInk = dark ? const Color(0xFFBFF5CF) : const Color(0xFF1F6B3D);
  if (accent != null) {
    final hsl = HSLColor.fromColor(accent);
    brandInk = hsl.withLightness(dark ? 0.82 : 0.28).withSaturation(hsl.saturation.clamp(0.3, 0.75)).toColor();
  }
  final tint = accent == null ? brand : HSLColor.fromColor(accent).withLightness(0.88).toColor();
  final error = dark ? const Color(0xFFFA9696) : const Color(0xFFB91C1C);
  return UwuColors(
    bg: bg,
    surface: surface,
    surfaceStrong: surfaceStrong,
    // Component edges at 3:1 or more against every surface, for all seven brand colours (WCAG
    // 1.4.11): the site's white-on-white glass edges vanish in light mode.
    border: dark ? const Color(0xFF84938A) : const Color(0xFF6F7E75),
    ink: dark ? const Color(0xFFEEF2EF) : _ink,
    muted: dark ? const Color(0xFFB4BEB8) : const Color(0xFF4A554E),
    brand: tint,
    brandInk: brandInk,
    brandFill: _mix(tint, 0.55, surfaceStrong),
    brandFillStrong: _mix(tint, 0.75, surfaceStrong),
    onBrand: _ink,
    ok: dark ? const Color(0xFF4ADE80) : const Color(0xFF0F7234),
    warn: dark ? const Color(0xFFFBBF24) : const Color(0xFFA24B08),
    busy: dark ? const Color(0xFF94A3B8) : const Color(0xFF627288),
    error: error,
    errorFill: _mix(error, 0.14, bg),
    scrim: Colors.black.withValues(alpha: dark ? 0.6 : 0.35),
    glass: true,
  );
}

/// The same tokens from a Material colour scheme.
UwuColors materialColors(ColorScheme s) {
  final dark = s.brightness == Brightness.dark;
  return UwuColors(
    bg: s.surface,
    surface: s.surfaceContainerLow,
    surfaceStrong: s.surfaceContainerHigh,
    // outline, not outlineVariant: Material's outline is the one made for 3:1 edges (WCAG 1.4.11).
    border: s.outline,
    ink: s.onSurface,
    muted: s.onSurfaceVariant,
    brand: s.primaryContainer,
    brandInk: s.primary,
    brandFill: s.primaryContainer,
    brandFillStrong: _mix(s.primary, 0.18, s.primaryContainer),
    onBrand: s.onPrimaryContainer,
    ok: dark ? const Color(0xFF7DDC9A) : const Color(0xFF0F7234),
    warn: dark ? const Color(0xFFFBBF24) : const Color(0xFFA24B08),
    busy: s.onSurfaceVariant,
    error: s.error,
    errorFill: s.errorContainer,
    scrim: s.scrim.withValues(alpha: dark ? 0.6 : 0.4),
    glass: false,
  );
}

/// WCAG's contrast ratio between two colours, from 1 to 21.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

/// The accent, darkened (lightened, in dark mode) until words in it read at 4.5:1 on each of
/// `on`: any accent the system has, yellow included, still makes readable links and labels.
Color _readableAccent(Color accent, List<Color> on, bool dark) {
  var hsl = HSLColor.fromColor(accent);
  for (var i = 0; i < 60; i++) {
    final c = hsl.toColor();
    if (on.every((b) => contrastRatio(c, b) >= 4.5)) return c;
    hsl = hsl.withLightness((hsl.lightness + (dark ? 0.015 : -0.015)).clamp(0.0, 1.0));
  }
  return hsl.toColor();
}

/// The accent laid over `over`, as much as `amount` of it, less if `ink` would no longer read on it.
Color _accentFill(Color accent, double amount, Color over, Color ink) {
  var a = amount;
  var fill = _mix(accent, a, over);
  while (a > 0.04 && contrastRatio(ink, fill) < 4.5) {
    a -= 0.02;
    fill = _mix(accent, a, over);
  }
  return fill;
}

/// White or near-black, whichever reads better on `c`: the words on an accent-coloured button.
Color onColor(Color c) => contrastRatio(Colors.white, c) >= contrastRatio(_ink, c) ? Colors.white : _ink;

/// The system's own accent where it has none to give: Windows', macOS' and DDE's blue.
Color defaultAccent(GlassStyle style) => switch (style) {
  GlassStyle.fluent => const Color(0xFF0078D4),
  GlassStyle.tahoe => const Color(0xFF007AFF),
  GlassStyle.frosted => const Color(0xFF0081FF),
};

/// How much of the window colour lies over the system's material, when there is one: Mica is
/// already tinted, macOS' sidebar glass a little, a compositor's blur not at all.
double glassWindowAlpha(GlassStyle style) => switch (style) {
  GlassStyle.fluent => 0.3,
  GlassStyle.tahoe => 0.45,
  GlassStyle.frosted => 0.62,
};

/// Native glass's tokens, for one system and mode, in the system's accent colour.
///
/// `bg` is the system's own window colour, solid: what words and fills are measured against.
/// The window itself is drawn see-through over the system's material (lib/widgets/glass.dart),
/// and the surfaces are white at an opacity over it, so the glass shows through what holds
/// things while words keep the contrast measured here.
UwuColors glassColors(GlassStyle style, Brightness brightness, {Color? accent}) {
  final dark = brightness == Brightness.dark;
  final bg = Color(switch (style) {
    GlassStyle.fluent => dark ? 0xFF202020 : 0xFFF3F3F3,
    GlassStyle.tahoe => dark ? 0xFF1C1C1E : 0xFFF5F5F7,
    GlassStyle.frosted => dark ? 0xFF1E2025 : 0xFFF7F8FA,
  });
  final (lo, hi) = switch (style) {
    GlassStyle.fluent => dark ? (0.05, 0.09) : (0.70, 0.90),
    GlassStyle.tahoe => dark ? (0.08, 0.14) : (0.55, 0.80),
    GlassStyle.frosted => dark ? (0.06, 0.11) : (0.60, 0.85),
  };
  final surface = Colors.white.withValues(alpha: lo);
  final surfaceStrong = Colors.white.withValues(alpha: hi);
  final strong = Color.alphaBlend(surfaceStrong, bg);
  // Words, quieter words, and the edges of what's pressed or typed in, at 3:1 or more (WCAG
  // 1.4.11): Fluent's strong control stroke, Apple's secondary grey, DDE's slate.
  final (ink, muted, border) = switch (style) {
    GlassStyle.fluent => dark ? (0xFFFFFFFF, 0xFFC5C5C5, 0xFF9A9A9A) : (0xFF1B1B1B, 0xFF5C5C5C, 0xFF8A8A8A),
    GlassStyle.tahoe => dark ? (0xFFF5F5F7, 0xFFAEAEB2, 0xFF8E8E93) : (0xFF1D1D1F, 0xFF5E5E63, 0xFF86868B),
    GlassStyle.frosted => dark ? (0xFFE8EBF0, 0xFFAAB2BE, 0xFF8A93A0) : (0xFF1E2330, 0xFF4F5A6B, 0xFF7F8896),
  };
  final inkColor = Color(ink);
  final tint = accent ?? defaultAccent(style);
  final error = dark ? const Color(0xFFFF99A4) : const Color(0xFFC42B1C);
  return UwuColors(
    bg: bg,
    surface: surface,
    surfaceStrong: surfaceStrong,
    border: Color(border),
    edge: switch (style) {
      GlassStyle.fluent => dark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.09),
      GlassStyle.tahoe => dark ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.10),
      GlassStyle.frosted => dark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
    },
    ink: inkColor,
    muted: Color(muted),
    brand: tint,
    brandInk: _readableAccent(tint, [bg, strong], dark),
    brandFill: _accentFill(tint, dark ? 0.32 : 0.20, strong, inkColor),
    brandFillStrong: _accentFill(tint, dark ? 0.48 : 0.32, strong, inkColor),
    onBrand: inkColor,
    ok: dark ? const Color(0xFF6CCB5F) : const Color(0xFF0F7B0F),
    warn: dark ? const Color(0xFFFBBF24) : const Color(0xFFA24B08),
    busy: Color(muted),
    error: error,
    errorFill: _mix(error, 0.14, bg),
    scrim: Colors.black.withValues(alpha: dark ? 0.5 : 0.28),
    glass: true,
    native: style,
  );
}

/// Native glass's font: Windows 11's Segoe UI Variable; on a Mac and on Linux, the system's own.
String? glassFont(GlassStyle style) => style == GlassStyle.fluent ? 'Segoe UI Variable Text' : null;

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
  if (material) {
    scheme = (dynamicScheme ?? ColorScheme.fromSeed(seedColor: const Color(0xFF22A85A), brightness: brightness, contrastLevel: highContrast ? 1.0 : 0.0))
        .copyWith(brightness: brightness);
    colors = materialColors(scheme);
  } else {
    colors = native
        ? glassColors(glassStyle, brightness, accent: accent)
        : uwuAppsColors(brand, brightness, accent: systemAccent ? dynamicScheme?.primary : null);
    scheme = ColorScheme.fromSeed(seedColor: colors.brandInk, brightness: brightness).copyWith(
      primary: colors.brandInk,
      onPrimary: native ? onColor(colors.brandInk) : colors.bg,
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

  final String? font = material ? null : (native ? glassFont(glassStyle) : 'Jua');
  final fallback = native && glassStyle == GlassStyle.fluent ? const ['Segoe UI Variable', 'Segoe UI'] : null;
  final tahoe = native && glassStyle == GlassStyle.tahoe;
  // Corners: a control's, a window's over the page, and a tooltip's. Fluent 2 rounds little and
  // evenly; Tahoe's glass a lot, its buttons into capsules; DDE and COSMIC between the two.
  final control = material ? 14.0 : (native ? switch (glassStyle) { GlassStyle.fluent => 4.0, GlassStyle.tahoe => 10.0, GlassStyle.frosted => 8.0 } : 10.0);
  final window = material ? 28.0 : colors.windowRadius;
  final radius = BorderRadius.circular(control);
  final OutlinedBorder buttonShape = tahoe ? const StadiumBorder() : RoundedRectangleBorder(borderRadius: radius);
  // Windows over the page: nearly solid, so they read wherever they open; the desktop's own
  // dialogs and panels blur what's behind them as well (lib/desktop/adaptive.dart).
  final overlay = native
      ? Color.alphaBlend(colors.surfaceStrong, colors.bg).withValues(alpha: 0.94)
      : Color.alphaBlend(colors.surfaceStrong.withValues(alpha: 0.9), colors.bg);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: font,
    fontFamilyFallback: fallback,
    // Native glass's page is the window, see-through to the system's material: the backdrop
    // under the whole app (lib/widgets/glass.dart) draws it.
    scaffoldBackgroundColor: native ? Colors.transparent : colors.bg,
    // A computer's rows and buttons are closer set than a phone's.
    visualDensity: desktop ? VisualDensity.compact : VisualDensity.standard,
    extensions: [colors],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: colors.ink, displayColor: colors.ink),
    iconTheme: IconThemeData(color: colors.ink, size: 20),
    dividerTheme: DividerThemeData(color: colors.edge, space: 1, thickness: 1),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(color: colors.ink, borderRadius: BorderRadius.circular(native && control < 8 ? control : 8)),
      textStyle: TextStyle(color: colors.bg, fontSize: 12, fontFamily: font),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: colors.surfaceStrong,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: desktop ? 10 : 13),
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
        backgroundColor: material || native ? null : colors.brandFill,
        foregroundColor: material || native ? null : colors.onBrand,
        shape: material || native ? buttonShape : buttonShape.copyWith(side: BorderSide(color: colors.border)),
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: desktop ? 12 : 14),
        textStyle: TextStyle(fontFamily: font, fontSize: 14, fontWeight: material ? FontWeight.w600 : (native ? FontWeight.w500 : FontWeight.w400)),
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.ink,
        backgroundColor: material ? null : colors.surfaceStrong,
        side: BorderSide(color: colors.border),
        shape: buttonShape,
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: desktop ? 10 : 12),
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
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? colors.brandInk : null),
      checkColor: WidgetStatePropertyAll(colors.bg),
      side: BorderSide(color: colors.muted, width: 1.5),
      mouseCursor: WidgetStateMouseCursor.clickable,
    ),
    switchTheme: material || native
        ? null
        : SwitchThemeData(
            trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? colors.brandInk : colors.surfaceStrong),
            thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? colors.bg : colors.muted),
            trackOutlineColor: WidgetStatePropertyAll(colors.border),
          ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.ink,
      contentTextStyle: TextStyle(color: colors.bg, fontFamily: font, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(colors.round(12))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.glass ? overlay : scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(window),
        side: BorderSide(color: colors.edge),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.glass ? overlay : scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(window))),
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
