// Native glass, the desktop's second look (lib/theme/theme.dart): what draws it.
//
//   GlassBackdrop   under the whole window: the window's colour, see-through to the system's
//                   own material where the runner put one there (Mica on Windows 11, the
//                   desktop through an NSVisualEffectView on a Mac, the compositor's blur on
//                   DDE and KDE), else a frosted glow of its own for the panels to frost.
//   NativeGlass     a panel of glass: what's behind it blurred, its colour brightened, a fine
//                   bright rim and a soft shadow round it, as each system draws its own.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final style = c.native;
    if (style == null) return child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final material = ThemeController.I.windowMaterial;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: material
                ? ColoredBox(color: c.bg.withValues(alpha: glassWindowAlpha(style)))
                : CustomPaint(painter: _GlowPainter(bg: c.bg, accent: c.brand, dark: dark, style: style)),
          ),
        ),
        child,
      ],
    );
  }
}

/// Where the system gives no material: the window colour with soft light in the accent and its
/// neighbours, the way a wallpaper looks through Mica or a Mac's glass. Fluent's is the faintest,
/// as Mica is; Tahoe's the richest.
class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.bg, required this.accent, required this.dark, required this.style});
  final Color bg;
  final Color accent;
  final bool dark;
  final GlassStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final strength = switch (style) {
          GlassStyle.fluent => 0.14,
          GlassStyle.tahoe => 0.26,
          GlassStyle.frosted => 0.2,
        } *
        (dark ? 1.25 : 1.0);
    final hsl = HSLColor.fromColor(accent);
    Color hue(double turn) => hsl.withHue((hsl.hue + turn) % 360).withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0)).toColor();
    final side = size.longestSide;
    void glow(Offset at, double r, Color colour, double a) {
      final rect = Rect.fromCircle(center: at, radius: r);
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: [colour.withValues(alpha: a), colour.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }

    glow(Offset(size.width * 0.08, size.height * 0.02), side * 0.55, accent, strength);
    glow(Offset(size.width * 0.95, size.height * 0.35), side * 0.45, hue(48), strength * 0.8);
    glow(Offset(size.width * 0.45, size.height * 1.05), side * 0.6, hue(-52), strength * 0.75);
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.bg != bg || old.accent != accent || old.dark != dark || old.style != style;
}

/// A panel of native glass round `child`, which brings its own fill and edge. What's behind it
/// is blurred and, as Acrylic and Apple's materials do, a little more saturated; a rim of light
/// runs round the inside of its edge, and a shadow round the outside only, so it never greys
/// the see-through fill.
class NativeGlass extends StatelessWidget {
  const NativeGlass({super.key, required this.style, required this.radius, required this.child, this.blur = true, this.shadow = true});

  final GlassStyle style;
  final BorderRadius radius;
  final Widget child;
  final bool blur;
  final bool shadow;

  /// How far what's behind is blurred: Acrylic's is the strongest.
  static double sigmaOf(GlassStyle style) => switch (style) {
    GlassStyle.fluent => 30,
    GlassStyle.tahoe => 20,
    GlassStyle.frosted => 24,
  };

  static ui.ImageFilter filterOf(GlassStyle style) {
    final sigma = sigmaOf(style);
    final blur = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror);
    if (style == GlassStyle.frosted) return blur;
    // Saturation, as a colour matrix, then the blur.
    final s = style == GlassStyle.tahoe ? 1.5 : 1.25;
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final m = <double>[
      r * (1 - s) + s, g * (1 - s), b * (1 - s), 0, 0, //
      r * (1 - s), g * (1 - s) + s, b * (1 - s), 0, 0,
      r * (1 - s), g * (1 - s), b * (1 - s) + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
    return ui.ImageFilter.compose(outer: blur, inner: ColorFilter.matrix(m));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget body = child;
    if (blur) {
      body = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(filter: filterOf(style), child: body),
      );
    }
    return CustomPaint(
      painter: shadow ? _OuterShadow(radius: radius, style: style, dark: dark) : null,
      foregroundPainter: _Rim(radius: radius, style: style, dark: dark),
      child: body,
    );
  }
}

/// The light along the inside of a panel's edge: Fluent's even and faint, darker at the foot in
/// light mode; Tahoe's bright at the top left and the bottom right, as light catches curved
/// glass, with a sheen across its top; DDE and COSMIC's a plain frost.
class _Rim extends CustomPainter {
  _Rim({required this.radius, required this.style, required this.dark});
  final BorderRadius radius;
  final GlassStyle style;
  final bool dark;

  Color _w(double a) => Colors.white.withValues(alpha: a);
  Color _k(double a) => Colors.black.withValues(alpha: a);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(1.5);
    final colours = switch (style) {
      GlassStyle.fluent => dark ? [_w(0.12), _w(0.04)] : [_w(0.9), _k(0.06)],
      GlassStyle.tahoe => dark ? [_w(0.42), _w(0.07), _w(0.24)] : [_w(0.95), _w(0.35), _w(0.8)],
      GlassStyle.frosted => dark ? [_w(0.2), _w(0.06)] : [_w(0.85), _w(0.4)],
    };
    final tahoe = style == GlassStyle.tahoe;
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = tahoe ? 1.4 : 1
        ..shader = LinearGradient(
          begin: tahoe ? Alignment.topLeft : Alignment.topCenter,
          end: tahoe ? Alignment.bottomRight : Alignment.bottomCenter,
          colors: colours,
        ).createShader(rect),
    );
    if (tahoe) {
      canvas.save();
      canvas.clipRRect(radius.toRRect(rect));
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height * 0.5),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_w(dark ? 0.07 : 0.28), _w(0)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.5)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Rim old) => old.radius != radius || old.style != style || old.dark != dark;
}

/// A panel's shadow, drawn only outside its shape.
class _OuterShadow extends CustomPainter {
  _OuterShadow({required this.radius, required this.style, required this.dark});
  final BorderRadius radius;
  final GlassStyle style;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = radius.toRRect(Offset.zero & size);
    final (alpha, blur, dy) = switch (style) {
      GlassStyle.fluent => (dark ? 0.28 : 0.10, 8.0, 2.0),
      GlassStyle.tahoe => (dark ? 0.4 : 0.14, 22.0, 8.0),
      GlassStyle.frosted => (dark ? 0.32 : 0.12, 14.0, 4.0),
    };
    canvas.save();
    canvas.clipPath(
      Path.combine(PathOperation.difference, Path()..addRect((Offset.zero & size).inflate(blur * 3 + dy)), Path()..addRRect(rrect)),
    );
    canvas.drawRRect(
      rrect.shift(Offset(0, dy)),
      Paint()
        ..color = Colors.black.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadow old) => old.radius != radius || old.style != style || old.dark != dark;
}

/// A picture of the app laid on its page colour: native glass's window is see-through, so a
/// screenshot of it would be too (and black once it's a JPEG).
Future<ui.Image> flattenOnto(ui.Image image, Color bg) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(bg.withValues(alpha: 1), BlendMode.src);
  canvas.drawImage(image, Offset.zero, Paint());
  final flat = await recorder.endRecording().toImage(image.width, image.height);
  image.dispose();
  return flat;
}
