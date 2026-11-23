// The desktop app's own settings (docs/desktop-features-spec.md §20): one small JSON file in the
// app's per-user folder, read and merged on every write, so two parts of the app writing
// different keys never undo each other. A failed read is an empty map and a failed write is
// ignored. Nothing secret is ever kept here.
//
// Keys: bounds, maximized, trayHintShown (desk.dart); loginChosen (desk.dart); updateNotices
// (updater.dart); setupDone, pendingLook, useSystemAccent (welcome.dart); widgets
// (widgets_window.dart); trayStop, favourites, dueSeen (glance.dart); linkHandoff (desk.dart).
import 'dart:convert';
import 'dart:io';

class DeskSettings {
  DeskSettings._();

  /// The app's name as its folder has it, on every system.
  static const folderName = 'uwuBoard';

  /// %APPDATA%\uwuBoard, ~/Library/Application Support/uwuBoard, or ~/.config/uwuBoard.
  static String get directory {
    final environment = Platform.environment;
    if (Platform.isWindows) {
      String? appData = environment['APPDATA'];
      if (appData == null) {
        appData = '${environment['USERPROFILE']}\\AppData\\Roaming';
      }
      return '$appData\\$folderName';
    }
    String? home = environment['HOME'];
    if (home == null) {
      home = '';
    }
    if (Platform.isMacOS) {
      return '$home/Library/Application Support/$folderName';
    }
    String? configHome = environment['XDG_CONFIG_HOME'];
    if (configHome == null) {
      configHome = '$home/.config';
    }
    return '$configHome/$folderName';
  }

  /// For tests: another folder.
  static String? override;

  /// The folder in use: the test override if one is set, or else the usual one.
  static String get folder {
    final overrideFolder = override;
    if (overrideFolder != null) {
      return overrideFolder;
    }
    return directory;
  }

  static File get _file {
    return File('$folder${Platform.pathSeparator}settings.json');
  }

  /// Every setting, or an empty map if the file is missing or unreadable.
  static Map<String, dynamic> read() {
    try {
      final decoded = jsonDecode(_file.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else {
        return {};
      }
    } catch (error) {
      return {};
    }
  }

  /// One setting, or null if it's missing or not of type T.
  static T? get<T>(String key) {
    final value = read()[key];
    if (value is T) {
      return value;
    } else {
      return null;
    }
  }

  /// Merges `changes` into the file; a null value removes its key. Writes to a temporary file
  /// first and renames it over the old one, so a crash never leaves half a file.
  static void write(Map<String, dynamic> changes) {
    try {
      _file.parent.createSync(recursive: true);
      final merged = {...read(), ...changes};
      merged.removeWhere((key, value) {
        return value == null;
      });
      final temporaryFile = File('${_file.path}.tmp');
      temporaryFile.writeAsStringSync(jsonEncode(merged));
      temporaryFile.renameSync(_file.path);
    } catch (error) {
      // Not kept: the default comes back next time.
    }
  }
}
