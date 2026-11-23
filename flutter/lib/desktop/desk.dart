// The desktop app's core (docs/desktop-features-spec.md): its one main window, kept running in
// the tray when closed, one copy at a time, starting at sign-in, and uwu://board/ links shared
// with the sibling UwU Apps.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app/links.dart';
import 'settings.dart';

class Desktop {
  Desktop._();

  static const name = 'uwuBoard';
  static const appId = 'org.uwuapps.board';
  static const site = 'https://board.uwuapps.org';
  static const releases = 'https://github.com/augy-studios/uwuboard/releases/latest';

  static bool get mac {
    return Platform.isMacOS;
  }

  static bool get windows {
    return Platform.isWindows;
  }

  static bool get linux {
    return Platform.isLinux;
  }

  /// Run from `flutter run`, not an installed copy: nothing to update, no start at sign-in.
  static bool get fromSource {
    return !kReleaseMode;
  }

  /// The command line the app was started with.
  static List<String> launchArguments = const [];

  /// Quitting for real: closing the window then lets it go.
  static bool quitting = false;

  /// The main window's been shown once (after the update window and Make it yours).
  static bool shown = false;

  static final ValueNotifier<bool> fullScreen = ValueNotifier(false);
  static final ValueNotifier<bool> maximized = ValueNotifier(false);

  // ---------- the main window ----------

  static const minimumSize = Size(800, 600);
  static const compactMinimumSize = Size(360, 520);
  static const defaultSize = Size(1120, 760);

  /// The window's size and place when last neither maximised, full screen nor minimised.
  static Rect? _normalBounds;
  static Timer? _keepBoundsTimer;

  static final _listener = _WindowEvents();

  /// Hidden, its own title bar, close keeping the app in the tray.
  static Future<void> setUp() async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: name,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: true,
        minimumSize: compactMinimumSize,
        size: defaultSize,
        center: true,
        skipTaskbar: false,
      ),
    );
    await windowManager.setPreventClose(true);
    windowManager.addListener(_listener);
  }

  /// Keeps the window's size, place and maximised state in the settings, for next time: `now`,
  /// or 600 ms after the last move or resize (so a drag writes once, at its end).
  static void _keepBounds({bool now = false}) {
    if (!shown) {
      return;
    }
    final oldTimer = _keepBoundsTimer;
    if (oldTimer != null) {
      oldTimer.cancel();
    }
    Future<void> write() async {
      try {
        final isMaximized = await windowManager.isMaximized();
        final isFullScreen = await windowManager.isFullScreen();
        final isMinimized = await windowManager.isMinimized();
        if (!isMaximized && !isFullScreen && !isMinimized) {
          _normalBounds = await windowManager.getBounds();
        }
        final bounds = _normalBounds;
        DeskSettings.write({
          if (bounds != null) 'bounds': {'x': bounds.left.round(), 'y': bounds.top.round(), 'width': bounds.width.round(), 'height': bounds.height.round()},
          'maximized': isMaximized,
        });
      } catch (error) {
        // Not kept this time.
      }
    }

    if (now) {
      write();
    } else {
      _keepBoundsTimer = Timer(const Duration(milliseconds: 600), write);
    }
  }

  /// A kept window position, or 40 if there's none.
  static double _positionOrDefault(Object? value) {
    final position = value as num?;
    if (position == null) {
      return 40.0;
    }
    return position.toDouble();
  }

  /// The window, the first time: at its kept size and place (if that's still on a screen),
  /// maximised unless it was last closed un-maximised.
  static Future<void> firstShow() async {
    if (shown) {
      return;
    }
    shown = true;
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(compactMinimumSize);
    final settings = DeskSettings.read();
    final bounds = settings['bounds'];
    var placed = false;
    if (bounds is Map && bounds['width'] is num && bounds['height'] is num) {
      final rect = Rect.fromLTWH(
        _positionOrDefault(bounds['x']),
        _positionOrDefault(bounds['y']),
        (bounds['width'] as num).toDouble(),
        (bounds['height'] as num).toDouble(),
      );
      if (_onAScreen(rect)) {
        await windowManager.setBounds(rect);
        placed = true;
      } else {
        await windowManager.setSize(rect.size);
      }
    }
    if (!placed) {
      if (bounds is! Map) {
        await windowManager.setSize(defaultSize);
      }
      await windowManager.center();
    }
    _normalBounds = await windowManager.getBounds();
    if (settings['maximized'] != false) {
      await windowManager.maximize();
    }
    await windowManager.show();
    await windowManager.focus();
    for (final callback in List.of(onShown)) {
      callback();
    }
  }

  static final List<void Function()> onShown = [];

  /// Whether `rect` is at least partly on (or near) one of the screens.
  static bool _onAScreen(Rect rect) {
    try {
      for (final display in ui.PlatformDispatcher.instance.displays) {
        final size = display.size / display.devicePixelRatio;
        if (rect.overlaps(Rect.fromLTWH(-size.width, -size.height, size.width * 3, size.height * 3))) {
          return true;
        }
      }
    } catch (error) {
      // No screens known: treated as off screen.
    }
    return false;
  }

  /// The window, forward; on a link's page if there's one.
  static Future<void> show([String? link]) async {
    if (!shown) {
      await firstShow();
    } else {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    }
    if (link != null && link.isNotEmpty) {
      Links.open(link);
    }
  }

  /// Shown and in front, or hidden if it already is (the tray icon's click).
  static Future<void> toggle() async {
    if (shown && await windowManager.isVisible() && await windowManager.isFocused() && !await windowManager.isMinimized()) {
      await hide();
    } else {
      await show();
    }
  }

  /// Into the tray. The first time, a notification says it's still running.
  static Future<void> hide() async {
    _keepBounds(now: true);
    await windowManager.hide();
    if (DeskSettings.get<bool>('trayHintShown') == true) {
      return;
    }
    DeskSettings.write({'trayHintShown': true});
    final stillRunningNotice = stillRunning;
    if (stillRunningNotice != null) {
      stillRunningNotice();
    }
  }

  /// Set by notify.dart: "uwuBoard is still running".
  static void Function()? stillRunning;

  static Future<bool> get inFront async {
    return shown && await windowManager.isVisible() && await windowManager.isFocused();
  }

  /// Quits: anything waiting for the quit (an update to install) runs first.
  static Future<void> quit() async {
    quitting = true;
    _keepBounds(now: true);
    for (final callback in List.of(beforeQuit)) {
      try {
        await callback();
      } catch (error) {
        // One failing doesn't stop the quit.
      }
    }
    await windowManager.setPreventClose(false);
    exit(0);
  }

  static final List<Future<void> Function()> beforeQuit = [];

  static Future<void> setFullScreen(bool on) async {
    await windowManager.setFullScreen(on);
    fullScreen.value = on;
  }

  // ---------- one copy at a time ----------

  static ServerSocket? _instance;

  static File get _portFile {
    return File('${DeskSettings.folder}${Platform.pathSeparator}instance.port');
  }

  /// True when this is the only copy. Otherwise the running copy is handed this one's command
  /// line (a link, or just "come forward"), and this one should quit.
  static Future<bool> claimInstance(List<String> arguments) async {
    // A running copy wrote the port it listens on; if it answers, hand it the command line.
    try {
      final port = int.tryParse(_portFile.readAsStringSync().trim());
      if (port != null) {
        final socket = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(milliseconds: 700));
        socket.write(jsonEncode({'app': appId, 'args': arguments}));
        await socket.flush();
        await socket.close();
        return false;
      }
    } catch (error) {
      // Nobody listening: this copy is the one.
    }
    // This copy is the one: listen for later copies, and write down the port for them.
    try {
      _instance = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _portFile.parent.createSync(recursive: true);
      _portFile.writeAsStringSync('${_instance!.port}');
      _instance!.listen((client) {
        utf8.decoder.bind(client).join().then((text) {
          try {
            final message = jsonDecode(text);
            if (message is Map && message['app'] == appId) {
              List? otherArguments = message['args'] as List?;
              if (otherArguments == null) {
                otherArguments = const [];
              }
              onSecondCopy(List<String>.from(otherArguments));
            }
          } catch (error) {
            // Not a message from another copy.
          }
        });
      });
    } catch (error) {
      // Can't listen: carry on as the only copy.
    }
    return true;
  }

  /// Another copy was opened: this one comes forward, on its link if it had one.
  static void onSecondCopy(List<String> arguments) {
    final link = linkIn(arguments);
    if (link != null && !_ours(link)) {
      handOff(link);
      return;
    }
    show(link);
  }

  // ---------- links ----------

  /// The first uwu:// link in a command line, or null.
  static String? linkIn(List<String> arguments) {
    return arguments.where((argument) {
      return argument.toLowerCase().startsWith('$appScheme://');
    }).firstOrNull;
  }

  /// Whether a link is for this app (its host is uwuBoard's) rather than another UwU App.
  static bool _ours(String link) {
    final uri = Uri.tryParse(link);
    String host = '';
    if (uri != null) {
      host = uri.host;
    }
    return host.toLowerCase() == appHost;
  }

  /// Registers uwu:// for this app at every start (Windows), so links keep working after an update
  /// or a move. A desktop gives a scheme to one app only, so whichever UwU App holds it is noted
  /// first, and links for its host are handed to it (handOff).
  static Future<void> registerScheme() async {
    if (fromSource) {
      return;
    }
    if (windows) {
      final executable = Platform.resolvedExecutable;
      const key = r'HKCU\Software\Classes\uwu';
      final mine = '"$executable" "%1"';
      try {
        final result = await Process.run('reg', ['query', '$key\\shell\\open\\command', '/ve']);
        final match = RegExp(r'REG_SZ\s+(.+)$', multiLine: true).firstMatch('${result.stdout}');
        String? current;
        if (match != null) {
          final group = match.group(1);
          if (group != null) {
            current = group.trim();
          }
        }
        if (current != null && current.isNotEmpty && current.toLowerCase() != mine.toLowerCase() && !current.toLowerCase().contains('uwuboard')) {
          DeskSettings.write({
            'linkHandoff': {'command': current},
          });
        }
        await Process.run('reg', ['add', key, '/ve', '/d', 'URL:UwU Apps link', '/f']);
        await Process.run('reg', ['add', key, '/v', 'URL Protocol', '/d', '', '/f']);
        await Process.run('reg', ['add', '$key\\shell\\open\\command', '/ve', '/d', mine, '/f']);
      } catch (error) {
        // Links won't open this app.
      }
    } else if (linux) {
      try {
        final result = await Process.run('xdg-mime', ['query', 'default', 'x-scheme-handler/uwu']);
        final current = '${result.stdout}'.trim();
        if (current.isNotEmpty && current != 'uwuboard.desktop') {
          DeskSettings.write({
            'linkHandoff': {'desktop': current},
          });
        }
        await Process.run('xdg-mime', ['default', 'uwuboard.desktop', 'x-scheme-handler/uwu']);
      } catch (error) {
        // Links won't open this app.
      }
    }
  }

  /// A link for another UwU App, passed to the one that held the scheme before this one, as one
  /// argument and never through a shell.
  static Future<bool> handOff(String link) async {
    final handoff = DeskSettings.get<Map<String, dynamic>>('linkHandoff');
    try {
      if (windows && handoff != null && handoff['command'] is String) {
        // The command split into its parts: each quoted part, or each run of non-spaces.
        final parts = RegExp(r'"([^"]+)"|(\S+)').allMatches(handoff['command'] as String).map((match) {
          final quoted = match.group(1);
          if (quoted != null) {
            return quoted;
          }
          return match.group(2)!;
        }).toList();
        if (parts.isEmpty) {
          return false;
        }
        // The link goes where the command has %1, or on the end.
        final arguments = [
          for (final part in parts.skip(1))
            if (part == '%1') link else part,
        ];
        if (!arguments.contains(link)) {
          arguments.add(link);
        }
        await Process.start(parts.first, arguments, mode: ProcessStartMode.detached);
        return true;
      }
      if (linux && handoff != null && handoff['desktop'] is String) {
        await Process.start('gtk-launch', [handoff['desktop'] as String, link], mode: ProcessStartMode.detached);
        return true;
      }
    } catch (error) {
      // Couldn't start it.
    }
    return false;
  }

  // ---------- starting at sign-in ----------

  /// Linux's autostart entry for the app.
  static File get _autostart {
    String? configHome = Platform.environment['XDG_CONFIG_HOME'];
    if (configHome == null) {
      configHome = '${Platform.environment['HOME']}/.config';
    }
    return File('$configHome/autostart/uwuboard.desktop');
  }

  /// macOS's launch agent for the app.
  static File get _launchAgent {
    return File('${Platform.environment['HOME']}/Library/LaunchAgents/$appId.plist');
  }

  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  /// Whether the app is set to start at sign-in.
  static Future<bool> startsAtLogin() async {
    try {
      if (linux) {
        return _autostart.existsSync();
      }
      if (mac) {
        return _launchAgent.existsSync();
      }
      final result = await Process.run('reg', ['query', _runKey, '/v', name]);
      return result.exitCode == 0;
    } catch (error) {
      return false;
    }
  }

  /// Turns starting at sign-in on or off: an autostart entry (Linux), a launch agent (macOS), or
  /// the Run key in the registry (Windows).
  static Future<void> setStartAtLogin(bool startAtLogin) async {
    if (fromSource) {
      return;
    }
    try {
      if (linux) {
        final file = _autostart;
        if (!startAtLogin) {
          if (file.existsSync()) {
            file.deleteSync();
          }
          return;
        }
        // An AppImage runs from a temporary mount, so it's started by the file itself.
        String? executable = Platform.environment['APPIMAGE'];
        if (executable == null) {
          executable = Platform.resolvedExecutable;
        }
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(
          ['[Desktop Entry]', 'Type=Application', 'Name=$name', 'Exec="$executable" --hidden', 'Icon=uwuboard', 'X-GNOME-Autostart-enabled=true', ''].join('\n'),
        );
      } else if (mac) {
        final file = _launchAgent;
        if (!startAtLogin) {
          if (file.existsSync()) {
            file.deleteSync();
          }
          return;
        }
        // The .app bundle: three folders up from the executable inside it.
        final app = File(Platform.resolvedExecutable).parent.parent.parent.path;
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$appId</string>
<key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>$app</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
''');
      } else if (startAtLogin) {
        await Process.run('reg', ['add', _runKey, '/v', name, '/d', '"${Platform.resolvedExecutable}"', '/f']);
      } else {
        await Process.run('reg', ['delete', _runKey, '/v', name, '/f']);
      }
    } catch (error) {
      // Not changed.
    }
  }

  /// From the first run of an installed copy the app starts at sign-in, until it's turned off;
  /// once chosen, the choice sticks (loginChosen).
  static Future<void> startAtLoginFirstRun() async {
    if (fromSource || DeskSettings.get<bool>('loginChosen') == true) {
      return;
    }
    await setStartAtLogin(true);
    DeskSettings.write({'loginChosen': true});
  }

  // ---------- small things ----------

  /// Opens a link in the browser (or mail app).
  static Future<void> openExternal(String url) async {
    try {
      if (windows) {
        await Process.start('rundll32', ['url.dll,FileProtocolHandler', url], mode: ProcessStartMode.detached);
      } else if (mac) {
        await Process.start('open', [url], mode: ProcessStartMode.detached);
      } else {
        await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
      }
    } catch (error) {
      // Not opened.
    }
  }

  /// Shows a file in its folder.
  static Future<void> showInFolder(String path) async {
    try {
      if (windows) {
        await Process.start('explorer.exe', ['/select,', path], mode: ProcessStartMode.detached);
      } else if (mac) {
        await Process.start('open', ['-R', path], mode: ProcessStartMode.detached);
      } else {
        await Process.start('xdg-open', [File(path).parent.path], mode: ProcessStartMode.detached);
      }
    } catch (error) {
      // Not shown.
    }
  }

  /// The Downloads folder.
  static String get downloads {
    final environment = Platform.environment;
    if (windows) {
      return '${environment['USERPROFILE']}\\Downloads';
    }
    String? home = environment['HOME'];
    if (home == null) {
      home = '';
    }
    if (linux) {
      // The folder the user chose, as user-dirs.dirs has it.
      try {
        final userDirectories = File('$home/.config/user-dirs.dirs').readAsStringSync();
        final match = RegExp(r'^XDG_DOWNLOAD_DIR="(.+)"$', multiLine: true).firstMatch(userDirectories);
        if (match != null) {
          return match[1]!.replaceAll(r'$HOME', home);
        }
      } catch (error) {
        // Not there: the usual folder.
      }
    }
    return '$home/Downloads';
  }
}

/// The main window's events: closing it hides it to the tray, and moving, resizing and
/// maximising are kept for next time.
class _WindowEvents with WindowListener {
  @override
  void onWindowClose() {
    // Not while the window is Make it yours or the update window: they handle their own close.
    if (Desktop.quitting || !Desktop.shown) {
      return;
    }
    Desktop.hide();
  }

  @override
  void onWindowMoved() {
    Desktop._keepBounds();
  }

  @override
  void onWindowResized() {
    Desktop._keepBounds();
  }

  @override
  void onWindowMaximize() {
    Desktop.maximized.value = true;
    Desktop._keepBounds();
  }

  @override
  void onWindowUnmaximize() {
    Desktop.maximized.value = false;
    Desktop._keepBounds();
  }

  @override
  void onWindowEnterFullScreen() {
    Desktop.fullScreen.value = true;
  }

  @override
  void onWindowLeaveFullScreen() {
    Desktop.fullScreen.value = false;
  }
}
