// The window's own material, for native glass (lib/theme/theme.dart, lib/widgets/glass.dart):
// asked of the runner whenever the look or the mode changes, and again after anything that
// resets the window's frame (showing it, leaving full screen).
//
//   Windows  Mica, through DWM (Windows 11 22H2 and later)        windows/runner/flutter_window.cpp
//   macOS    the desktop through an NSVisualEffectView            macos/Runner/MainFlutterWindow.swift
//   Linux    the compositor's blur, on DDE and KDE under X11      linux/runner/my_application.cc
//
// The runner says whether it could. Where it couldn't (Windows 10, a desktop that doesn't blur,
// COSMIC for now), the window stays solid and native glass frosts a glow of its own.
import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'desk.dart';
import 'runner.dart';

class WindowBackdrop {
  WindowBackdrop._();

  static String? _applied;
  static bool _started = false;

  static String _kindFor(GlassStyle style) => switch (style) {
    GlassStyle.fluent => 'mica',
    GlassStyle.tahoe => 'glass',
    GlassStyle.frosted => 'blur',
  };

  static void start() {
    if (_started) return;
    _started = true;
    ThemeController.I.addListener(_apply);
    // Showing the window and leaving full screen set its frame again, which takes Mica away.
    Desktop.onShown.add(() => _apply(force: true));
    Desktop.fullScreen.addListener(() => Timer(const Duration(milliseconds: 300), () => _apply(force: true)));
    _apply();
  }

  static Future<void> _apply({bool force = false}) async {
    final t = ThemeController.I;
    final kind = t.isNative ? _kindFor(t.glassStyle) : 'none';
    final dark = t.brightness == Brightness.dark;
    final key = '$kind/$dark';
    if (!force && key == _applied) return;
    _applied = key;
    final ok = await Runner.setBackdrop(kind, dark: dark);
    // The look may have changed while the runner answered.
    if (_applied == key) t.setWindowMaterial(kind != 'none' && ok);
  }
}
