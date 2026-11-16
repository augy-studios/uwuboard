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
    final colors = UwuColors.of(context);
    final style = colors.native;
    if (style == null) {
      return child;
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final material = ThemeController.I.windowMaterial;
    // The system's own material shows through a see-through window colour; without one, a glow
    // of the app's own.
    final Widget backdrop;
    if (material) {
      backdrop = ColoredBox(color: colors.bg.withValues(alpha: glassWindowAlpha(style)));
    } else {
      backdrop = CustomPaint(painter: _GlowPainter(background: colors.bg, accent: colors.brand, dark: dark, style: style));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: backdrop,
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
  _GlowPainter({required this.background, required this.accent, required this.dark, required this.style});
  final Color background;
  final Color accent;
  final bool dark;
  final GlassStyle style;

  /// How strong the glow is for each look, before dark mode's boost.
  static double _baseStrength(GlassStyle style) {
    switch (style) {
      case GlassStyle.fluent:
        return 0.14;
      case GlassStyle.tahoe:
        return 0.26;
      case GlassStyle.frosted:
        return 0.2;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint();
    backgroundPaint.color = background;
    canvas.drawRect(Offset.zero & size, backgroundPaint);
    final double darkBoost;
    if (dark) {
      darkBoost = 1.25;
    } else {
      darkBoost = 1.0;
    }
    final strength = _baseStrength(style) * darkBoost;
    final hsl = HSLColor.fromColor(accent);

    /// The accent turned round the colour wheel by [turn] degrees, a little less saturated.
    Color shiftedHue(double turn) {
      return hsl.withHue((hsl.hue + turn) % 360).withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0)).toColor();
    }

    final side = size.longestSide;

    /// A soft round light in [colour], fading out from [center] to [radius].
    void glow(Offset center, double radius, Color colour, double alpha) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final glowPaint = Paint();
      glowPaint.shader = RadialGradient(
        colors: [colour.withValues(alpha: alpha), colour.withValues(alpha: 0)],
      ).createShader(rect);
      canvas.drawRect(Offset.zero & size, glowPaint);
    }

    glow(Offset(size.width * 0.08, size.height * 0.02), side * 0.55, accent, strength);
    glow(Offset(size.width * 0.95, size.height * 0.35), side * 0.45, shiftedHue(48), strength * 0.8);
    glow(Offset(size.width * 0.45, size.height * 1.05), side * 0.6, shiftedHue(-52), strength * 0.75);
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) {
    return oldDelegate.background != background || oldDelegate.accent != accent || oldDelegate.dark != dark || oldDelegate.style != style;
  }
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
  static double sigmaOf(GlassStyle style) {
    switch (style) {
      case GlassStyle.fluent:
        return 30;
      case GlassStyle.tahoe:
        return 20;
      case GlassStyle.frosted:
        return 24;
    }
  }

  /// The filter for what's behind a panel: a blur, and for Fluent and Tahoe a boost in
  /// saturation first.
  static ui.ImageFilter filterOf(GlassStyle style) {
    final sigma = sigmaOf(style);
    final blur = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror);
    if (style == GlassStyle.frosted) {
      return blur;
    }
    // Saturation, as a colour matrix, then the blur.
    final double saturation;
    if (style == GlassStyle.tahoe) {
      saturation = 1.5;
    } else {
      saturation = 1.25;
    }
    // How much red, green and blue each count towards brightness.
    const redWeight = 0.2126;
    const greenWeight = 0.7152;
    const blueWeight = 0.0722;
    final matrix = <double>[
      redWeight * (1 - saturation) + saturation, greenWeight * (1 - saturation), blueWeight * (1 - saturation), 0, 0, //
      redWeight * (1 - saturation), greenWeight * (1 - saturation) + saturation, blueWeight * (1 - saturation), 0, 0,
      redWeight * (1 - saturation), greenWeight * (1 - saturation), blueWeight * (1 - saturation) + saturation, 0, 0,
      0, 0, 0, 1, 0,
    ];
    return ui.ImageFilter.compose(outer: blur, inner: ColorFilter.matrix(matrix));
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
    CustomPainter? shadowPainter;
    if (shadow) {
      shadowPainter = _OuterShadow(radius: radius, style: style, dark: dark);
    } else {
      shadowPainter = null;
    }
    return CustomPaint(
      painter: shadowPainter,
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

  Color _white(double alpha) {
    return Colors.white.withValues(alpha: alpha);
  }

  Color _black(double alpha) {
    return Colors.black.withValues(alpha: alpha);
  }

  /// The rim's gradient colours, from its start to its end, for this look and brightness.
  List<Color> _rimColours() {
    switch (style) {
      case GlassStyle.fluent:
        if (dark) {
          return [_white(0.12), _white(0.04)];
        } else {
          return [_white(0.9), _black(0.06)];
        }
      case GlassStyle.tahoe:
        if (dark) {
          return [_white(0.42), _white(0.07), _white(0.24)];
        } else {
          return [_white(0.95), _white(0.35), _white(0.8)];
        }
      case GlassStyle.frosted:
        if (dark) {
          return [_white(0.2), _white(0.06)];
        } else {
          return [_white(0.85), _white(0.4)];
        }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final roundedRect = radius.toRRect(rect).deflate(1.5);
    final colours = _rimColours();
    final tahoe = style == GlassStyle.tahoe;
    // Tahoe's rim is a little thicker and its light runs corner to corner; the others' top to
    // bottom.
    final double strokeWidth;
    final Alignment gradientBegin;
    final Alignment gradientEnd;
    if (tahoe) {
      strokeWidth = 1.4;
      gradientBegin = Alignment.topLeft;
      gradientEnd = Alignment.bottomRight;
    } else {
      strokeWidth = 1;
      gradientBegin = Alignment.topCenter;
      gradientEnd = Alignment.bottomCenter;
    }
    final rimPaint = Paint();
    rimPaint.style = PaintingStyle.stroke;
    rimPaint.strokeWidth = strokeWidth;
    rimPaint.shader = LinearGradient(
      begin: gradientBegin,
      end: gradientEnd,
      colors: colours,
    ).createShader(rect);
    canvas.drawRRect(roundedRect, rimPaint);
    // Tahoe's sheen: a light fading down over the top half.
    if (tahoe) {
      canvas.save();
      canvas.clipRRect(radius.toRRect(rect));
      final double sheenAlpha;
      if (dark) {
        sheenAlpha = 0.07;
      } else {
        sheenAlpha = 0.28;
      }
      final sheenPaint = Paint();
      sheenPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_white(sheenAlpha), _white(0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.5));
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.5), sheenPaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Rim oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.style != style || oldDelegate.dark != dark;
  }
}

/// A panel's shadow, drawn only outside its shape.
class _OuterShadow extends CustomPainter {
  _OuterShadow({required this.radius, required this.style, required this.dark});
  final BorderRadius radius;
  final GlassStyle style;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final roundedRect = radius.toRRect(Offset.zero & size);
    // How dark, how soft and how far down the shadow is, for each look.
    final double alpha;
    final double blur;
    final double deltaY;
    switch (style) {
      case GlassStyle.fluent:
        if (dark) {
          alpha = 0.28;
        } else {
          alpha = 0.10;
        }
        blur = 8.0;
        deltaY = 2.0;
      case GlassStyle.tahoe:
        if (dark) {
          alpha = 0.4;
        } else {
          alpha = 0.14;
        }
        blur = 22.0;
        deltaY = 8.0;
      case GlassStyle.frosted:
        if (dark) {
          alpha = 0.32;
        } else {
          alpha = 0.12;
        }
        blur = 14.0;
        deltaY = 4.0;
    }
    canvas.save();
    // Everything round the panel, but not the panel itself.
    final outerPath = Path();
    outerPath.addRect((Offset.zero & size).inflate(blur * 3 + deltaY));
    final shapePath = Path();
    shapePath.addRRect(roundedRect);
    canvas.clipPath(
      Path.combine(PathOperation.difference, outerPath, shapePath),
    );
    final shadowPaint = Paint();
    shadowPaint.color = Colors.black.withValues(alpha: alpha);
    shadowPaint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2);
    canvas.drawRRect(
      roundedRect.shift(Offset(0, deltaY)),
      shadowPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadow oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.style != style || oldDelegate.dark != dark;
  }
}

/// A picture of the app laid on its page colour: native glass's window is see-through, so a
/// screenshot of it would be too (and black once it's a JPEG).
Future<ui.Image> flattenOnto(ui.Image image, Color background) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(background.withValues(alpha: 1), BlendMode.src);
  canvas.drawImage(image, Offset.zero, Paint());
  final flat = await recorder.endRecording().toImage(image.width, image.height);
  image.dispose();
  return flat;
}
