// The tray icon (the menu bar on macOS) and its menu (docs/desktop-features-spec.md §4): a click
// shows or hides the window on Windows and Linux; the menu, rebuilt whenever something in it
// changes, top to bottom:
//   Restart to update to x.y.z / Download version x.y.z (only while there is one)
//   Tray countdown: {board} and Stop the tray countdown (while one's followed)
//   Open uwuBoard, New board, Sync with another device
//   Add a desktop widget, Make it yours...
//   Check for updates..., Start when I sign in (a check box)
//   Quit
import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart';

import '../features/sync/sync_sheet.dart';
import '../app/nav.dart';
import 'desk.dart';
import 'glance.dart';
import 'updater.dart';
import 'widgets_window.dart';

class DeskTray with TrayListener {
  DeskTray._();
  static final DeskTray I = DeskTray._();

  /// Set by desktop_main.dart: opens Make it yours again.
  static Future<void> Function()? openWelcome;

  bool _login = false;

  Future<void> start() async {
    final icon = Platform.isWindows ? 'assets/images/tray.ico' : (Platform.isMacOS ? 'assets/images/tray_template.png' : 'assets/images/tray.png');
    await trayManager.setIcon(icon, isTemplate: Platform.isMacOS);
    await trayManager.setToolTip(Desktop.name);
    trayManager.addListener(this);
    Glance.onTray = (tooltip, title) {
      trayManager.setToolTip(tooltip);
      if (Platform.isMacOS) trayManager.setTitle(title);
      rebuild();
    };
    Updater.available.addListener(rebuild);
    Updater.ready.addListener(rebuild);
    Updater.checking.addListener(rebuild);
    _login = await Desktop.startsAtLogin();
    await rebuild();
  }

  Future<void> rebuild() async {
    final ready = Updater.ready.value;
    final available = Updater.available.value;
    final followed = Glance.followed.value;
    final checking = Updater.checking.value;
    await trayManager.setContextMenu(
      Menu(
        items: [
          if (ready != null) ...[
            MenuItem(key: 'restart', label: 'Restart to update to $ready', onClick: (_) => Updater.restartToUpdate()),
            MenuItem.separator(),
          ] else if (available != null && !Updater.canInstall) ...[
            MenuItem(key: 'download', label: 'Download version $available', onClick: (_) => Desktop.openExternal(Desktop.releases)),
            MenuItem.separator(),
          ],
          if (followed != null) ...[
            MenuItem(key: 'countdown', label: 'Tray countdown: ${followed['name']}', onClick: (_) => Desktop.show('uwu://board/b/${followed['code']}')),
            MenuItem(key: 'stop', label: 'Stop the tray countdown', onClick: (_) => Glance.follow(null)),
            MenuItem.separator(),
          ],
          MenuItem(key: 'open', label: 'Open ${Desktop.name}', onClick: (_) => Desktop.show()),
          MenuItem(key: 'new', label: 'New board', onClick: (_) => Desktop.show('uwu://board/new')),
          MenuItem(
            key: 'sync',
            label: 'Sync with another device',
            onClick: (_) async {
              await Desktop.show();
              final ctx = AppNav.context;
              if (ctx != null && ctx.mounted) unawaited(openSync(ctx));
            },
          ),
          MenuItem(key: 'widget', label: 'Add a desktop widget', onClick: (_) => DeskWidgets.add()),
          MenuItem(key: 'welcome', label: 'Make it yours...', onClick: (_) => openWelcome?.call()),
          MenuItem.separator(),
          MenuItem(key: 'check', label: checking ? 'Checking for updates...' : 'Check for updates...', disabled: checking, onClick: (_) => Updater.checkNow()),
          MenuItem.checkbox(
            key: 'login',
            label: 'Start when I sign in',
            checked: _login,
            onClick: (_) async {
              _login = !_login;
              await Desktop.setStartAtLogin(_login);
              rebuild();
            },
          ),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit', onClick: (_) => Desktop.quit()),
        ],
      ),
    );
  }

  @override
  void onTrayIconMouseDown() {
    // macOS opens the menu on a click; Windows and Linux show or hide the window.
    if (Platform.isMacOS) {
      trayManager.popUpContextMenu();
    } else {
      Desktop.toggle();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    Desktop.startsAtLogin().then((on) {
      _login = on;
      rebuild().then((_) => trayManager.popUpContextMenu());
    });
  }
}
