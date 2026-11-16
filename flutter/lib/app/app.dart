// The app's root: the theme (the device's Material You palette when there is one, or the
// desktop's accent in native glass), the navigator and messenger keys, the sign-in screen or the
// boards, and the desktop's chrome round all of it where it applies, on native glass's backdrop.
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import '../desktop/adaptive.dart';
import '../features/auth/auth_screen.dart';
import '../features/bug/bug_report.dart';
import '../features/update/update_bar.dart';
import '../theme/theme.dart';
import '../widgets/glass.dart';
import '../widgets/sheet.dart';
import 'env.dart';
import 'home.dart';
import 'nav.dart';
import 'state.dart';

/// Wraps the app on the desktop: the title bar, the command bar and the shortcuts
/// (lib/desktop/chrome.dart). Set by the desktop's start-up.
Widget Function(BuildContext context, Widget child)? desktopChrome;

/// For the Playwright suite: a device palette, as Android 12+ would give one.
ColorScheme? testLightDynamic;
ColorScheme? testDarkDynamic;

/// The desktop's system accent, as a colour scheme, when "Use system accent colour" is on.
ColorScheme? Function(Brightness brightness)? desktopAccentScheme;

/// The desktop's system accent as it is, for native glass.
Color? Function()? desktopAccent;

class UwuBoardApp extends StatefulWidget {
  const UwuBoardApp({super.key});

  @override
  State<UwuBoardApp> createState() => _UwuBoardAppState();
}

class _UwuBoardAppState extends State<UwuBoardApp> {
  @override
  void initState() {
    super.initState();
    // A window opening or closing changes what's on screen, for the tours.
    AppSheet.open.addListener(AppState.I.pageChanged);
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (deviceLight, deviceDark) {
        final lightDynamic = testLightDynamic ?? deviceLight;
        final darkDynamic = testDarkDynamic ?? deviceDark;
        ThemeController.I.setHasDynamic(lightDynamic != null && Env.android);
        lightDynamicScheme = lightDynamic?.harmonized();
        darkDynamicScheme = darkDynamic?.harmonized();
        return ListenableBuilder(
          listenable: Listenable.merge([ThemeController.I, AppState.I]),
          builder: (context, _) {
            final t = ThemeController.I;
            final brand = t.colorTheme.color;
            ThemeData make(Brightness b, {bool hc = false}) {
              final ColorScheme? dyn = t.isMaterial
                  ? (b == Brightness.dark ? darkDynamic : lightDynamic)?.harmonized()
                  : (t.systemAccent && !t.isNative ? desktopAccentScheme?.call(b) : null);
              return buildTheme(
                look: t.look,
                brightness: b,
                brand: brand,
                dynamicScheme: dyn,
                systemAccent: t.systemAccent,
                highContrast: hc,
                desktop: Env.desktop,
                glassStyle: t.glassStyle,
                accent: t.isNative ? desktopAccent?.call() : null,
              );
            }

            final b = t.brightness;
            return MaterialApp(
              title: 'uwuBoard',
              debugShowCheckedModeBanner: false,
              navigatorKey: AppNav.navigatorKey,
              scaffoldMessengerKey: AppNav.messengerKey,
              scrollBehavior: const AppScrollBehavior(),
              theme: make(b),
              highContrastTheme: make(b, hc: true),
              themeAnimationDuration: const Duration(milliseconds: 250),
              builder: (context, child) {
                // Text grows with the device's setting, up to twice, so layouts hold.
                final mq = MediaQuery.of(context);
                Widget app = MediaQuery(
                  data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 1, maxScaleFactor: 2)),
                  // Fills what it's given, as the navigator did on its own. The desktop's title bar
                  // puts the app in a Column, whose width is loose: sized by its children, the
                  // Stack would be as wide as the hidden bar's SizedBox.shrink, 0, and the window
                  // black (1.0.2).
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(child: RepaintBoundary(key: AppNav.repaintKey, child: child ?? const SizedBox.shrink())),
                      // A bug report's Screenshot a page: outside what's taken, so not in the picture.
                      ValueListenableBuilder<bool>(
                        valueListenable: BugShot.shooting,
                        builder: (context, shooting, _) => shooting ? const BugShotBar() : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                );
                final chrome = desktopChrome;
                if (chrome != null) app = chrome(context, app);
                // Native glass: the window under all of it, title bar included.
                return GlassBackdrop(child: app);
              },
              home: AppState.I.shown ? const HomeScreen() : const AuthScreen(),
            );
          },
        );
      },
    );
  }
}
