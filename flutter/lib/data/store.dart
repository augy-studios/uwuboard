// What the app keeps, under the same keys and in the same shapes the site keeps in localStorage
// (main-site/script.js, js/theme.js, js/tray.js, js/tour.js, js/sync.js, js/timeline.js): every
// value a string, JSON where the site's is JSON. So a feature ported from the site reads what it
// always did.
//
// One key-value store (shared_preferences) under a prefix that keeps the app's keys apart from
// plugins'. The guest's boards (`kanbanflow_guest_boards`) hold their images as data URLs and can
// run to megabytes, so off the web that one key lives in a file of its own (store_file_io.dart).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store_file_stub.dart' if (dart.library.io) 'store_file_io.dart';

/// The app's one key-value store: every value a string, under the site's localStorage keys.
class Store {
  Store._(this._preferences, this._files);

  static Store? _instance;
  static Store get instance {
    return _instance!;
  }

  static bool get isOpen {
    return _instance != null;
  }

  final SharedPreferences? _preferences;
  final BigValues? _files;
  // Tests and screenshots: kept in memory only, so nothing touches the device.
  final Map<String, String> _memory = {};
  final Map<String, StreamController<String?>> _changes = {};

  static const _prefix = 'ls.';

  /// Keys too big for the platform's preferences.
  static const bigKeys = {'kanbanflow_guest_boards'};

  static Future<Store> open() async {
    final preferences = await SharedPreferences.getInstance();
    final BigValues? files;
    if (kIsWeb) {
      files = null;
    } else {
      files = await BigValues.open(bigKeys);
    }
    final store = Store._(preferences, files);
    _instance = store;
    return store;
  }

  /// A store with these values and nothing written to the device.
  static Store memory([Map<String, String> values = const {}]) {
    final store = Store._(null, null);
    store._memory.addAll(values);
    _instance = store;
    return store;
  }

  String? get(String key) {
    if (_preferences == null) {
      return _memory[key];
    }
    if (_files != null && bigKeys.contains(key)) {
      return _files.get(key);
    }
    return _preferences.getString('$_prefix$key');
  }

  bool has(String key) {
    return get(key) != null;
  }

  /// Saves a value (or removes it, for null) and tells anything listening for that key.
  void put(String key, String? value) {
    if (_preferences == null) {
      if (value == null) {
        _memory.remove(key);
      } else {
        _memory[key] = value;
      }
    } else if (_files != null && bigKeys.contains(key)) {
      _files.put(key, value);
    } else if (value == null) {
      _preferences.remove('$_prefix$key');
    } else {
      _preferences.setString('$_prefix$key', value);
    }
    final listeners = _changes[key];
    if (listeners != null) {
      listeners.add(value);
    }
  }

  void remove(String key) {
    put(key, null);
  }

  /// Every change to one key, as localStorage's `storage` event would say it.
  Stream<String?> changes(String key) {
    var listeners = _changes[key];
    if (listeners == null) {
      listeners = StreamController<String?>.broadcast();
      _changes[key] = listeners;
    }
    return listeners.stream;
  }

  /// Every key the app holds (without the prefix): for the web-parity test.
  Iterable<String> get keys {
    if (_preferences == null) {
      return _memory.keys;
    }
    final preferenceKeys = _preferences.getKeys().where((key) {
      return key.startsWith(_prefix);
    }).map((key) {
      return key.substring(_prefix.length);
    });
    return [...preferenceKeys, if (_files != null) ..._files.keys];
  }

  /// Reads again what another window wrote (the desktop's widget windows share the store).
  Future<void> reload() async {
    if (_preferences != null) {
      await _preferences.reload();
    }
    if (_files != null) {
      await _files.reload();
    }
  }
}
