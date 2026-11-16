// The desktop app updating itself (docs/desktop-features-spec.md §2, §3): as it opens, in the
// update window (splash.dart, up to 10 seconds), 30 seconds after the main window, then every
// hour, soon after the computer wakes, and when the tray's "Check for updates..." asks, which
// says what it found either way.
//
// It reads latest.yml (Windows), latest-mac.yml (macOS), latest-linux.yml or
// latest-linux-arm64.yml (Linux, by processor) from the newest GitHub release
// (releases/latest/download/ always points at it): the version, the file and its SHA-512, checked
// before anything's installed. installers/write-latest-yml.mjs writes them, in electron-updater's
// format.
//
//   Windows .exe (NSIS), Linux .AppImage,   downloaded in the background; a notification, the tray
//   macOS in a folder it can write to       and the title bar offer Restart to update, and it's
//                                           installed on quit anyway.
//   Windows .msi, Linux .deb or .rpm,       told only, with a link to the release to download it.
//   a Mac app it can't write to, a copy
//   run from source
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import '../app/env.dart';
import 'desk.dart';
import 'notify.dart';
import 'settings.dart';

/// What the update window says: its line, a smaller line under it, how far (0 to 100, -1 for no
/// telling, null for no bar), and whether Later's offered.
class SplashStatus {
  const SplashStatus(this.text, {this.detail = '', this.percent, this.later = false});
  final String text;
  final String detail;
  final int? percent;
  final bool later;
}

/// One update, as an update file (latest.yml and the like) describes it.
class UpdateInfo {
  UpdateInfo({required this.version, required this.file, required this.sha512, required this.size});
  final String version;
  final String file;
  final String sha512;
  final int size;

  /// Reads an update file in electron-updater's format. Of the files it lists, picks the one for
  /// this processor (`arm64` or not), and on macOS the .zip rather than the .dmg. Null when the
  /// text isn't such a file or misses the version, the file or its SHA-512.
  static UpdateInfo? parse(String text, {bool arm64 = false}) {
    Object? document;
    try {
      document = loadYaml(text);
    } catch (error) {
      return null;
    }
    if (document is! YamlMap || document['version'] == null) {
      return null;
    }
    List<dynamic> fileEntries;
    if (document['files'] is YamlList) {
      fileEntries = document['files'] as YamlList;
    } else {
      fileEntries = const [];
    }
    final files = fileEntries.whereType<YamlMap>().toList();
    YamlMap? pick;
    if (files.isNotEmpty) {
      // macOS lists a .zip and a .dmg for each processor: the .zip for this one.
      final zips = files.where((fileEntry) {
        return '${fileEntry['url']}'.endsWith('.zip');
      }).toList();
      List<YamlMap> candidates;
      if (zips.isNotEmpty) {
        candidates = zips;
      } else {
        candidates = files;
      }
      final forThisProcessor = candidates.where((fileEntry) {
        return '${fileEntry['url']}'.contains('arm64') == arm64;
      }).firstOrNull;
      if (forThisProcessor != null) {
        pick = forThisProcessor;
      } else if (zips.isEmpty) {
        pick = candidates.first;
      } else {
        pick = null;
      }
    }
    // The picked file's name and hash, or else the ones at the top of the update file.
    Object? fileValue;
    if (pick != null) {
      fileValue = pick['url'];
    }
    if (fileValue == null) {
      fileValue = document['path'];
    }
    if (fileValue == null) {
      fileValue = '';
    }
    final file = '$fileValue';
    Object? hashValue;
    if (pick != null) {
      hashValue = pick['sha512'];
    }
    if (hashValue == null) {
      hashValue = document['sha512'];
    }
    if (hashValue == null) {
      hashValue = '';
    }
    final hash = '$hashValue';
    if (file.isEmpty || hash.isEmpty) {
      return null;
    }
    num? sizeValue;
    if (pick != null) {
      sizeValue = pick['size'] as num?;
    }
    int size;
    if (sizeValue == null) {
      size = 0;
    } else {
      size = sizeValue.toInt();
    }
    return UpdateInfo(version: '${document['version']}', file: file, sha512: hash, size: size);
  }
}

class Updater {
  Updater._();

  static const _baseUrl = 'https://github.com/augy-studios/uwuboard/releases/latest/download';
  static const startupWait = Duration(seconds: 10);
  static String get userAgent {
    return 'uwuBoardDesktop/${Env.version}';
  }

  static final available = ValueNotifier<String?>(null);
  static final ready = ValueNotifier<String?>(null);
  static final checking = ValueNotifier<bool>(false);
  static final splash = ValueNotifier<SplashStatus>(const SplashStatus('Starting…'));

  /// Completed when Later is pressed in the update window.
  static Completer<void>? _laterChosen;

  static String? _notifiedFor;
  static String? _failedFor;
  static String? _downloadingVersion;
  static File? _downloadedFile;
  static Directory? _macStagedApp;

  /// True while the check running was asked for from the tray (so it says what it found).
  static bool _askedByUser = false;
  static Timer? _checkTimer;
  static DateTime _lastTick = DateTime.now();
  static DateTime _checkedAt = DateTime.now();

  /// An Arm processor: Dart names it at the end of its version, as in `on "windows_arm64"`.
  static bool get arm64 {
    return RegExp(r'_arm64"?\s*$').hasMatch(Platform.version.trim());
  }

  /// The update file for this system.
  static String get yamlFileName {
    if (Desktop.windows) {
      return 'latest.yml';
    }
    if (Desktop.mac) {
      return 'latest-mac.yml';
    }
    if (arm64) {
      return 'latest-linux-arm64.yml';
    } else {
      return 'latest-linux.yml';
    }
  }

  /// Whether update notices are wanted (they're on unless turned off).
  static bool get _wanted {
    return DeskSettings.get<bool>('updateNotices') != false;
  }

  static String get executableDirectory {
    return File(Platform.resolvedExecutable).parent.path;
  }

  /// The macOS .app bundle: three folders up from the executable inside it.
  static String get macAppBundle {
    return File(Platform.resolvedExecutable).parent.parent.parent.path;
  }

  /// Whether a file can be written in this folder (tried by writing and deleting one).
  static bool _writable(String path) {
    try {
      final probe = File('$path${Platform.pathSeparator}.uwuboard-write-test');
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } catch (error) {
      return false;
    }
  }

  /// Whether this copy can install an update itself: the .exe install is told apart by the
  /// uninstaller beside it.
  static bool get canInstall {
    if (Desktop.fromSource) {
      return false;
    }
    if (Desktop.windows) {
      return File('$executableDirectory\\Uninstall ${Desktop.name}.exe').existsSync();
    }
    if (Desktop.linux) {
      final appImage = Platform.environment['APPIMAGE'];
      return appImage != null && appImage.isNotEmpty;
    }
    if (Desktop.mac) {
      final bundle = macAppBundle;
      return bundle.endsWith('.app') &&
          !bundle.startsWith('/Volumes/') &&
          !bundle.contains('/AppTranslocation/') &&
          _writable(bundle) &&
          _writable(File(bundle).parent.path);
    }
    return false;
  }

  /// Whether `version` is newer than `otherVersion`, comparing the first three numbers of each
  /// (a missing or unreadable number counts as 0).
  static bool newer(String version, String otherVersion) {
    List<int> parts(String text) {
      return text.split(RegExp(r'[.+-]')).take(3).map((part) {
        final number = int.tryParse(part);
        if (number == null) {
          return 0;
        }
        return number;
      }).toList();
    }

    final versionParts = parts(version);
    final otherParts = parts(otherVersion);
    for (var index = 0; index < 3; index = index + 1) {
      int part;
      if (index < versionParts.length) {
        part = versionParts[index];
      } else {
        part = 0;
      }
      int otherPart;
      if (index < otherParts.length) {
        otherPart = otherParts[index];
      } else {
        otherPart = 0;
      }
      if (part != otherPart) {
        return part > otherPart;
      }
    }
    return false;
  }

  /// The newest release's update, or null if it isn't newer than this copy. Throws when the
  /// update file can't be fetched or read.
  static Future<UpdateInfo?> find() async {
    final response = await http
        .get(Uri.parse('$_baseUrl/$yamlFileName?t=${DateTime.now().millisecondsSinceEpoch}'), headers: {'User-Agent': userAgent, 'Cache-Control': 'no-cache'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw HttpException('update file: ${response.statusCode}');
    }
    final info = UpdateInfo.parse(utf8.decode(response.bodyBytes), arm64: arm64);
    if (info == null) {
      throw const FormatException('update file');
    }
    if (newer(info.version, Env.version)) {
      return info;
    } else {
      return null;
    }
  }

  /// Downloads the update into a temporary folder (unless it's there already), telling
  /// `progress` the bytes received so far and the total, then checks its SHA-512.
  static Future<File> download(UpdateInfo info, {void Function(int received, int total)? progress}) async {
    final folder = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}uwuboard-update');
    folder.createSync(recursive: true);
    final downloadFile = File('${folder.path}${Platform.pathSeparator}${info.file.split('/').last}');
    if (downloadFile.existsSync() && await _hash(downloadFile) == info.sha512) {
      return downloadFile;
    }
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse('$_baseUrl/${Uri.encodeComponent(info.file)}'));
      request.headers['User-Agent'] = userAgent;
      final response = await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('download: ${response.statusCode}');
      }
      int total;
      final contentLength = response.contentLength;
      if (contentLength != null) {
        total = contentLength;
      } else {
        total = info.size;
      }
      final sink = downloadFile.openWrite();
      var received = 0;
      await for (final chunk in response.stream.timeout(const Duration(seconds: 60))) {
        sink.add(chunk);
        received = received + chunk.length;
        if (progress != null) {
          progress(received, total);
        }
      }
      await sink.close();
    } finally {
      client.close();
    }
    if (await _hash(downloadFile) != info.sha512) {
      try {
        downloadFile.deleteSync();
      } catch (error) {
        // Left behind; it's replaced next time.
      }
      throw const FormatException("the download's SHA-512 doesn't match");
    }
    return downloadFile;
  }

  /// A file's SHA-512, in base 64 as the update file has it.
  static Future<String> _hash(File file) async {
    final digest = await sha512.bind(file.openRead()).first;
    return base64.encode(digest.bytes);
  }

  /// Keeps the downloaded update for installing; on macOS, unzips the new app beside it first.
  static Future<void> _stage(File file) async {
    _downloadedFile = file;
    if (!Desktop.mac) {
      return;
    }
    final stagingFolder = Directory('${Directory.systemTemp.path}/uwuboard-staged');
    if (stagingFolder.existsSync()) {
      stagingFolder.deleteSync(recursive: true);
    }
    stagingFolder.createSync(recursive: true);
    final result = await Process.run('/usr/bin/ditto', ['-x', '-k', file.path, stagingFolder.path]);
    if (result.exitCode != 0) {
      throw ProcessException('ditto', [], '${result.stderr}', result.exitCode);
    }
    final app = stagingFolder.listSync().whereType<Directory>().where((directory) {
      return directory.path.endsWith('.app');
    }).firstOrNull;
    if (app == null) {
      throw const FormatException('no .app in the update');
    }
    _macStagedApp = app;
  }

  // macOS: once this process has gone, swap the new app in for the old, keeping the old if the
  // swap fails part-way, clear the quarantine flag, then open it again if asked. Detached.
  static const _swapScript = r'''
while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
old="$3.old-$$"
if mv "$3" "$old"; then
  if mv "$2" "$3"; then rm -rf "$old"; else mv "$old" "$3"; fi
fi
xattr -dr com.apple.quarantine "$3" 2>/dev/null
rm -rf "$4"
[ "$5" = 1 ] && open "$3"
''';

  static bool _installing = false;

  /// Starts installing the staged update, to finish once this copy has quit: the installer on
  /// Windows, the new AppImage over the old on Linux, the swap script on macOS. With `relaunch`,
  /// the new version opens afterwards.
  static Future<void> _installOnExit({required bool relaunch}) async {
    final downloadedFile = _downloadedFile;
    if (_installing || downloadedFile == null) {
      return;
    }
    _installing = true;
    final stagedApp = _macStagedApp;
    if (Desktop.windows) {
      // The installer closes this copy, installs over it and, with --force-run, opens it again.
      await Process.start(downloadedFile.path, ['--updated', '/S', if (relaunch) '--force-run'], mode: ProcessStartMode.detached);
    } else if (Desktop.linux) {
      final target = Platform.environment['APPIMAGE']!;
      final newFile = File('$target.new');
      await downloadedFile.copy(newFile.path);
      await Process.run('chmod', ['755', newFile.path]);
      newFile.renameSync(target);
      if (relaunch) {
        await Process.start(target, const [], mode: ProcessStartMode.detached);
      }
    } else if (Desktop.mac && stagedApp != null) {
      String relaunchFlag;
      if (relaunch) {
        relaunchFlag = '1';
      } else {
        relaunchFlag = '0';
      }
      await Process.start('/bin/sh', [
        '-c',
        _swapScript,
        'uwuboard-update',
        '$pid',
        stagedApp.path,
        macAppBundle,
        stagedApp.parent.path,
        relaunchFlag,
      ], mode: ProcessStartMode.detached);
    }
  }

  /// Set by desktop_main.dart: puts the update window up over the app, for Restart to update.
  static Future<void> Function()? showSplash;

  /// Puts the update window up, starts installing, and quits.
  static Future<void> restartToUpdate() async {
    if (ready.value == null) {
      return;
    }
    final showSplashWindow = showSplash;
    if (showSplashWindow != null) {
      await showSplashWindow();
    }
    splash.value = const SplashStatus('Installing update…', percent: -1);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await _installOnExit(relaunch: true);
    await Desktop.quit();
  }

  /// Starts the checks: installing on quit, a first check after 30 seconds, then hourly, and soon
  /// after the computer wakes.
  static void start() {
    if (Desktop.fromSource) {
      return;
    }
    Desktop.beforeQuit.add(() async {
      if (ready.value != null && !_installing && canInstall) {
        await _installOnExit(relaunch: false);
      }
    });
    Timer(const Duration(seconds: 30), check);
    _lastTick = DateTime.now();
    final oldTimer = _checkTimer;
    if (oldTimer != null) {
      oldTimer.cancel();
    }
    _checkTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      final now = DateTime.now();
      // Asleep overnight: the clock jumps. What came out meanwhile, soon after waking.
      final slept = now.difference(_lastTick) > const Duration(minutes: 5);
      _lastTick = now;
      if (slept) {
        Timer(const Duration(seconds: 20), check);
      } else if (now.difference(_checkedAt) >= const Duration(hours: 1)) {
        check();
      }
    });
  }

  /// One check for an update. When asked for from the tray, says what it found either way.
  static Future<void> check() async {
    if (checking.value) {
      return;
    }
    checking.value = true;
    _checkedAt = DateTime.now();
    final asked = _askedByUser;
    try {
      final info = await find();
      if (info == null) {
        if (asked) {
          DeskNotify.show(title: 'You’re up to date', body: '${Desktop.name} ${Env.version} is the newest version.');
        }
        return;
      }
      _found(info, asked: asked);
    } catch (error) {
      if (asked) {
        DeskNotify.show(title: 'Couldn’t check for updates', body: 'Check your connection and try again.');
      }
    } finally {
      checking.value = false;
      _askedByUser = false;
    }
  }

  /// An update's out. Where this copy can't install it, a notification links to the release;
  /// otherwise it's downloaded in the background and a notification offers Restart to update.
  static void _found(UpdateInfo info, {required bool asked}) {
    available.value = info.version;
    final install = canInstall;
    if (asked && install) {
      if (ready.value == info.version) {
        _sayReady(info.version, force: true);
      } else {
        DeskNotify.show(title: '${Desktop.name} ${info.version} is out', body: 'It’s downloading. You’ll be told when it’s ready to install.');
      }
    }
    if (!install) {
      if (_notifiedFor == info.version && !asked) {
        return;
      }
      if (!asked && !_wanted) {
        return;
      }
      _notifiedFor = info.version;
      DeskNotify.show(
        title: '${Desktop.name} ${info.version} is out',
        body: 'Click to download it from GitHub, then install it over this one.',
        onClick: () {
          Desktop.openExternal(Desktop.releases);
        },
      );
      return;
    }
    if (ready.value == info.version || _downloadingVersion == info.version) {
      return;
    }
    _downloadingVersion = info.version;
    download(info)
        .then((file) async {
          await _stage(file);
          _downloadingVersion = null;
          ready.value = info.version;
          _sayReady(info.version);
        })
        .catchError((Object error) {
          _downloadFailed(info.version);
        });
  }

  /// The notification that an update is ready to install (once per version, unless `force`).
  static void _sayReady(String version, {bool force = false}) {
    if (!force && (_notifiedFor == version || !_wanted)) {
      return;
    }
    _notifiedFor = version;
    DeskNotify.show(
      title: '${Desktop.name} $version is ready',
      body: 'Click to restart and update. Otherwise it updates the next time you quit.',
      onClick: restartToUpdate,
    );
  }

  /// The notification that a download failed (once per version).
  static void _downloadFailed(String version) {
    _downloadingVersion = null;
    if (_failedFor == version || !_wanted) {
      return;
    }
    _failedFor = version;
    DeskNotify.show(
      title: 'Couldn’t download ${Desktop.name} $version',
      body: 'It tries again within the hour, or click to download it from GitHub.',
      onClick: () {
        Desktop.openExternal(Desktop.releases);
      },
    );
  }

  /// The tray's "Check for updates...": a check now, and a notification of what it found.
  static void checkNow() {
    if (Desktop.fromSource) {
      DeskNotify.show(title: 'No updates to check for', body: 'Run from source, there is nothing to update. The installed app checks for itself.');
      return;
    }
    if (checking.value) {
      return;
    }
    _askedByUser = true;
    check();
  }

  /// The update window's Later button.
  static void later() {
    final laterChosen = _laterChosen;
    if (laterChosen != null) {
      laterChosen.complete();
    }
  }

  /// As the app opens: checks for an update, and downloads and installs one it can install itself.
  /// Completes once the app should open; never, if it's restarting into the new version. From
  /// source there's nothing to update, unless UWUBOARD_SPLASH_DEMO=1 runs through the steps with
  /// made-up numbers.
  static Future<void> startup() async {
    final demo = Platform.environment['UWUBOARD_SPLASH_DEMO'] == '1';
    if (Desktop.fromSource && !demo) {
      return;
    }
    if (demo) {
      return _demo();
    }
    splash.value = const SplashStatus('Checking for updates…', percent: -1);
    UpdateInfo? info;
    try {
      info = await find().timeout(startupWait);
    } catch (error) {
      info = null;
    }
    // Nothing to install now: open, and mention an update this copy can't install a bit later.
    if (info == null || !canInstall) {
      final found = info;
      if (found != null) {
        Timer(const Duration(seconds: 5), () {
          _found(found, asked: false);
        });
      }
      return _opening();
    }
    // Download it, showing the progress, until it's done or Later is pressed.
    available.value = info.version;
    _downloadingVersion = info.version;
    splash.value = SplashStatus('Downloading update', detail: 'Version ${info.version}', percent: 0, later: true);
    _laterChosen = Completer<void>();
    final done = Completer<Object?>();
    download(
      info,
      progress: (received, total) {
        final laterChosen = _laterChosen;
        if (laterChosen == null || laterChosen.isCompleted) {
          return;
        }
        int percent;
        if (total > 0) {
          percent = received * 100 ~/ total;
        } else {
          percent = -1;
        }
        splash.value = SplashStatus(
          'Downloading update',
          detail: '${_megabytes(received)} of ${_megabytes(total)} MB',
          percent: percent,
          later: true,
        );
      },
    ).then((file) {
      if (!done.isCompleted) {
        done.complete(file);
      }
    }).catchError((Object error) {
      if (!done.isCompleted) {
        done.complete(error);
      }
    });
    final outcome = await Future.any<Object?>([
      done.future,
      _laterChosen!.future.then((value) {
        return 'later';
      }),
    ]);
    final version = info.version;
    // Later: open now, and finish the download in the background.
    if (outcome == 'later') {
      done.future.then((result) async {
        if (result is File) {
          try {
            await _stage(result);
            _downloadingVersion = null;
            ready.value = version;
            _sayReady(version);
          } catch (error) {
            _downloadFailed(version);
          }
        } else {
          _downloadFailed(version);
        }
      });
      return _opening();
    }
    if (outcome is! File) {
      _downloadingVersion = null;
      return _opening();
    }
    try {
      await _stage(outcome);
    } catch (error) {
      _downloadingVersion = null;
      return _opening();
    }
    // Downloaded: restart into the new version, and never let the app open.
    _downloadingVersion = null;
    ready.value = version;
    await restartToUpdate();
    await Completer<void>().future;
  }

  /// Bytes as megabytes, with one decimal under 10 MB.
  static String _megabytes(int bytes) {
    int decimals;
    if (bytes < 10e6) {
      decimals = 1;
    } else {
      decimals = 0;
    }
    return (bytes / 1e6).toStringAsFixed(decimals);
  }

  /// The update window's last words before the app opens.
  static Future<void> _opening() async {
    splash.value = const SplashStatus('Starting…');
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  /// UWUBOARD_SPLASH_DEMO=1: the update window's steps with made-up numbers, for a look at it.
  static Future<void> _demo() async {
    splash.value = const SplashStatus('Checking for updates…', percent: -1);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    const total = 34600000;
    _laterChosen = Completer<void>();
    for (var percent = 0; percent <= 100; percent = percent + 4) {
      if (_laterChosen!.isCompleted) {
        return _opening();
      }
      splash.value = SplashStatus('Downloading update', detail: '${_megabytes(total * percent ~/ 100)} of ${_megabytes(total)} MB', percent: percent, later: true);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    splash.value = const SplashStatus('Installing update…', percent: -1);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    return _opening();
  }
}
