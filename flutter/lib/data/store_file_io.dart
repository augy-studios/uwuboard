// The store's big values, each in a file of its own in the app's support folder, read into
// memory as the app opens so reading stays as immediate as localStorage's (store.dart).
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class BigValues {
  BigValues._(this._directory, this._fileKeys);

  final Directory _directory;
  final Set<String> _fileKeys;
  final Map<String, String> _values = {};
  Future<void> _writing = Future.value();

  /// Makes the folder the files live in and reads every file into memory.
  static Future<BigValues?> open(Set<String> keys) async {
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final storeDirectory = Directory('${supportDirectory.path}${Platform.pathSeparator}store');
      await storeDirectory.create(recursive: true);
      final bigValues = BigValues._(storeDirectory, keys);
      await bigValues.reload();
      return bigValues;
    } catch (error) {
      // No folder to write to: the key falls back to shared_preferences.
      return null;
    }
  }

  File _fileFor(String key) {
    return File('${_directory.path}${Platform.pathSeparator}$key.json');
  }

  /// Reads every key's file again, so this window sees what another window wrote.
  Future<void> reload() async {
    for (final key in _fileKeys) {
      try {
        final file = _fileFor(key);
        if (await file.exists()) {
          _values[key] = await file.readAsString();
        } else {
          _values.remove(key);
        }
      } catch (error) {
        // Unreadable: as if it weren't there.
      }
    }
  }

  String? get(String key) {
    return _values[key];
  }

  Iterable<String> get keys {
    return _values.keys;
  }

  // One write at a time, each to a temporary file moved into place, so a crash mid-write
  // never leaves half a file.
  void put(String key, String? value) {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    _writing = _writing.then((previousWrite) async {
      try {
        final file = _fileFor(key);
        if (value == null) {
          if (await file.exists()) {
            await file.delete();
          }
          return;
        }
        final temporaryFile = File('${file.path}.tmp');
        await temporaryFile.writeAsString(value, flush: true);
        await temporaryFile.rename(file.path);
      } catch (error) {
        // Kept in memory for this run.
      }
    });
  }
}
