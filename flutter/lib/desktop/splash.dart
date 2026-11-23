// The update window at launch (docs/desktop-features-spec.md §2): small, frameless, 300 × 360,
// draggable anywhere, before the main window on every launch of an installed copy. The icon
// gently bobbing (still under reduced motion), a line of status and a bar under it, and Later
// while an update downloads. Light or dark as the computer is, with its own colours.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../widgets/wavy_progress.dart';
import 'updater.dart';

class SplashApp extends StatelessWidget {
  const SplashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'uwuBoard',
      themeMode: ThemeMode.system,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF22A85A), fontFamily: 'Jua'),
      darkTheme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF22A85A), brightness: Brightness.dark, fontFamily: 'Jua'),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() {
    return _SplashScreenState();
  }
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  /// Moves the icon up and back down, over and over.
  late final _bobbing = _startBobbing();

  AnimationController _startBobbing() {
    final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    controller.repeat(reverse: true);
    return controller;
  }

  /// How far up the icon is moved right now; none under reduced motion.
  double _bobOffset(bool still) {
    if (still) {
      return 0;
    } else {
      return -6 * math.sin(_bobbing.value * math.pi);
    }
  }

  /// The bar's fill from 0 to 1, or null (a bar that just moves) when the percent isn't known.
  double? _barValue(int percent) {
    if (percent < 0) {
      return null;
    } else {
      return percent / 100;
    }
  }

  @override
  void dispose() {
    _bobbing.dispose();
    super.dispose();
  }

  /// The icon, the status line and its detail, the progress bar and Later, all following
  /// [Updater.splash].
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final still = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: colors.surface,
      body: DragToMoveArea(
        child: SizedBox.expand(
          child: ValueListenableBuilder<SplashStatus>(
            valueListenable: Updater.splash,
            builder: (context, status, child) {
              return Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _bobbing,
                      builder: (context, child) {
                        return Transform.translate(offset: Offset(0, _bobOffset(still)), child: child);
                      },
                      child: ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.asset('assets/images/icon-512.png', width: 96, height: 96)),
                    ),
                    const SizedBox(height: 28),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        status.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 17, color: colors.onSurface),
                      ),
                    ),
                    if (status.detail.isNotEmpty) ...[const SizedBox(height: 4), Text(status.detail, style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant))],
                    const SizedBox(height: 16),
                    // Material You's wavy bar, as the Android Updates page has it.
                    if (status.percent != null) WavyProgress(value: _barValue(status.percent!), label: status.text),
                    if (status.later) ...[const SizedBox(height: 14), TextButton(onPressed: Updater.later, child: const Text('Later'))],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The window set up as the update window: small, frameless, in the middle.
Future<void> splashWindow() async {
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
  await windowManager.setResizable(false);
  await windowManager.setMinimumSize(const Size(300, 360));
  await windowManager.setSize(const Size(300, 360));
  await windowManager.center();
  await windowManager.show();
}
