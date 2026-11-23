// The one way to platform code (docs/flutter-android-app-spec.md §4):
//
//   Native.call('App', 'info')                  → Bridge → Plugin.method(call) → resolve(JSON)
//   Native.on('App', 'link', (data) {...})      ← Bridge ← plugin.notifyListeners('link', JSON)
//   Native.has('update')                        ← info().features, listed by the App plugin
//
// Options and answers are JSON strings, so the native side needs no codec of its own. On
// Android the channel reaches the Java plugins in android/app/src/main/java/org/uwuapps/board/.
// The desktop apps install a Dart host instead (lib/desktop/host.dart), and tests a fake.
// Without either, the bridge is unavailable and every call fails fast, so features fall back
// to their plain path.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A plugin call that failed: its message, a code ("permission", "cancelled", "unavailable"…)
/// and whatever data came with it.
class NativeError implements Exception {
  NativeError(this.message, {this.code, this.data});
  final String message;
  final String? code;
  final Map<String, dynamic>? data;

  @override
  String toString() {
    if (code == null) {
      return message;
    } else {
      return '$message ($code)';
    }
  }
}

/// One listener for a plugin's event; [cancel] stops it.
class NativeListener {
  NativeListener._(this._key, this._callback);
  final String _key;
  final void Function(Map<String, dynamic>) _callback;

  void cancel() {
    Native._remove(this);
  }
}

/// Stands in for platform code: the desktop's host, or a fake in tests and screenshots.
abstract class NativeHost {
  Future<Map<String, dynamic>?> call(String plugin, String method, Map<String, dynamic> options);
}

class Native {
  Native._();

  static const _channel = MethodChannel('org.uwuapps.board/bridge');
  static final Map<String, List<NativeListener>> _listeners = {};
  static bool _started = false;
  static Map<String, dynamic>? _info;

  /// Set before start() to answer calls in Dart.
  static NativeHost? host;

  /// Whether there's anything behind the bridge at all.
  static bool available = true;

  /// Finds out once whether there's a native side (a host, or Android's channel), starts
  /// passing on the channel's events, and asks the App plugin what this build can do.
  static Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (host == null && !isAndroid) {
      available = false;
    }
    if (host == null && available) {
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'event') {
          return null;
        }
        final arguments = Map<String, dynamic>.from(call.arguments as Map);
        final plugin = '${arguments['plugin']}';
        final event = '${arguments['event']}';
        var data = _decode(arguments['data'] as String?);
        if (data == null) {
          data = <String, dynamic>{};
        }
        emit(plugin, event, data);
        return null;
      });
      try {
        await _channel.invokeMethod('hello');
      } on MissingPluginException {
        available = false;
      } catch (error) {
        // Answered below, if at all.
      }
    }
    try {
      if (available) {
        _info = await call('App', 'info');
      }
    } catch (error) {
      _info = null;
    }
  }

  /// For tests: as if never started.
  @visibleForTesting
  static void reset() {
    _started = false;
    _info = null;
    host = null;
    available = true;
    _listeners.clear();
  }

  // One field of the App plugin's info, or null before (or without) it.
  static Object? _infoField(String name) {
    final info = _info;
    if (info == null) {
      return null;
    }
    return info[name];
  }

  /// What this build and device can do, as the App plugin lists it. The only switch features
  /// use to show a native-only button.
  static bool has(String feature) {
    var features = _infoField('features') as List?;
    if (features == null) {
      features = const [];
    }
    return features.contains(feature);
  }

  static Map<String, dynamic>? get info {
    return _info;
  }

  static String? get version {
    return _infoField('version') as String?;
  }

  /// 'android', 'desktop', or null where there's no native side.
  static String? get platform {
    return _infoField('platform') as String?;
  }

  /// Calls a plugin's method with these options: through the host where there is one, else
  /// through the channel. Throws a [NativeError] when it fails or there's no native side.
  static Future<Map<String, dynamic>?> call(String plugin, String method, [Map<String, dynamic>? options]) async {
    if (!available) {
      throw NativeError('Not in the app', code: 'unavailable');
    }
    final Map<String, dynamic> optionsOrEmpty;
    if (options == null) {
      optionsOrEmpty = const {};
    } else {
      optionsOrEmpty = options;
    }
    final nativeHost = host;
    if (nativeHost != null) {
      return nativeHost.call(plugin, method, optionsOrEmpty);
    }
    try {
      final json = await _channel.invokeMethod<String>('call', {'plugin': plugin, 'method': method, 'options': jsonEncode(optionsOrEmpty)});
      return _decode(json);
    } on PlatformException catch (error) {
      var message = error.message;
      if (message == null) {
        message = 'Failed';
      }
      final Map<String, dynamic>? details;
      if (error.details is String) {
        details = _decode(error.details as String);
      } else {
        details = null;
      }
      throw NativeError(message, code: error.code, data: details);
    } on MissingPluginException {
      available = false;
      throw NativeError('Not in the app', code: 'unavailable');
    }
  }

  /// A call whose failure doesn't matter to the caller.
  static Future<Map<String, dynamic>?> tryCall(String plugin, String method, [Map<String, dynamic>? options]) async {
    try {
      return await call(plugin, method, options);
    } catch (error) {
      return null;
    }
  }

  /// Listens for a plugin's event. The first listener for an event asks the channel to start
  /// sending it.
  static NativeListener on(String plugin, String event, void Function(Map<String, dynamic>) callback) {
    final key = '$plugin.$event';
    final listener = NativeListener._(key, callback);
    final list = _listeners.putIfAbsent(key, () {
      return <NativeListener>[];
    });
    list.add(listener);
    if (list.length == 1 && available && host == null) {
      _channel.invokeMethod('listen', {'plugin': plugin, 'event': event}).catchError((error) {
        return null;
      });
    }
    return listener;
  }

  /// An event, to everything listening for it: from the channel, a host or a fake.
  static void emit(String plugin, String event, Map<String, dynamic> data) {
    var listeners = _listeners['$plugin.$event'];
    if (listeners == null) {
      listeners = const <NativeListener>[];
    }
    for (final listener in List.of(listeners)) {
      try {
        listener._callback(data);
      } catch (error) {
        // One listener's trouble isn't the others'.
      }
    }
  }

  // Forgets a listener; when it was its event's last, the channel stops sending that event.
  static void _remove(NativeListener listener) {
    final list = _listeners[listener._key];
    if (list == null || !list.remove(listener) || list.isNotEmpty || !available || host != null) {
      return;
    }
    final parts = listener._key.split('.');
    _channel.invokeMethod('unlisten', {'plugin': parts[0], 'event': parts[1]}).catchError((error) {
      return null;
    });
  }

  static Map<String, dynamic>? _decode(String? json) {
    if (json == null || json.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      } else {
        return null;
      }
    } catch (error) {
      return null;
    }
  }
}
