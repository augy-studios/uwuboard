// The app as the Playwright suite runs it (README.md here): the real screens in a browser, with a
// stand-in for the Android side, so what only the phone can do (the Updates page, the release
// notifications switch, saving files) is at least reached the right way. Every call to it lands in
// window.e2eCalls, and window.e2eEmit(plugin, event, json) says what Android would have said.
// Screen reader support is switched on: it's what the suite finds things by.
//
// Query parameters:
//   ?android=1     draw as the Android app does (its Updates entry, Material You by default)
//   ?wallpaper=1   pretend the phone has wallpaper colours (a purple), for Material You
//   ?play=1        as the Google Play build: no updater of its own
//   ?desktop=1     drawn as the desktop apps are: their title bar and command bar, dialogs and
//                  side panels, the boards' right-click menu (for the store's desktop pictures)
//   ?welcome=1     the desktop's Make it yours window
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:uwuboard/app/app.dart';
import 'package:uwuboard/app/env.dart';
import 'package:uwuboard/app/sidebar.dart';
import 'package:uwuboard/data/store.dart';
import 'package:uwuboard/desktop/adaptive.dart';
import 'package:uwuboard/desktop/chrome.dart';
import 'package:uwuboard/desktop/welcome.dart';
import 'package:uwuboard/theme/theme.dart';
import 'package:uwuboard/native/bridge.dart';
import 'package:uwuboard/run.dart';

class _FakeAndroid implements NativeHost {
  _FakeAndroid({required this.play}) {
    globalContext.setProperty('e2eCalls'.toJS, <JSAny>[].toJS);
    globalContext.setProperty(
      'e2eEmit'.toJS,
      ((JSString plugin, JSString event, JSString json) {
        Native.emit(plugin.toDart, event.toDart, Map<String, dynamic>.from(jsonDecode(json.toDart) as Map));
      }).toJS,
    );
  }

  final bool play;

  @override
  Future<Map<String, dynamic>?> call(String plugin, String method, Map<String, dynamic> options) async {
    (globalContext.getProperty('e2eCalls'.toJS) as JSObject)
        .callMethod('push'.toJS, jsonEncode({'plugin': plugin, 'method': method, 'options': options}).toJS);
    switch ('$plugin.$method') {
      case 'App.info':
        return {
          'platform': 'android',
          'version': '1.0.0',
          'build': 1,
          'play': play,
          'features': ['saveFile', 'links', 'push', if (!play) 'update'],
        };
      case 'App.saveFile':
        return {'path': 'Downloads/${options['name']}'};
      case 'App.launchLink':
        return {};
      default:
        return {};
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final q = Uri.base.queryParameters;
  if (q['android'] == '1') {
    Env.androidOverride = true;
    Native.host = _FakeAndroid(play: q['play'] == '1');
  }
  if (q['wallpaper'] == '1') {
    testLightDynamic = ColorScheme.fromSeed(seedColor: const Color(0xFF7B3FF2));
    testDarkDynamic = ColorScheme.fromSeed(seedColor: const Color(0xFF7B3FF2), brightness: Brightness.dark);
  }
  if (q['welcome'] == '1') {
    Env.desktopOverride = true;
    await Store.open();
    ThemeController.I.init();
    runApp(WelcomeApp(done: (_) {}));
    return;
  }
  if (q['desktop'] == '1') {
    Env.desktopOverride = true;
    desktopChrome = (context, child) => DesktopChrome(child: child);
    desktopBoardActions = (board) => [
          MenuAction('Pin to Desktop Widget', () {}, icon: 'widget'),
          MenuAction('Set as Tray Countdown', () {}, icon: 'pin'),
        ];
    ViewHistory.start();
  }
  await runUwuBoard(const []);
}
