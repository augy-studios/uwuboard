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
  State<UwuBoardApp> createState() {
    return _UwuBoardAppState();
  }
}

class _UwuBoardAppState extends State<UwuBoardApp> {
  @override
  void initState() {
    super.initState();
    // A window opening or closing changes what's on screen, for the tours.
    AppSheet.open.addListener(AppState.instance.pageChanged);
  }

  /// Builds the whole app. The device's own palette (Material You on Android 12+) is read
  /// first, then the app rebuilds whenever the theme settings or the signed-in state change.
  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (deviceLight, deviceDark) {
        // A test palette wins over the device's, when a test set one.
        final testLight = testLightDynamic;
        final ColorScheme? lightDynamic;
        if (testLight != null) {
          lightDynamic = testLight;
        } else {
          lightDynamic = deviceLight;
        }
        final testDark = testDarkDynamic;
        final ColorScheme? darkDynamic;
        if (testDark != null) {
          darkDynamic = testDark;
        } else {
          darkDynamic = deviceDark;
        }
        ThemeController.instance.setHasDynamic(lightDynamic != null && Environment.android);
        if (lightDynamic != null) {
          lightDynamicScheme = lightDynamic.harmonized();
        } else {
          lightDynamicScheme = null;
        }
        if (darkDynamic != null) {
          darkDynamicScheme = darkDynamic.harmonized();
        } else {
          darkDynamicScheme = null;
        }
        return ListenableBuilder(
          listenable: Listenable.merge([ThemeController.instance, AppState.instance]),
          builder: (context, listenableChild) {
            final themeController = ThemeController.instance;
            final brand = themeController.colorTheme.color;

            /// Makes the app's theme for one brightness, with the device's palette on
            /// Material, or the desktop's accent when "Use system accent colour" is on.
            ThemeData makeTheme(Brightness brightness, {bool highContrast = false}) {
              ColorScheme? dynamicScheme;
              if (themeController.isMaterial) {
                ColorScheme? deviceScheme;
                if (brightness == Brightness.dark) {
                  deviceScheme = darkDynamic;
                } else {
                  deviceScheme = lightDynamic;
                }
                if (deviceScheme != null) {
                  dynamicScheme = deviceScheme.harmonized();
                } else {
                  dynamicScheme = null;
                }
              } else {
                if (themeController.systemAccent && !themeController.isNative) {
                  final accentSchemeFor = desktopAccentScheme;
                  if (accentSchemeFor != null) {
                    dynamicScheme = accentSchemeFor(brightness);
                  } else {
                    dynamicScheme = null;
                  }
                } else {
                  dynamicScheme = null;
                }
              }
              Color? nativeAccent;
              if (themeController.isNative) {
                final readAccent = desktopAccent;
                if (readAccent != null) {
                  nativeAccent = readAccent();
                } else {
                  nativeAccent = null;
                }
              } else {
                nativeAccent = null;
              }
              return buildTheme(
                look: themeController.look,
                brightness: brightness,
                brand: brand,
                dynamicScheme: dynamicScheme,
                systemAccent: themeController.systemAccent,
                highContrast: highContrast,
                desktop: Environment.desktop,
                glassStyle: themeController.glassStyle,
                accent: nativeAccent,
              );
            }

            final brightness = themeController.brightness;
            final lightTheme = makeTheme(brightness);
            final highContrastTheme = makeTheme(brightness, highContrast: true);
            // Signed in (or using it without an account): the boards. Otherwise the sign-in screen.
            final Widget homeScreen;
            if (AppState.instance.shown) {
              homeScreen = const HomeScreen();
            } else {
              homeScreen = const AuthScreen();
            }
            return MaterialApp(
              title: 'uwuBoard',
              debugShowCheckedModeBanner: false,
              navigatorKey: AppNavigation.navigatorKey,
              scaffoldMessengerKey: AppNavigation.messengerKey,
              scrollBehavior: const AppScrollBehavior(),
              theme: lightTheme,
              highContrastTheme: highContrastTheme,
              themeAnimationDuration: const Duration(milliseconds: 250),
              builder: (context, child) {
                // Text grows with the device's setting, up to twice, so layouts hold.
                final mediaQuery = MediaQuery.of(context);
                final Widget page;
                if (child != null) {
                  page = child;
                } else {
                  page = const SizedBox.shrink();
                }
                Widget app = MediaQuery(
                  data: mediaQuery.copyWith(textScaler: mediaQuery.textScaler.clamp(minScaleFactor: 1, maxScaleFactor: 2)),
                  // Fills what it's given, as the navigator did on its own. The desktop's title bar
                  // puts the app in a Column, whose width is loose: sized by its children, the
                  // Stack would be as wide as the hidden bar's SizedBox.shrink, 0, and the window
                  // black (1.0.2).
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(child: RepaintBoundary(key: AppNavigation.repaintKey, child: page)),
                      // A bug report's Screenshot a page: outside what's taken, so not in the picture.
                      ValueListenableBuilder<bool>(
                        valueListenable: BugShot.shooting,
                        builder: (context, shooting, unusedChild) {
                          if (shooting) {
                            return const BugShotBar();
                          } else {
                            return const SizedBox.shrink();
                          }
                        },
                      ),
                    ],
                  ),
                );
                final chrome = desktopChrome;
                if (chrome != null) {
                  app = chrome(context, app);
                }
                // Native glass: the window under all of it, title bar included.
                return GlassBackdrop(child: app);
              },
              home: homeScreen,
            );
          },
        );
      },
    );
  }
}
