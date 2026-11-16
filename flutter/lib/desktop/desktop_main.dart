// uwuBoard for Windows, macOS and Linux: the same app as the phone's, with the desktop's extras
// round it (docs/desktop-features-spec.md lists each one, docs/flutter-desktop-app-spec.md says
// how):
//
// - one copy at a time, links forwarded to it (desk.dart);
// - the update window at launch, and updating itself (splash.dart, updater.dart);
// - Make it yours, the first window, and from the tray's menu after (welcome.dart);
// - the tray, where closing the window leaves it running (tray.dart);
// - its own title bar and command bar, shortcuts, the macOS menu bar (chrome.dart);
// - due cards as notifications, the tray countdown, the Jump List and Dock (glance.dart);
// - desktop widgets, each in its own window and engine (widgets_window.dart);
// - starting at sign-in, uwu://board/ links shared with the sibling apps (desk.dart).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import '../app/app.dart';
import '../app/sidebar.dart';
import '../features/theme/theme_sheet.dart';
import '../native/bridge.dart';
import '../theme/theme.dart';
import 'adaptive.dart';
import 'backdrop.dart';
import 'chrome.dart';
import 'desk.dart';
import 'glance.dart';
import 'host.dart';
import 'notify.dart';
import 'runner.dart';
import 'settings.dart';
import 'splash.dart';
import 'tray.dart';
import 'updater.dart';
import 'welcome.dart';
import 'widgets_window.dart';

/// A desktop widget's own engine runs only its small screen. True when this engine was one.
Future<bool> runDesktopSubWindow(List<String> args) async {
  try {
    final c = await WindowController.fromCurrentEngine();
    if (c.arguments.isEmpty) return false;
    final m = jsonDecode(c.arguments);
    if (m is Map && m['kind'] == 'widget') {
      await runWidgetWindow('${m['id']}');
      return true;
    }
  } catch (_) {
    // The main window.
  }
  return false;
}

/// Before the app: one copy only, the window, the update window, and Make it yours the first time.
Future<void> desktopBeforeApp(List<String> args) async {
  Desktop.launchArgs = args;
  if (!await Desktop.claimInstance(args)) exit(0);
  Native.host = DesktopHost();
  await Desktop.setUp();
  ThemeController.I.init();
  ThemeController.I.systemAccent = DeskSettings.get<bool>('useSystemAccent') ?? false;

  // The update window, every launch of an installed copy.
  if (!Desktop.fromSource || Platform.environment['UWUBOARD_SPLASH_DEMO'] == '1') {
    await splashWindow();
    runApp(const SplashApp());
    await Updater.startup();
  }

  // Make it yours: once, for a new install.
  if (DeskSettings.get<bool>('setupDone') != true) await _welcome();
}

Future<void> _welcome() async {
  final done = Completer<WelcomeChoices?>();
  await welcomeWindow();
  runApp(
    WelcomeApp(
      done: (c) {
        if (!done.isCompleted) done.complete(c);
      },
    ),
  );
  await applyWelcome(await done.future);
}

/// After the app's started: the chrome round it, the tray, notifications, the glance surfaces,
/// widgets, links, start at sign-in, and the update checks.
Future<void> desktopAfterApp(List<String> args) async {
  desktopChrome = (context, child) => DesktopChrome(child: child);
  desktopAccentScheme = (b) => ColorScheme.fromSeed(seedColor: _systemAccent() ?? _green, brightness: b);
  desktopAccent = _systemAccent;
  desktopAccentGet = () => ThemeController.I.systemAccent;
  desktopAccentSet = (on) {
    DeskSettings.write({'useSystemAccent': on});
    ThemeController.I.setSystemAccent(on);
  };
  desktopBoardActions = (board) => [
    MenuAction('Pin to Desktop Widget', () => DeskWidgets.add(board), icon: 'widget'),
    MenuAction('Set as Tray Countdown', () => Glance.follow(board), icon: 'pin'),
  ];
  ViewHistory.start();
  Runner.listen();
  Runner.onDock = (id) => Desktop.show('uwu://board/b/$id');
  Runner.onThumb = (id) => Desktop.show(id.startsWith('uwu://') ? id : null);
  Runner.onOpen = (link) => link == null ? Desktop.show() : Desktop.onSecondCopy([link]);
  DeskWidgets.listen((link) => Desktop.show(link));
  Updater.showSplash = () async {
    await splashWindow();
    runApp(const SplashApp());
  };
  DeskTray.openWelcome = () async {
    await Desktop.hide();
    // Not the boards' window for now: its size and place stay as they were kept, not the
    // welcome window's, and it comes back maximised if it was.
    Desktop.shown = false;
    final done = Completer<WelcomeChoices?>();
    await welcomeWindow();
    runApp(
      WelcomeApp(
        done: (c) {
          if (!done.isCompleted) done.complete(c);
        },
      ),
    );
    await applyWelcome(await done.future);
    Desktop.shown = false;
    runApp(const UwuBoardApp());
    await Desktop.firstShow();
  };

  await DeskNotify.init();
  WindowBackdrop.start();
  await Desktop.firstShow();
  unawaited(DeskTray.I.start());
  Glance.start();
  unawaited(DeskWidgets.reopenAll());
  unawaited(Desktop.registerScheme());
  unawaited(Desktop.startAtLoginFirstRun());
  Updater.start();
}

/// The system's accent colour, read again at most every half a minute: the theme asks on every
/// build, and reading it starts a process. Null where the system has none to give.
Color? _systemAccent() {
  final now = DateTime.now();
  if (now.difference(_accentAt) < const Duration(seconds: 30)) return _accent;
  _accentAt = now;
  return _accent = _readSystemAccent();
}

Color? _accent;
DateTime _accentAt = DateTime(0);

/// uwuBoard's green, for "Use system accent colour" where the system has none.
const _green = Color(0xFF22A85A);

Color? _hex(String s) {
  final m = RegExp(r'#([0-9a-fA-F]{6})').firstMatch(s);
  return m == null ? null : Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
}

/// COSMIC keeps its accent as RON, `(red: 0.38, green: 0.81, blue: 0.87, …)`, in the theme
/// builder's file for the mode it's in (the theme's own, if the builder's is the default).
Color? _cosmicAccent() {
  final home = Platform.environment['HOME'];
  if (home == null) return null;
  final config = Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config';
  String read(String path) {
    final f = File('$config/cosmic/$path');
    return f.existsSync() ? f.readAsStringSync() : '';
  }

  final dark = read('com.system76.CosmicTheme.Mode/v1/is_dark').trim() != 'false';
  final mode = dark ? 'Dark' : 'Light';
  for (final path in ['com.system76.CosmicTheme.$mode.Builder/v1/accent', 'com.system76.CosmicTheme.$mode/v1/accent']) {
    final m = RegExp(r'red:\s*([\d.]+),\s*green:\s*([\d.]+),\s*blue:\s*([\d.]+)').firstMatch(read(path));
    if (m != null) {
      int c(int i) => (double.parse(m.group(i)!) * 255).round().clamp(0, 255);
      return Color.fromARGB(255, c(1), c(2), c(3));
    }
  }
  return null;
}

/// The system's accent colour where it can be read.
Color? _readSystemAccent() {
  try {
    if (Platform.isWindows) {
      final r = Process.runSync('reg', ['query', r'HKCU\Software\Microsoft\Windows\DWM', '/v', 'AccentColor']);
      final m = RegExp(r'0x([0-9a-fA-F]{8})').firstMatch('${r.stdout}');
      if (m != null) {
        // ABGR.
        final v = int.parse(m.group(1)!, radix: 16);
        return Color.fromARGB(255, v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff);
      }
    } else if (Platform.isMacOS) {
      final r = Process.runSync('defaults', ['read', '-g', 'AppleAccentColor']);
      const accents = {
        '-1': Color(0xFF8E8E93),
        '0': Color(0xFFFF3B30),
        '1': Color(0xFFFF9500),
        '2': Color(0xFFFFCC00),
        '3': Color(0xFF34C759),
        '5': Color(0xFFAF52DE),
        '6': Color(0xFFFF2D55),
      };
      return accents['${r.stdout}'.trim()] ?? const Color(0xFF007AFF);
    } else {
      final desktop = (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '').toUpperCase();
      if (desktop.contains('COSMIC')) {
        final c = _cosmicAccent();
        if (c != null) return c;
      }
      if (desktop.contains('DEEPIN') || desktop.contains('DDE')) {
        final r = Process.runSync('gsettings', ['get', 'com.deepin.dde.appearance', 'qt-active-color']);
        final c = _hex('${r.stdout}');
        if (c != null) return c;
      }
      final r = Process.runSync('gsettings', ['get', 'org.gnome.desktop.interface', 'accent-color']);
      const accents = {
        'blue': Color(0xFF3584E4),
        'teal': Color(0xFF2190A4),
        'green': Color(0xFF3A944A),
        'yellow': Color(0xFFC88800),
        'orange': Color(0xFFED5B00),
        'red': Color(0xFFE62D42),
        'pink': Color(0xFFD56199),
        'purple': Color(0xFF9141AC),
        'slate': Color(0xFF6F8396),
      };
      final c = accents['${r.stdout}'.replaceAll("'", '').trim()];
      if (c != null) return c;
    }
  } catch (_) {}
  return null;
}
