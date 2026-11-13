// Small pieces the screens share: the site's glass panels and round glass buttons, a field's
// label, the avatar, and a card image drawn from its bytes.
import 'dart:ui';

import 'package:flutter/material.dart';

import '../app/state.dart';
import '../data/board.dart';
import '../data/images.dart';
import '../theme/icons.dart';
import '../theme/theme.dart';

/// The site's .glass-panel: a see-through panel with a bright edge, solid in Material You.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.radius = 18, this.padding, this.strong = false, this.blur = true});

  final Widget child;
  final double radius;
  final EdgeInsets? padding;
  final bool strong;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: strong ? c.surfaceStrong : c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.border),
        boxShadow: c.glass ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8))] : null,
      ),
      child: child,
    );
    if (!c.glass || !blur) return box;
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
    final c = UwuColors.of(context);
    return Tooltip(
      excludeFromSemantics: true,
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: active ? c.brandFill : c.surfaceStrong,
          shape: CircleBorder(side: BorderSide(color: c.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: AppIcon(icon, size: size * 0.45, color: danger ? c.error : (active ? c.onBrand : c.ink)),
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
    final c = UwuColors.of(context);
    return Tooltip(
      excludeFromSemantics: true,
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: AppIcon(icon, size: size * 0.52, color: color ?? c.muted),
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
    final c = UwuColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 12),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: text,
              style: TextStyle(fontSize: 12.5, color: c.muted, fontWeight: FontWeight.w600),
            ),
            if (note != null)
              TextSpan(
                text: ' $note',
                style: TextStyle(fontSize: 12, color: c.muted),
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
    final m = message;
    if (m == null || m.isEmpty) return const SizedBox.shrink();
    final c = UwuColors.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: c.errorFill, borderRadius: BorderRadius.circular(8)),
        child: Text(m, style: TextStyle(color: c.error, fontSize: 13)),
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

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final s = AppState.I;
    final initial = Center(
      child: Text(
        s.initial,
        style: TextStyle(fontSize: size * 0.42, color: c.onBrand, fontWeight: FontWeight.w700),
      ),
    );
    Widget inner = initial;
    if (preview != null) {
      inner = Image.memory(preview!.bytes, fit: BoxFit.cover, width: size, height: size);
    } else if (s.signedIn && s.hasAvatar) {
      inner = FutureBuilder<LoadedImage>(
        key: ValueKey(s.avatarVersion),
        future: ImageStore.avatar(),
        builder: (context, snap) => snap.hasData && snap.data!.bytes.isNotEmpty
            ? Image.memory(snap.data!.bytes, fit: BoxFit.cover, width: size, height: size, gaplessPlayback: true)
            : initial,
      );
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.brandFillStrong,
        shape: round ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: round ? null : BorderRadius.circular(size * 0.22),
        border: Border.all(color: c.border),
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

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    return FutureBuilder<LoadedImage>(
      key: ValueKey(ImageStore.keyOf(image)),
      future: ImageStore.load(image),
      builder: (context, snap) {
        if (snap.hasData && snap.data!.bytes.isNotEmpty) {
          return Image.memory(
            snap.data!.bytes,
            fit: fit,
            width: width,
            height: height,
            gaplessPlayback: true,
            semanticLabel: '${image['name'] ?? ''}',
            errorBuilder: (_, _, _) => _missing(c),
          );
        }
        if (snap.hasError) return _missing(c);
        return Container(width: width, height: height, color: c.surfaceStrong);
      },
    );
  }

  Widget _missing(UwuColors c) => Container(
    width: width,
    height: height,
    color: c.surfaceStrong,
    alignment: Alignment.center,
    child: Text('Image unavailable', style: TextStyle(fontSize: 11, color: c.muted)),
  );
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
    final hex = parseHex(color) ?? 0xccffcc;
    final bg = Color(0xFF000000 | hex);
    final ink = isDarkHex(color) ? Colors.white : const Color(0xFF121815);
    return Container(
      padding: EdgeInsets.fromLTRB(small ? 7 : 10, small ? 2 : 4, onRemove == null ? (small ? 7 : 10) : 2, small ? 2 : 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(color: ink, fontSize: small ? 10.5 : 12),
          ),
          if (onRemove != null)
            InkWell(
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
