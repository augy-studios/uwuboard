// Small pieces the screens share: the site's glass panels and round glass buttons, a field's
// label, the avatar, and a card image drawn from its bytes.
import 'dart:ui';

import 'package:flutter/material.dart';

import '../app/state.dart';
import '../data/board.dart';
import '../data/images.dart';
import '../theme/icons.dart';
import '../theme/theme.dart';
import 'glass.dart';

/// The site's .glass-panel: a see-through panel with a bright edge, solid in Material You, and
/// the system's own glass in native glass.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.radius = 18, this.padding, this.strong = false, this.blur = true});

  final Widget child;
  final double radius;
  final EdgeInsets? padding;
  final bool strong;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final style = colors.native;
    final Color fillColor;
    if (strong) {
      fillColor = colors.surfaceStrong;
    } else {
      fillColor = colors.surface;
    }
    // Native glass: the system's own look.
    if (style != null) {
      final borderRadius = BorderRadius.circular(colors.round(radius));
      return NativeGlass(
        style: style,
        radius: borderRadius,
        blur: blur,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: borderRadius,
            border: Border.all(color: colors.edge),
          ),
          child: child,
        ),
      );
    }
    // The site's glass: a soft shadow and, unless asked not to, what's behind it blurred.
    List<BoxShadow>? shadows;
    if (colors.glass) {
      shadows = [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8))];
    } else {
      shadows = null;
    }
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: colors.border),
        boxShadow: shadows,
      ),
      child: child,
    );
    if (!colors.glass || !blur) {
      return box;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: box),
    );
  }
}

/// The site's .glass-btn: a round icon button, labelled for screen readers and with its label
/// on hover (and, in the edge tray, on a long press).
class GlassButton extends StatelessWidget {
  const GlassButton({super.key, required this.icon, required this.label, required this.onPressed, this.danger = false, this.size = 44, this.active = false});

  final String icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final Color fillColor;
    if (active) {
      fillColor = colors.brandFill;
    } else {
      fillColor = colors.surfaceStrong;
    }
    final Color iconColor;
    if (danger) {
      iconColor = colors.error;
    } else if (active) {
      iconColor = colors.onBrand;
    } else {
      iconColor = colors.ink;
    }
    return Tooltip(
      excludeFromSemantics: true,
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: fillColor,
          shape: CircleBorder(side: BorderSide(color: colors.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: AppIcon(icon, size: size * 0.45, color: iconColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small square icon button (the site's .mini-btn).
class MiniButton extends StatelessWidget {
  const MiniButton({super.key, required this.icon, required this.label, required this.onPressed, this.size = 30, this.color});

  final String icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final Color iconColor;
    final givenColor = color;
    if (givenColor != null) {
      iconColor = givenColor;
    } else {
      iconColor = colors.muted;
    }
    return Tooltip(
      excludeFromSemantics: true,
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: AppIcon(icon, size: size * 0.52, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// A form field's label, as the site writes them.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.note});
  final String text;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 12),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: text,
              style: TextStyle(fontSize: 12.5, color: colors.muted, fontWeight: FontWeight.w600),
            ),
            if (note != null)
              TextSpan(
                text: ' $note',
                style: TextStyle(fontSize: 12, color: colors.muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// The error under a form (the site's .form-error).
class FormError extends StatelessWidget {
  const FormError(this.message, {super.key});
  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null || text.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = UwuColors.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: colors.errorFill, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(color: colors.error, fontSize: 13)),
      ),
    );
  }
}

/// The person's avatar: their picture once it's loaded, else their initial ('G' as a guest).
class Avatar extends StatelessWidget {
  const Avatar({super.key, this.size = 34, this.round = true, this.preview});
  final double size;
  final bool round;

  /// A picture just picked, shown before it's saved.
  final LoadedImage? preview;

  /// A picture just picked, else the saved avatar once it has loaded, else the initial; in a
  /// circle, or a rounded square when [round] is off.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final app = AppState.I;
    final initial = Center(
      child: Text(
        app.initial,
        style: TextStyle(fontSize: size * 0.42, color: colors.onBrand, fontWeight: FontWeight.w700),
      ),
    );
    Widget inner = initial;
    final previewImage = preview;
    if (previewImage != null) {
      inner = Image.memory(previewImage.bytes, fit: BoxFit.cover, width: size, height: size);
    } else if (app.signedIn && app.hasAvatar) {
      inner = FutureBuilder<LoadedImage>(
        key: ValueKey(app.avatarVersion),
        future: ImageStore.avatar(),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.bytes.isNotEmpty) {
            return Image.memory(snapshot.data!.bytes, fit: BoxFit.cover, width: size, height: size, gaplessPlayback: true);
          } else {
            return initial;
          }
        },
      );
    }
    final BoxShape shape;
    final BorderRadius? borderRadius;
    if (round) {
      shape = BoxShape.circle;
      borderRadius = null;
    } else {
      shape = BoxShape.rectangle;
      borderRadius = BorderRadius.circular(size * 0.22);
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.brandFillStrong,
        shape: shape,
        borderRadius: borderRadius,
        border: Border.all(color: colors.border),
      ),
      child: inner,
    );
  }
}

/// A card image from its bytes. Never its address: the bytes come through ImageStore.
class CardImage extends StatelessWidget {
  const CardImage(this.image, {super.key, this.fit = BoxFit.cover, this.height, this.width});
  final Json image;
  final BoxFit fit;
  final double? height;
  final double? width;

  /// The picture once its bytes have loaded, a plain box while they load, and "Image
  /// unavailable" when they can't be.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    return FutureBuilder<LoadedImage>(
      key: ValueKey(ImageStore.keyOf(image)),
      future: ImageStore.load(image),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.bytes.isNotEmpty) {
          final imageName = image['name'];
          final String semanticName;
          if (imageName != null) {
            semanticName = '$imageName';
          } else {
            semanticName = '';
          }
          return Image.memory(
            snapshot.data!.bytes,
            fit: fit,
            width: width,
            height: height,
            gaplessPlayback: true,
            semanticLabel: semanticName,
            errorBuilder: (context, error, stackTrace) {
              return _missing(colors);
            },
          );
        }
        if (snapshot.hasError) {
          return _missing(colors);
        }
        return Container(width: width, height: height, color: colors.surfaceStrong);
      },
    );
  }

  Widget _missing(UwuColors colors) {
    return Container(
      width: width,
      height: height,
      color: colors.surfaceStrong,
      alignment: Alignment.center,
      child: Text('Image unavailable', style: TextStyle(fontSize: 11, color: colors.muted)),
    );
  }
}

/// A label chip in its own colour, its words flipping light or dark with it.
class LabelChip extends StatelessWidget {
  const LabelChip({super.key, required this.text, required this.color, this.onRemove, this.small = false});
  final String text;
  final String color;
  final VoidCallback? onRemove;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final parsedHex = parseHex(color);
    final int hex;
    if (parsedHex != null) {
      hex = parsedHex;
    } else {
      hex = 0xccffcc;
    }
    final background = Color(0xFF000000 | hex);
    final Color ink;
    if (isDarkHex(color)) {
      ink = Colors.white;
    } else {
      ink = const Color(0xFF121815);
    }
    // A small chip is tighter all round; one with a remove button leaves little room on its right.
    final double sidePadding;
    final double verticalPadding;
    final double fontSize;
    if (small) {
      sidePadding = 7;
      verticalPadding = 2;
      fontSize = 10.5;
    } else {
      sidePadding = 10;
      verticalPadding = 4;
      fontSize = 12;
    }
    final double rightPadding;
    if (onRemove == null) {
      rightPadding = sidePadding;
    } else {
      rightPadding = 2;
    }
    return Container(
      padding: EdgeInsets.fromLTRB(sidePadding, verticalPadding, rightPadding, verticalPadding),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: background.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(color: ink, fontSize: fontSize),
          ),
          if (onRemove != null)
            InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: AppIcon('close', size: 12, color: ink),
              ),
            ),
        ],
      ),
    );
  }
}
