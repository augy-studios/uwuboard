// uwuBoard's apps: start-up (main.dart runs it). The store, the native bridge (or the desktop's host in its
// place), the theme, the saved session, then the app. The desktop's extra windows (its
// welcome window, update window and desktop widgets) start here too, from their arguments.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api/api.dart';
import 'app/app.dart';
import 'app/env.dart';
import 'app/links.dart';
import 'app/state.dart';
import 'data/store.dart';
import 'desktop/desktop_main_stub.dart' if (dart.library.io) 'desktop/desktop_main.dart';
import 'features/sync/sync_controller.dart';
import 'features/update/update_bar.dart';
import 'native/bridge.dart';
import 'theme/theme.dart';

/// The app's start-up, for main() and the Playwright suite's entry point (e2e/main_e2e.dart).
///
/// In order: the store, the app's version, the desktop's or Android's native side, the theme,
/// the saved session and any link the app was opened with, and only then the app itself.
Future<void> runUwuBoard(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  // A desktop widget's own window runs only its small screen.
  if (Environment.desktop && await runDesktopSubWindow(arguments)) {
    return;
  }

  await Store.open();
  try {
    Environment.version = (await PackageInfo.fromPlatform()).version;
  } catch (error) {
    Environment.version = '';
  }

  final desktop = Environment.desktop && !kIsWeb;
  ThemeController.isDesktop = () {
    return Environment.desktop;
  };
  if (desktop) {
    await desktopBeforeApp(arguments);
  }
  await Native.start();

  ThemeController.isAndroid = () {
    return Environment.android;
  };
  ThemeController.instance.init();
  Api.watchOffline();
  AppState.instance.onBoardsChanged = SyncController.instance.boardsChanged;
  AppState.instance.onLogout.add(SyncController.instance.stop);
  await AppState.instance.restore();

  // Links from the platform: the one that opened the app, and any that come after.
  Native.on('App', 'link', (data) {
    final url = data['url'];
    if (url is String) {
      Links.open(url);
    }
  });
  final launch = await Native.tryCall('App', 'launchLink');
  if (launch != null) {
    if (launch['url'] is String) {
      Links.open(launch['url'] as String);
    }
  }
  // In the browser (the Playwright suite's build), a sync link in the address.
  if (kIsWeb) {
    final base = Uri.base;
    if (base.fragment.startsWith('sync/')) {
      Links.open(base.toString());
    }
  }

  runApp(const UwuBoardApp());

  if (Environment.android) {
    AndroidUpdates.instance.start();
  }
  if (desktop) {
    await desktopAfterApp(arguments);
  }
}
