// The runner's own channel (docs/flutter-desktop-app-spec.md §2.7), for what no package does:
//   Windows  the Jump List (favourite boards) and the taskbar's thumbnail buttons
//            (windows/runner/flutter_window.cpp)
//   macOS    the Dock menu and badge (macos/Runner/AppDelegate.swift)
//   all      the window's own material for native glass, 'setBackdrop' (backdrop.dart)
// Events back: 'thumb' with a button id or link, 'dock' with a board id, 'open' with a link and
// 'activate' (macOS). Where the runner doesn't know a call, it's quietly nothing.
import 'package:flutter/services.dart';

class Runner {
  Runner._();

  static const _channel = MethodChannel('org.uwuapps.board/desktop');

  /// Set by desktop_main.dart.
  static void Function(String id)? onThumb;
  static void Function(String boardId)? onDock;

  /// A link opened from elsewhere (macOS), or a click on the Dock icon (`null`).
  static void Function(String? link)? onOpen;

  /// Starts answering the runner's events by passing each to its handler above, if one is set.
  static void listen() {
    _channel.setMethodCallHandler((call) async {
      final arguments = call.arguments;
      switch (call.method) {
        case 'thumb':
          final thumbHandler = onThumb;
          if (thumbHandler != null) {
            thumbHandler('$arguments');
          }
        case 'dock':
          final dockHandler = onDock;
          if (dockHandler != null) {
            dockHandler('$arguments');
          }
        case 'open':
          final openHandler = onOpen;
          if (openHandler != null) {
            String? link;
            if (arguments is String) {
              link = arguments;
            } else {
              link = null;
            }
            openHandler(link);
          }
        case 'activate':
          final activateHandler = onOpen;
          if (activateHandler != null) {
            activateHandler(null);
          }
      }
      return null;
    });
  }

  /// Calls the runner, ignoring a system where it doesn't know the method.
  static Future<void> _call(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod(method, arguments);
    } catch (error) {
      // Not on this system.
    }
  }

  /// The favourite boards, [{ code, name }], for the Jump List, thumbnail buttons and Dock menu.
  static Future<void> setFavourites(List<Map<String, Object?>> favourites) {
    return _call('setFavourites', {
      'items': [
        for (final favourite in favourites) {'id': '${favourite['code']}', 'name': '${favourite['name']}', 'link': 'uwu://board/b/${favourite['code']}'},
      ],
    });
  }

  /// The window's material: 'mica' (Windows), 'glass' (macOS), 'blur' (Linux) or 'none', in light
  /// or dark. True if the system draws it.
  static Future<bool> setBackdrop(String kind, {required bool dark}) async {
    try {
      final drawn = await _channel.invokeMethod<bool>('setBackdrop', {'kind': kind, 'dark': dark});
      if (drawn == null) {
        return false;
      }
      return drawn;
    } catch (error) {
      return false;
    }
  }

  /// The Dock's badge (macOS): a few characters, or '' for none.
  static Future<void> setBadge(String text) {
    return _call('setBadge', text);
  }
}
