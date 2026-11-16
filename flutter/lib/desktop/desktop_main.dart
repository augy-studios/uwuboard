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
Future<bool> runDesktopSubWindow(List<String> arguments) async {
  try {
    final controller = await WindowController.fromCurrentEngine();
    if (controller.arguments.isEmpty) {
      return false;
    }
    final decoded = jsonDecode(controller.arguments);
    if (decoded is Map && decoded['kind'] == 'widget') {
      await runWidgetWindow('${decoded['id']}');
      return true;
    }
  } catch (error) {
    // The main window.
  }
  return false;
}

/// Before the app: one copy only, the window, the update window, and Make it yours the first time.
Future<void> desktopBeforeApp(List<String> arguments) async {
  Desktop.launchArgs = arguments;
  if (!await Desktop.claimInstance(arguments)) {
    exit(0);
  }
  Native.host = DesktopHost();
  await Desktop.setUp();
  ThemeController.I.init();
  bool? useSystemAccent = DeskSettings.get<bool>('useSystemAccent');
  if (useSystemAccent == null) {
    useSystemAccent = false;
  }
  ThemeController.I.systemAccent = useSystemAccent;

  // The update window, every launch of an installed copy.
  if (!Desktop.fromSource || Platform.environment['UWUBOARD_SPLASH_DEMO'] == '1') {
    await splashWindow();
    runApp(const SplashApp());
    await Updater.startup();
  }

  // Make it yours: once, for a new install.
  if (DeskSettings.get<bool>('setupDone') != true) {
    await _welcome();
  }
}

/// Shows Make it yours in this window, waits for the choices, and applies them.
Future<void> _welcome() async {
  final done = Completer<WelcomeChoices?>();
  await welcomeWindow();
  runApp(
    WelcomeApp(
      done: (choices) {
        if (!done.isCompleted) {
          done.complete(choices);
        }
      },
    ),
  );
  await applyWelcome(await done.future);
}

/// After the app's started: the chrome round it, the tray, notifications, the glance surfaces,
/// widgets, links, start at sign-in, and the update checks.
Future<void> desktopAfterApp(List<String> arguments) async {
  // The shared app's hooks for the desktop's extras: the chrome round the app, the system
  // accent colour, and a board's right-click menu.
  desktopChrome = (context, child) {
    return DesktopChrome(child: child);
  };
  desktopAccentScheme = (brightness) {
    Color seedColor;
    final systemAccent = _systemAccent();
    if (systemAccent != null) {
      seedColor = systemAccent;
    } else {
      seedColor = _green;
    }
    return ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
  };
  desktopAccent = _systemAccent;
  desktopAccentGet = () {
    return ThemeController.I.systemAccent;
  };
  desktopAccentSet = (useSystemAccent) {
    DeskSettings.write({'useSystemAccent': useSystemAccent});
    ThemeController.I.setSystemAccent(useSystemAccent);
  };
  desktopBoardActions = (board) {
    return [
      MenuAction('Pin to Desktop Widget', () {
        DeskWidgets.add(board);
      }, icon: 'widget'),
      MenuAction('Set as Tray Countdown', () {
        Glance.follow(board);
      }, icon: 'pin'),
    ];
  };
  ViewHistory.start();

  // What the runner, the desktop widgets and the tray ask of the main window.
  Runner.listen();
  Runner.onDock = (id) {
    Desktop.show('uwu://board/b/$id');
  };
  Runner.onThumb = (id) {
    String? link;
    if (id.startsWith('uwu://')) {
      link = id;
    } else {
      link = null;
    }
    Desktop.show(link);
  };
  Runner.onOpen = (link) {
    if (link == null) {
      Desktop.show();
    } else {
      Desktop.onSecondCopy([link]);
    }
  };
  DeskWidgets.listen((link) {
    Desktop.show(link);
  });
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
        done: (choices) {
          if (!done.isCompleted) {
            done.complete(choices);
          }
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
  unawaited(DeskTray.instance.start());
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
  if (now.difference(_accentReadAt) < const Duration(seconds: 30)) {
    return _accent;
  }
  _accentReadAt = now;
  _accent = _readSystemAccent();
  return _accent;
}

/// The accent colour as last read, and when it was read.
Color? _accent;
DateTime _accentReadAt = DateTime(0);

/// uwuBoard's green, for "Use system accent colour" where the system has none.
const _green = Color(0xFF22A85A);

/// The first `#rrggbb` colour in `text`, or null if there's none.
Color? _colorFromHex(String text) {
  final match = RegExp(r'#([0-9a-fA-F]{6})').firstMatch(text);
  if (match == null) {
    return null;
  } else {
    return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
  }
}

/// COSMIC keeps its accent as RON, `(red: 0.38, green: 0.81, blue: 0.87, …)`, in the theme
/// builder's file for the mode it's in (the theme's own, if the builder's is the default).
Color? _cosmicAccent() {
  final home = Platform.environment['HOME'];
  if (home == null) {
    return null;
  }
  String? config = Platform.environment['XDG_CONFIG_HOME'];
  if (config == null) {
    config = '$home/.config';
  }

  /// One of COSMIC's settings files, or '' if it isn't there.
  String read(String path) {
    final file = File('$config/cosmic/$path');
    if (file.existsSync()) {
      return file.readAsStringSync();
    } else {
      return '';
    }
  }

  final dark = read('com.system76.CosmicTheme.Mode/v1/is_dark').trim() != 'false';
  String mode;
  if (dark) {
    mode = 'Dark';
  } else {
    mode = 'Light';
  }
  for (final path in ['com.system76.CosmicTheme.$mode.Builder/v1/accent', 'com.system76.CosmicTheme.$mode/v1/accent']) {
    final match = RegExp(r'red:\s*([\d.]+),\s*green:\s*([\d.]+),\s*blue:\s*([\d.]+)').firstMatch(read(path));
    if (match != null) {
      /// One colour channel, from 0 to 1 in the file to 0 to 255.
      int channel(int groupNumber) {
        return (double.parse(match.group(groupNumber)!) * 255).round().clamp(0, 255);
      }

      return Color.fromARGB(255, channel(1), channel(2), channel(3));
    }
  }
  return null;
}

/// The system's accent colour where it can be read: from the registry on Windows, the global
/// defaults on macOS, and on Linux from COSMIC's files, Deepin's settings or GNOME's.
Color? _readSystemAccent() {
  try {
    if (Platform.isWindows) {
      final result = Process.runSync('reg', ['query', r'HKCU\Software\Microsoft\Windows\DWM', '/v', 'AccentColor']);
      final match = RegExp(r'0x([0-9a-fA-F]{8})').firstMatch('${result.stdout}');
      if (match != null) {
        // ABGR.
        final value = int.parse(match.group(1)!, radix: 16);
        return Color.fromARGB(255, value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff);
      }
    } else if (Platform.isMacOS) {
      final result = Process.runSync('defaults', ['read', '-g', 'AppleAccentColor']);
      const accents = {
        '-1': Color(0xFF8E8E93),
        '0': Color(0xFFFF3B30),
        '1': Color(0xFFFF9500),
        '2': Color(0xFFFFCC00),
        '3': Color(0xFF34C759),
        '5': Color(0xFFAF52DE),
        '6': Color(0xFFFF2D55),
      };
      final accent = accents['${result.stdout}'.trim()];
      if (accent == null) {
        // Blue (the default, with no number set) or a number not listed.
        return const Color(0xFF007AFF);
      }
      return accent;
    } else {
      String? currentDesktop = Platform.environment['XDG_CURRENT_DESKTOP'];
      if (currentDesktop == null) {
        currentDesktop = '';
      }
      final desktop = currentDesktop.toUpperCase();
      if (desktop.contains('COSMIC')) {
        final accent = _cosmicAccent();
        if (accent != null) {
          return accent;
        }
      }
      if (desktop.contains('DEEPIN') || desktop.contains('DDE')) {
        final result = Process.runSync('gsettings', ['get', 'com.deepin.dde.appearance', 'qt-active-color']);
        final accent = _colorFromHex('${result.stdout}');
        if (accent != null) {
          return accent;
        }
      }
      final result = Process.runSync('gsettings', ['get', 'org.gnome.desktop.interface', 'accent-color']);
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
      final accent = accents['${result.stdout}'.replaceAll("'", '').trim()];
      if (accent != null) {
        return accent;
      }
    }
  } catch (error) {
    // Couldn't be read: no accent.
  }
  return null;
}
