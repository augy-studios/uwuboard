// The welcome window, "Make it yours" (docs/desktop-features-spec.md §1): the first window of a
// new install, and from the tray's menu after that. Left, a welcome panel in the brand colour;
// right, the choices: start at sign-in, follow the system's light or dark, the theme, and the
// brand colour (or the system's accent). It previews as you pick, and Get started applies
// everything through the app's own settings (ThemeController), so there's one set of settings.
// Closing it any other way changes nothing, but it still counts as seen.
//
// The site is in English only, so there's no language row: the spec's four languages are the
// site's own, and this site has one.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/icons.dart';
import '../theme/theme.dart';
import 'desk.dart';
import 'settings.dart';

/// What's picked in the welcome window.
class WelcomeChoices {
  bool startAtLogin = true;
  bool followSystem = false;
  String mode = 'light';
  String colour = 'classic';
  bool accent = false;
}

class WelcomeApp extends StatefulWidget {
  const WelcomeApp({super.key, required this.done});

  /// Called with the choices on Get started, or null when the window's closed.
  final void Function(WelcomeChoices? choices) done;

  @override
  State<WelcomeApp> createState() {
    return _WelcomeAppState();
  }
}

class _WelcomeAppState extends State<WelcomeApp> with WindowListener {
  final choices = WelcomeChoices();

  /// The computer's own light or dark, kept up to date for "Follow system theme".
  Brightness _systemBrightness = SchedulerBinding.instance.platformDispatcher.platformBrightness;

  @override
  void initState() {
    super.initState();
    // What's set already, filled in.
    final theme = ThemeController.I;
    choices.mode = theme.modePreference;
    choices.colour = theme.colorThemeId;
    final useSystemAccent = DeskSettings.get<bool>('useSystemAccent');
    if (useSystemAccent == null) {
      choices.accent = false;
    } else {
      choices.accent = useSystemAccent;
    }
    final followSystem = DeskSettings.get<bool>('followSystem');
    if (followSystem == null) {
      choices.followSystem = false;
    } else {
      choices.followSystem = followSystem;
    }
    // Start at sign-in: on, unless it was chosen before, in which case as it is now.
    Desktop.startsAtLogin().then((startsAtLogin) {
      if (mounted) {
        setState(() {
          if (DeskSettings.get<bool>('loginChosen') == true) {
            choices.startAtLogin = startsAtLogin;
          } else {
            choices.startAtLogin = true;
          }
        });
      }
    });
    SchedulerBinding.instance.platformDispatcher.onPlatformBrightnessChanged = () {
      if (mounted) {
        setState(() {
          _systemBrightness = SchedulerBinding.instance.platformDispatcher.platformBrightness;
        });
      }
    };
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    widget.done(null);
  }

  /// Light or dark, as the choices so far make it.
  Brightness get _brightness {
    if (choices.followSystem) {
      return _systemBrightness;
    }
    if (resolveMode(choices.mode) == 'dark') {
      return Brightness.dark;
    } else {
      return Brightness.light;
    }
  }

  /// The window: a title strip with Close, then the welcome panel (when it's wide enough) beside
  /// the choices, all in the theme being picked.
  @override
  Widget build(BuildContext context) {
    final brand = colorThemes.firstWhere((colorTheme) {
      return colorTheme.id == choices.colour;
    }).color;
    final theme = buildTheme(look: lookUwuApps, brightness: _brightness, brand: brand, desktop: true);
    bool? disableAnimations = MediaQuery.maybeDisableAnimationsOf(context);
    if (disableAnimations == null) {
      disableAnimations = false;
    }
    final reduceMotion = disableAnimations;
    int themeAnimationMilliseconds;
    if (reduceMotion) {
      themeAnimationMilliseconds = 0;
    } else {
      themeAnimationMilliseconds = 200;
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Make uwuBoard yours',
      theme: theme,
      themeAnimationDuration: Duration(milliseconds: themeAnimationMilliseconds),
      home: Builder(
        builder: (context) {
          final colors = UwuColors.of(context);
          return Scaffold(
            body: Column(
              children: [
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      Expanded(
                        child: DragToMoveArea(
                          child: Container(
                            padding: const EdgeInsets.only(left: 16),
                            alignment: Alignment.centerLeft,
                            child: Text('Make uwuBoard yours', style: TextStyle(color: colors.muted, fontSize: 12)),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () {
                          widget.done(null);
                        },
                        icon: AppIcon('close', size: 16, color: colors.ink),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 760;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (wide) SizedBox(width: constraints.maxWidth / 3, child: _panel(brand)),
                          Expanded(child: _choicesColumn(context, colors)),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The welcome panel on the left: the brand colour fading lighter, two soft circles, the
  /// icon, a greeting and three things the app does.
  Widget _panel(Color brand) {
    const ink = Color(0xFF121815);
    Widget feature(String icon, String text) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            AppIcon(icon, size: 20, color: ink),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: const TextStyle(color: ink, fontSize: 14)),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [brand, Color.lerp(brand, Colors.white, 0.45)!]),
      ),
      child: Stack(
        children: [
          Positioned(top: -40, right: -40, child: _circle(140)),
          Positioned(bottom: -60, left: -50, child: _circle(180)),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.asset('assets/images/icon-512.png', width: 72, height: 72)),
                const SizedBox(height: 18),
                const Text(
                  'Welcome to uwuBoard',
                  style: TextStyle(color: ink, fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text('The Kanban way: drag your tasks from To Do to Done.', style: TextStyle(color: ink, fontSize: 14)),
                const SizedBox(height: 26),
                feature('kanban', 'Boards as columns, or as a Timeline'),
                feature('bell', 'Due cards as desktop notifications'),
                feature('sync', 'Sync with your phone, no account needed'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
    );
  }

  /// The choices on the right: one row each for start at sign-in, follow the system, the theme
  /// and the brand colour, then Get started.
  Widget _choicesColumn(BuildContext context, UwuColors colors) {
    Widget row(String icon, String label, Widget control) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceStrong,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: colors.brandFill, borderRadius: BorderRadius.circular(10)),
              child: Center(child: AppIcon(icon, size: 18, color: colors.onBrand)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: TextStyle(color: colors.ink, fontSize: 14)),
            ),
            control,
          ],
        ),
      );
    }

    // The theme can't be picked while it follows the system.
    ValueChanged<String?>? onModeChanged;
    if (choices.followSystem) {
      onModeChanged = null;
    } else {
      onModeChanged = (value) {
        setState(() {
          if (value == null) {
            choices.mode = 'light';
          } else {
            choices.mode = value;
          }
        });
      };
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Make uwuBoard yours',
            style: TextStyle(color: colors.ink, fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('Choose how the app should look and feel.', style: TextStyle(color: colors.muted, fontSize: 14)),
          const SizedBox(height: 18),
          Expanded(
            child: ListView(
              children: [
                row(
                  'power',
                  'Start when I sign in',
                  Switch(
                    value: choices.startAtLogin,
                    onChanged: (value) {
                      setState(() {
                        choices.startAtLogin = value;
                      });
                    },
                  ),
                ),
                row(
                  'sun',
                  'Follow system theme',
                  Switch(
                    value: choices.followSystem,
                    onChanged: (value) {
                      setState(() {
                        choices.followSystem = value;
                      });
                    },
                  ),
                ),
                row(
                  'moon',
                  'Theme',
                  DropdownButton<String>(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    dropdownMenuItemMouseCursor: WidgetStateMouseCursor.clickable,
                    value: choices.mode,
                    underline: const SizedBox.shrink(),
                    onChanged: onModeChanged,
                    items: const [
                      DropdownMenuItem(value: 'light', child: Text('Light')),
                      DropdownMenuItem(value: 'dark', child: Text('Dark')),
                      DropdownMenuItem(value: 'time', child: Text('Time-based')),
                    ],
                  ),
                ),
                row(
                  'palette',
                  'Brand colour',
                  Semantics(
                    container: true,
                    label: 'Brand colour',
                    child: Wrap(
                      spacing: 6,
                      children: [for (final colorTheme in colorThemes) _swatch(colors, colorTheme.id, colorTheme.label, colorTheme.color), _swatch(colors, 'system', 'System accent', null)],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text('You can change these any time, from Make it yours in the tray’s menu.', style: TextStyle(color: colors.muted, fontSize: 12.5)),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () {
                  widget.done(choices);
                },
                iconAlignment: IconAlignment.end,
                icon: AppIcon('arrow-right', size: 16, color: colors.onBrand),
                label: const Text('Get started'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// One round colour to pick: a brand colour, or (`id` 'system', no `colour`) the system's
  /// accent, drawn as a rainbow. The picked one has a thick ring.
  Widget _swatch(UwuColors colors, String id, String label, Color? colour) {
    bool picked;
    if (id == 'system') {
      picked = choices.accent;
    } else {
      picked = !choices.accent && choices.colour == id;
    }
    Gradient? gradient;
    if (colour == null) {
      gradient = const SweepGradient(colors: [Colors.red, Colors.yellow, Colors.green, Colors.blue, Colors.purple, Colors.red]);
    } else {
      gradient = null;
    }
    Color ringColor;
    double ringWidth;
    if (picked) {
      ringColor = colors.brandInk;
      ringWidth = 3;
    } else {
      ringColor = colors.border;
      ringWidth = 1;
    }
    return Tooltip(
      excludeFromSemantics: true,
      message: label,
      child: Semantics(
        label: label,
        inMutuallyExclusiveGroup: true,
        checked: picked,
        button: true,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          customBorder: const CircleBorder(),
          onTap: () {
            setState(() {
              if (id == 'system') {
                choices.accent = true;
              } else {
                choices.accent = false;
                choices.colour = id;
              }
            });
          },
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colour,
              gradient: gradient,
              border: Border.all(color: ringColor, width: ringWidth),
            ),
          ),
        ),
      ),
    );
  }
}

/// The window set up as the welcome window: about 940 × 660, at least 620 × 560.
Future<void> welcomeWindow() async {
  // From the tray's menu it's the main window, which may be maximised or full screen: resized
  // like that, Windows keeps the maximised frame and the app draws at the wrong size and place,
  // here and again when the boards come back.
  if (await windowManager.isFullScreen()) {
    await windowManager.setFullScreen(false);
  }
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
  }
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
  await windowManager.setResizable(true);
  await windowManager.setMinimumSize(const Size(620, 560));
  await windowManager.setSize(const Size(940, 660));
  await windowManager.center();
  await windowManager.show();
  await windowManager.focus();
}

/// Applies the choices through the app's own settings, and marks the window seen.
Future<void> applyWelcome(WelcomeChoices? choices) async {
  DeskSettings.write({'setupDone': true});
  if (choices == null) {
    return;
  }
  final theme = ThemeController.I;
  if (choices.followSystem) {
    final brightness = SchedulerBinding.instance.platformDispatcher.platformBrightness;
    if (brightness == Brightness.dark) {
      theme.setMode('dark');
    } else {
      theme.setMode('light');
    }
  } else {
    theme.setMode(choices.mode);
  }
  theme.setColorTheme(choices.colour);
  DeskSettings.write({'useSystemAccent': choices.accent, 'followSystem': choices.followSystem, 'loginChosen': true});
  theme.setSystemAccent(choices.accent);
  unawaited(Desktop.setStartAtLogin(choices.startAtLogin));
}
