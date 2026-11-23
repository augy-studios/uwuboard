// What a computer does differently from a phone, for the shared widgets
// (docs/flutter-desktop-app-spec.md §2.4): sheets as centred dialogs or a slide-over panel
// from the right, right-click menus, hover highlights with a pointer cursor, and scrolling
// without Android's stretch.
import 'dart:ui';

import 'package:flutter/material.dart';

import '../app/env.dart';
import '../app/nav.dart';
import '../theme/icons.dart';
import '../theme/theme.dart';
import '../widgets/glass.dart';
import '../widgets/sheet.dart';

/// Shows a sheet the desktop way: a drawer slides in from the right, anything else is a dialog
/// in the middle that fades and grows in. With native glass the panel is see-through glass.
Future<T?> showDesktopSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  required SheetKind kind,
  required double width,
  bool dismissible = true,
}) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  int transitionMilliseconds;
  if (reduceMotion) {
    transitionMilliseconds = 0;
  } else {
    transitionMilliseconds = 180;
  }
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: dismissible,
    barrierLabel: 'Close',
    barrierColor: UwuColors.of(context).scrim,
    transitionDuration: Duration(milliseconds: transitionMilliseconds),
    pageBuilder: (context, animation, secondaryAnimation) {
      final colors = UwuColors.of(context);
      final size = MediaQuery.sizeOf(context);
      final style = colors.native;
      BorderRadius radius;
      if (kind == SheetKind.drawer) {
        radius = BorderRadius.zero;
      } else {
        radius = BorderRadius.circular(colors.windowRadius);
      }
      // Native glass: Acrylic, or the system's own glass, over what it opens on.
      Color? panelColor;
      if (style == null) {
        panelColor = Theme.of(context).dialogTheme.backgroundColor;
      } else {
        panelColor = Color.alphaBlend(colors.surfaceStrong, colors.background).withValues(alpha: 0.8);
      }
      ShapeBorder panelShape;
      if (kind == SheetKind.drawer) {
        panelShape = Border(left: BorderSide(color: colors.edge));
      } else {
        panelShape = RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.edge),
        );
      }
      double panelElevation;
      if (style == null) {
        panelElevation = 12;
      } else {
        panelElevation = 0;
      }
      Widget panel = Material(
        color: panelColor,
        shape: panelShape,
        clipBehavior: Clip.antiAlias,
        elevation: panelElevation,
        child: builder(context),
      );
      if (style != null) {
        panel = NativeGlass(style: style, radius: radius, child: panel);
      }
      if (kind == SheetKind.drawer) {
        // The drawer is `width` wide, kept between 320 and the window less 60; the whole window
        // when that's too narrow.
        double drawerWidth;
        if (size.width - 60 < 320) {
          drawerWidth = size.width;
        } else {
          drawerWidth = width.clamp(320, size.width - 60);
        }
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: drawerWidth,
            height: double.infinity,
            child: SafeArea(left: false, child: panel),
          ),
        );
      }
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width, maxHeight: size.height * 0.9),
              child: panel,
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      if (kind == SheetKind.drawer) {
        return SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(curved),
          child: child,
        );
      }
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

/// One line of a right-click menu.
class MenuAction {
  const MenuAction(this.label, this.onTap, {this.icon, this.danger = false, this.enabled = true});
  final String label;
  final VoidCallback onTap;
  final String? icon;
  final bool danger;
  final bool enabled;
}

/// Opens a right-click menu of `actions` at `position` (a place in the window) and runs the
/// one picked, if any.
Future<void> showContextMenu(BuildContext context, Offset position, List<MenuAction> actions) async {
  if (actions.isEmpty) {
    return;
  }
  final colors = UwuColors.of(context);
  // The menu opens in the navigator's overlay, which starts below the desktop's title bar, so the
  // pointer's place in the window is turned into a place in that overlay.
  OverlayState? overlayState;
  final navigatorState = AppNavigation.navigatorKey.currentState;
  if (navigatorState != null) {
    overlayState = navigatorState.overlay;
  }
  if (overlayState == null) {
    overlayState = Overlay.of(context);
  }
  final overlay = overlayState.context.findRenderObject() as RenderBox;
  final pointInOverlay = overlay.globalToLocal(position);

  /// A dangerous action's words and icon are in the error colour.
  Color colorFor(MenuAction action) {
    if (action.danger) {
      return colors.error;
    } else {
      return colors.ink;
    }
  }

  final pickedIndex = await showMenu<int>(
    context: context,
    useRootNavigator: true,
    position: RelativeRect.fromRect(pointInOverlay & const Size(1, 1), Offset.zero & overlay.size),
    color: Color.alphaBlend(colors.surfaceStrong, colors.background),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(colors.round(10)),
      side: BorderSide(color: colors.edge),
    ),
    items: [
      for (var index = 0; index < actions.length; index = index + 1)
        PopupMenuItem<int>(
          value: index,
          enabled: actions[index].enabled,
          height: 36,
          child: Row(
            children: [
              if (actions[index].icon != null) ...[AppIcon(actions[index].icon!, size: 16, color: colorFor(actions[index])), const SizedBox(width: 10)],
              Text(actions[index].label, style: TextStyle(fontSize: 13, color: colorFor(actions[index]))),
            ],
          ),
        ),
    ],
  );
  if (pickedIndex != null) {
    actions[pickedIndex].onTap();
  }
}

/// Wraps something that can be right-clicked (or, on a phone, pressed and held). `actions` is
/// asked for as the menu opens, so it says what's true then.
class ContextMenuRegion extends StatelessWidget {
  const ContextMenuRegion({super.key, required this.actions, required this.child, this.longPress = false});

  final List<MenuAction> Function() actions;
  final Widget child;

  /// Also on a long press: off where a long press already means something (dragging a card).
  final bool longPress;

  @override
  Widget build(BuildContext context) {
    GestureLongPressStartCallback? onLongPressStart;
    if (longPress) {
      onLongPressStart = (details) {
        showContextMenu(context, details.globalPosition, actions());
      };
    } else {
      onLongPressStart = null;
    }
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapUp: (details) {
        showContextMenu(context, details.globalPosition, actions());
      },
      onLongPressStart: onLongPressStart,
      child: child,
    );
  }
}

/// A pointer cursor and a soft highlight under the mouse, for anything that can be clicked.
class Hoverable extends StatefulWidget {
  const Hoverable({super.key, required this.child, this.onTap, this.radius = 10, this.selected = false, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final bool selected;
  final EdgeInsets? padding;

  @override
  State<Hoverable> createState() {
    return _HoverableState();
  }
}

class _HoverableState extends State<Hoverable> {
  /// True while the mouse is over it.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    Color fill;
    if (widget.selected) {
      fill = colors.brandFillStrong;
    } else if (_hovered) {
      fill = colors.surfaceStrong;
    } else {
      fill = Colors.transparent;
    }
    MouseCursor cursor;
    if (widget.onTap == null) {
      cursor = MouseCursor.defer;
    } else {
      cursor = SystemMouseCursors.click;
    }
    return MouseRegion(
      cursor: cursor,
      onEnter: (event) {
        setState(() {
          _hovered = true;
        });
      },
      onExit: (event) {
        setState(() {
          _hovered = false;
        });
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: widget.padding,
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(widget.radius)),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Scrolling as a computer does it: no stretch or glow at the ends, a scrollbar that stays, and
/// dragging with a mouse as well as a finger (the board's columns are dragged sideways).
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices {
    return {...super.dragDevices, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus};
  }

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    if (Environment.desktop) {
      return child;
    } else {
      return super.buildOverscrollIndicator(context, child, details);
    }
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    if (Environment.desktop) {
      return const ClampingScrollPhysics();
    } else {
      return super.getScrollPhysics(context);
    }
  }
}
