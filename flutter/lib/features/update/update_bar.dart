// The Android app updating itself from GitHub Releases (docs/flutter-android-app-spec.md §8):
// the site's /api/app-release names the newest release and every one before it; a newer one
// shows in a bar at the top, and the Updates page (always in Material You, whichever look the
// app is in) says what's new in each version, newest first, downloads the APK, checks it
// against GitHub's SHA-256, and hands it to Android's installer. Looked up as the app opens and
// again on coming back to it after an hour. "Not now" lasts until the app's next opened.
//
// "New versions of the app" on the same page joins the FCM topic the site pushes to the moment
// a release is published (main-site/api/push/release.js, flutter/FIREBASE-SETUP.md); tapping
// that notification opens this page. Only where the APK was built with Firebase in it.
//
// The Play build has no updater of its own (Play updates it): its page shows the versions and
// sends the person to Play.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api.dart';
import '../../app/env.dart';
import '../../app/nav.dart';
import '../../data/store.dart';
import '../../native/bridge.dart';
import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/wavy_progress.dart';
import 'release_notes.dart';

const _releasesKey = 'app.releaseNotices';
const playListing = 'https://play.google.com/store/apps/details?id=org.uwuapps.board';

/// Whether `version` comes after `otherVersion`, number by number: 1.10.0 after 1.9.0. The same
/// as newer() in main-site/api/app-release.js.
bool newerVersion(String version, String otherVersion) {
  // The numbers of a version, ignoring anything in each part that isn't a digit.
  List<int> numbersOf(String text) {
    return text.split('.').map((part) {
      final number = int.tryParse(part.replaceAll(RegExp(r'\D'), ''));
      if (number == null) {
        return 0;
      }
      return number;
    }).toList();
  }

  final numbers = numbersOf(version);
  final otherNumbers = numbersOf(otherVersion);
  for (var index = 0; index < numbers.length || index < otherNumbers.length; index = index + 1) {
    int number;
    if (index < numbers.length) {
      number = numbers[index];
    } else {
      number = 0;
    }
    int otherNumber;
    if (index < otherNumbers.length) {
      otherNumber = otherNumbers[index];
    } else {
      otherNumber = 0;
    }
    final difference = number - otherNumber;
    if (difference != 0) {
      return difference > 0;
    }
  }
  return false;
}

/// The text style with its colour (and, when given, its weight) changed, or null when there is
/// no style to start from.
TextStyle? _recoloured(TextStyle? base, Color color, {FontWeight? fontWeight}) {
  if (base == null) {
    return null;
  }
  return base.copyWith(color: color, fontWeight: fontWeight);
}

/// Looks up the newest release, downloads and installs it, and joins or leaves the release
/// notifications; everything the bar and the Updates page show.
class AndroidUpdates extends ChangeNotifier with WidgetsBindingObserver {
  AndroidUpdates._();
  static final AndroidUpdates I = AndroidUpdates._();

  /// The site's whole answer: the newest release, and `history`, every release newest first.
  Map<String, dynamic>? latest;
  bool loading = false;
  bool failed = false;
  bool dismissed = false;
  DateTime? _checkedAt;

  /// Downloading: 0 to 1, or null.
  double? progress;
  String? error;

  /// "New versions of the app": on, off, or null while it's being changed.
  bool? notices;

  bool _started = false;

  String get mine {
    final nativeVersion = Native.version;
    if (nativeVersion == null) {
      return Env.version;
    }
    return nativeVersion;
  }

  /// The newest release, when it's newer than this copy.
  Map<String, dynamic>? get newer {
    final release = latest;
    if (release == null || release['version'] is! String) {
      return null;
    }
    if (newerVersion(release['version'] as String, mine)) {
      return release;
    } else {
      return null;
    }
  }

  /// The Play build: Play updates it, so no updater of its own.
  bool get play {
    if (isPlayBuild) {
      return true;
    }
    final info = Native.info;
    if (info == null) {
      return false;
    }
    return info['play'] == true;
  }

  bool get offered {
    return newer != null && !dismissed && !play;
  }

  List<Map<String, dynamic>> get history {
    List<dynamic> releases = const [];
    final answer = latest;
    if (answer != null) {
      final listed = answer['history'] as List?;
      if (listed != null) {
        releases = listed;
      }
    }
    return [
      for (final entry in releases)
        if (entry is Map) Map<String, dynamic>.from(entry),
    ];
  }

  /// Once, on Android: watches for the app coming back, listens for the release notification
  /// being tapped, and looks for a newer release.
  void start() {
    if (_started || !Env.android) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    notices = Store.I.get(_releasesKey) == '1';
    // The notification "x.y.z is out", tapped: this page.
    Native.on('App', 'openUpdates', (arguments) {
      openUpdates();
    });
    check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    final lastCheck = _checkedAt;
    if (lastCheck == null || DateTime.now().difference(lastCheck) > const Duration(hours: 1)) {
      check();
    }
  }

  /// `fresh` asks past the site's cache, for a release published a moment ago.
  Future<void> check({bool fresh = false}) async {
    _checkedAt = DateTime.now();
    loading = true;
    notifyListeners();
    try {
      String cacheBuster;
      if (fresh) {
        cacheBuster = '?v=${DateTime.now().millisecondsSinceEpoch}';
      } else {
        cacheBuster = '';
      }
      final uri = Api.uri('/app-release$cacheBuster');
      final response = await Api.client.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      final data = jsonDecode(response.body);
      if (data is Map) {
        latest = Map<String, dynamic>.from(data);
      }
      failed = false;
    } catch (error) {
      failed = latest == null;
    }
    loading = false;
    notifyListeners();
  }

  void dismiss() {
    dismissed = true;
    notifyListeners();
  }

  /// Downloads the newer APK (showing progress), checks it against GitHub's SHA-256, and hands
  /// it to Android's installer; on a failure, says what went wrong.
  Future<void> install() async {
    final release = newer;
    if (release == null || progress != null) {
      return;
    }
    error = null;
    progress = 0;
    notifyListeners();
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}uwuboard-${release['version']}.apk');
      final response = await Api.client.send(http.Request('GET', Uri.parse('${release['apk']}')));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      int total;
      final size = release['size'] as num?;
      final contentLength = response.contentLength;
      if (size != null) {
        total = size.toInt();
      } else if (contentLength != null) {
        total = contentLength;
      } else {
        total = 0;
      }
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received = received + chunk.length;
        if (total > 0) {
          progress = received / total;
          notifyListeners();
        }
      }
      await sink.close();
      final checksum = (await sha256.bind(file.openRead()).first).toString();
      final expected = release['sha256'];
      if (expected is String && expected.isNotEmpty && expected.toLowerCase() != checksum) {
        await file.delete();
        throw StateError('checksum');
      }
      progress = 1;
      notifyListeners();
      await Native.call('App', 'installApk', {'path': file.path});
      progress = null;
    } catch (caught) {
      progress = null;
      if (caught is StateError && caught.message == 'checksum') {
        error = 'The download didn’t match GitHub’s checksum, so it wasn’t installed. Try again.';
      } else if (caught is NativeError && caught.code == 'permission') {
        error = 'Allow uwuBoard to install apps, then press Update again.';
      } else {
        error = 'Couldn’t download the update. Check your connection and try again.';
      }
    }
    notifyListeners();
  }

  /// Joins or leaves the release topic (Firebase), asking for notifications first.
  Future<void> setNotices(bool on) async {
    final previous = notices;
    notices = null;
    notifyListeners();
    try {
      await Native.call('App', 'setReleases', {'on': on});
      notices = on;
      String storedValue;
      String toastText;
      if (on) {
        storedValue = '1';
      } else {
        storedValue = '0';
      }
      Store.I.put(_releasesKey, storedValue);
      if (on) {
        toastText = 'You’ll get a notification the moment a new version is out.';
      } else {
        toastText = 'No more notifications of new versions.';
      }
      AppNav.toast(toastText);
    } on NativeError catch (nativeError) {
      notices = previous;
      String toastText;
      if (nativeError.code == 'permission') {
        toastText = 'Notifications are off for uwuBoard. Turn them on in Android’s settings, then try again.';
      } else {
        toastText = 'Couldn’t reach Firebase. Check your connection and try again.';
      }
      AppNav.toast(toastText, error: true);
      if (nativeError.code == 'permission') {
        Native.tryCall('App', 'openSettings', {'page': 'notifications'});
      }
    }
    notifyListeners();
  }
}

/// The bar at the top while a newer version is out.
class UpdateBar extends StatelessWidget {
  const UpdateBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AndroidUpdates.I,
      builder: (context, child) {
        final updates = AndroidUpdates.I;
        if (!updates.offered) {
          return const SizedBox.shrink();
        }
        final colors = UwuColors.of(context);
        return Material(
          color: colors.brandFill,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text('uwuBoard ${updates.newer!['version']} is out.', style: TextStyle(color: colors.onBrand, fontSize: 14)),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: colors.surfaceStrong, foregroundColor: colors.ink),
                    onPressed: openUpdates,
                    child: const Text('Update'),
                  ),
                  TextButton(
                    onPressed: updates.dismiss,
                    style: TextButton.styleFrom(foregroundColor: colors.onBrand),
                    child: const Text('Not now'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The device's Material You schemes, as the app's root last had them (app.dart), for the
/// Updates page, which is always in Material You.
ColorScheme? lightDynamicScheme;
ColorScheme? darkDynamicScheme;

/// Opens the Updates page, looking for a newer release (past the site's cache) as it opens.
Future<void> openUpdates() async {
  final navigator = AppNav.navigatorKey.currentState;
  if (navigator == null) {
    return;
  }
  AndroidUpdates.I.check(fresh: true);
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (context) {
        return const UpdatesPage();
      },
      settings: const RouteSettings(name: 'updates'),
    ),
  );
}

/// The Updates page: this version, the newest and its Update button, the release notifications
/// switch, and what's new in every version, newest first.
class UpdatesPage extends StatelessWidget {
  const UpdatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = ThemeController.I.brightness;
    ColorScheme? dynamicScheme;
    if (brightness == Brightness.dark) {
      dynamicScheme = darkDynamicScheme;
    } else {
      dynamicScheme = lightDynamicScheme;
    }
    final theme = buildTheme(look: lookMaterial, brightness: brightness, brand: ThemeController.I.colorTheme.color, dynamicScheme: dynamicScheme);
    return Theme(data: theme, child: const _UpdatesBody());
  }
}

/// The Updates page's content: a large app bar, the status card, the notifications switch
/// (where push is built in), and the timeline of every version. Pull down to look again.
class _UpdatesBody extends StatelessWidget {
  const _UpdatesBody();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: AndroidUpdates.I,
      builder: (context, child) {
        final updates = AndroidUpdates.I;
        final newer = updates.newer;
        final history = updates.history;
        // The notifications switch: off while unknown, and not pressable while it's changing.
        bool noticesOn;
        ValueChanged<bool>? onNoticesChanged;
        final notices = updates.notices;
        if (notices == null) {
          noticesOn = false;
          onNoticesChanged = null;
        } else {
          noticesOn = notices;
          onNoticesChanged = updates.setNotices;
        }
        String emptyText;
        if (updates.failed) {
          emptyText = 'Couldn’t load the versions. Pull down to try again.';
        } else {
          emptyText = 'No versions published yet.';
        }
        return Scaffold(
          backgroundColor: scheme.surface,
          body: RefreshIndicator(
            onRefresh: () {
              return updates.check(fresh: true);
            },
            child: CustomScrollView(
              slivers: [
                SliverAppBar.large(
                  backgroundColor: scheme.surface,
                  surfaceTintColor: scheme.surfaceTint,
                  leading: IconButton(
                    tooltip: 'Back',
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: AppIcon('arrow-left', color: scheme.onSurface),
                  ),
                  title: const Text('Updates'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverList.list(
                    children: [
                      _statusCard(context, updates, newer),
                      if (Native.has('push')) ...[
                        const SizedBox(height: 12),
                        Card.filled(
                          color: scheme.surfaceContainer,
                          child: SwitchListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            secondary: AppIcon('bell', color: scheme.onSurfaceVariant),
                            title: const Text('New versions of the app'),
                            subtitle: const Text('A notification the moment a new version is out, even with the app closed.'),
                            value: noticesOn,
                            onChanged: onNoticesChanged,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text('Every version', style: _recoloured(textTheme.titleMedium, scheme.primary)),
                      ),
                      const SizedBox(height: 8),
                      if (history.isEmpty && updates.loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 24),
                          child: WavyProgress(label: 'Loading the versions'),
                        ),
                      if (history.isEmpty && !updates.loading)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            emptyText,
                            style: _recoloured(textTheme.bodyMedium, scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverToBoxAdapter(child: _Timeline(history: history, mine: updates.mine)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The card at the top: up to date (with Check for updates), or the newer version is out
  /// (with its Update button, the download's progress, or Update on Google Play).
  Widget _statusCard(BuildContext context, AndroidUpdates updates, Map<String, dynamic>? newer) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final upToDate = newer == null;
    Color cardColour;
    Color headingColour;
    Color versionColour;
    String heading;
    if (upToDate) {
      cardColour = scheme.surfaceContainerHigh;
      headingColour = scheme.onSurface;
      versionColour = scheme.onSurfaceVariant;
      heading = 'You’re up to date';
    } else {
      cardColour = scheme.primaryContainer;
      headingColour = scheme.onPrimaryContainer;
      versionColour = scheme.onPrimaryContainer;
      heading = 'uwuBoard ${newer['version']} is out';
    }
    final progress = updates.progress;
    double progressFraction = 0;
    if (progress != null) {
      progressFraction = progress;
    }
    String updateLabel = 'Update';
    if (!upToDate) {
      final sizeText = _size(newer['size']);
      if (sizeText.isEmpty) {
        updateLabel = 'Update';
      } else {
        updateLabel = 'Update ($sizeText)';
      }
    }
    return Card.filled(
      color: cardColour,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('assets/images/icon-512.png', width: 52, height: 52, excludeFromSemantics: true)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heading,
                        style: _recoloured(textTheme.titleLarge, headingColour),
                      ),
                      const SizedBox(height: 2),
                      Text('This is version ${updates.mine}.', style: _recoloured(textTheme.bodyMedium, versionColour)),
                    ],
                  ),
                ),
              ],
            ),
            if (!upToDate) ...[
              const SizedBox(height: 16),
              if (updates.progress != null) ...[
                WavyProgress(value: updates.progress, label: 'Downloading'),
                const SizedBox(height: 8),
                Text('Downloading… ${(progressFraction * 100).round()}%', style: _recoloured(textTheme.bodySmall, scheme.onPrimaryContainer)),
              ] else if (updates.play)
                FilledButton.icon(
                  onPressed: () {
                    launchUrl(Uri.parse(playListing), mode: LaunchMode.externalApplication);
                  },
                  icon: AppIcon('download', size: 18, color: scheme.onPrimary),
                  label: const Text('Update on Google Play'),
                )
              else
                FilledButton.icon(
                  onPressed: updates.install,
                  icon: AppIcon('download', size: 18, color: scheme.onPrimary),
                  label: Text(updateLabel),
                ),
              if (updates.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(updates.error!, style: TextStyle(color: scheme.error)),
                ),
            ] else ...[
              const SizedBox(height: 12),
              if (updates.loading) ...[
                const WavyProgress(label: 'Checking for updates'),
                const SizedBox(height: 8),
                Text('Checking for updates…', style: _recoloured(textTheme.bodySmall, scheme.onSurfaceVariant)),
              ] else
                OutlinedButton.icon(
                  onPressed: () {
                    updates.check(fresh: true);
                  },
                  icon: AppIcon('refresh', size: 16, color: scheme.primary),
                  label: const Text('Check for updates'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// A download's size in megabytes, or nothing when it isn't known.
  static String _size(Object? bytes) {
    if (bytes is num && bytes > 0) {
      return '${(bytes / 1e6).toStringAsFixed(1)} MB';
    } else {
      return '';
    }
  }
}

/// Every release on a timeline, newest first, as sgbus-timings' updater has them: the ones newer
/// than this copy marked New, this one Installed, and "Earlier releases" before the rest. The one
/// you'd get opens by itself, or this one when there's nothing newer.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.history, required this.mine});
  final List<Map<String, dynamic>> history;
  final String mine;

  @override
  Widget build(BuildContext context) {
    var openIndex = -1;
    if (history.isNotEmpty && newerVersion('${history.first['version']}', mine)) {
      openIndex = 0;
    } else {
      openIndex = history.indexWhere((release) {
        return !newerVersion('${release['version']}', mine);
      });
    }
    final children = <Widget>[];
    var labelled = false;
    for (var index = 0; index < history.length; index = index + 1) {
      final version = '${history[index]['version']}';
      final isNew = newerVersion(version, mine);
      final installed = version == mine;
      if (!isNew && !installed && !labelled) {
        labelled = true;
        children.add(const _EarlierLabel());
      }
      children.add(
        _Release(
          key: ValueKey(version),
          release: history[index],
          isNew: isNew,
          installed: installed,
          openAtFirst: index == openIndex,
          last: index == history.length - 1,
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _EarlierLabel extends StatelessWidget {
  const _EarlierLabel();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Center(child: Container(width: 2, color: scheme.outlineVariant)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 0, 24),
              child: Text('Earlier releases', style: _recoloured(textTheme.titleSmall, scheme.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }
}

/// One release on the timeline: its version, New or Installed, when it came out and how many
/// changes, opening to show its notes.
class _Release extends StatefulWidget {
  const _Release({super.key, required this.release, required this.isNew, required this.installed, required this.openAtFirst, required this.last});
  final Map<String, dynamic> release;
  final bool isNew;
  final bool installed;
  final bool openAtFirst;
  final bool last;

  @override
  State<_Release> createState() => _ReleaseState();
}

class _ReleaseState extends State<_Release> {
  late bool _open = widget.openAtFirst;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// Today, Yesterday, 3 days ago, or 23 Oct 2026.
  static String? _when(Object? iso) {
    String isoText;
    if (iso == null) {
      isoText = '';
    } else {
      isoText = '$iso';
    }
    final parsed = DateTime.tryParse(isoText);
    if (parsed == null) {
      return null;
    }
    final date = parsed.toLocal();
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(date.year, date.month, date.day)).inDays;
    if (days <= 0) {
      return 'Today';
    }
    if (days == 1) {
      return 'Yesterday';
    }
    if (days < 7) {
      return '$days days ago';
    }
    return '${date.day} ${_months[date.month - 1]} ${date.year}';
  }

  /// The timeline's dot (a ring for the release you'd get or have), the header that opens and
  /// closes, and the notes when open.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final release = widget.release;
    final version = '${release['version']}';
    final notes = ReleaseNotes.parse(release['notes'] as String?);
    final count = notes.count;
    final when = _when(release['date']);
    String? changesText;
    if (count == 0) {
      changesText = null;
    } else if (count == 1) {
      changesText = '$count change';
    } else {
      changesText = '$count changes';
    }
    final metaParts = <String>[];
    if (when != null) {
      metaParts.add(when);
    }
    if (changesText != null) {
      metaParts.add(changesText);
    }
    final meta = metaParts.join(' · ');
    final hasNotes = notes.groups.isNotEmpty || notes.summary.isNotEmpty;
    final ring = widget.isNew || widget.installed;
    final disableAnimations = MediaQuery.maybeDisableAnimationsOf(context);
    bool reduceMotion;
    if (disableAnimations == null) {
      reduceMotion = false;
    } else {
      reduceMotion = disableAnimations;
    }
    final page = release['page'];

    // The dot on the timeline.
    double dotTop;
    double dotSize;
    Color dotColour;
    BoxBorder? dotBorder;
    if (ring) {
      dotTop = 7;
      dotSize = 16;
      dotColour = scheme.surface;
      dotBorder = Border.all(color: scheme.primary, width: 3);
    } else {
      dotTop = 10;
      dotSize = 10;
      dotColour = scheme.outline;
      dotBorder = null;
    }

    // The header: pressable only when there are notes to show.
    bool? expandedState;
    VoidCallback? onHeaderTap;
    if (hasNotes) {
      expandedState = _open;
      onHeaderTap = () {
        setState(() {
          _open = !_open;
        });
      };
    } else {
      expandedState = null;
      onHeaderTap = null;
    }
    Color chipColour;
    Color chipTextColour;
    String chipText;
    if (widget.isNew) {
      chipColour = scheme.primary;
      chipTextColour = scheme.onPrimary;
      chipText = 'New';
    } else {
      chipColour = scheme.primaryContainer;
      chipTextColour = scheme.onPrimaryContainer;
      chipText = 'Installed';
    }
    double chevronTurns;
    if (_open) {
      chevronTurns = 0.5;
    } else {
      chevronTurns = 0;
    }
    Duration animationDuration;
    if (reduceMotion) {
      animationDuration = Duration.zero;
    } else {
      animationDuration = const Duration(milliseconds: 200);
    }

    // The notes, when open: the summary, a card per group, and a link to the release on GitHub.
    Widget notesBody;
    if (!_open) {
      notesBody = const SizedBox(width: double.infinity);
    } else {
      notesBody = Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (notes.summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(notes.summary, style: _recoloured(textTheme.bodyMedium, scheme.onSurfaceVariant)),
              ),
            for (var groupIndex = 0; groupIndex < notes.groups.length; groupIndex = groupIndex + 1)
              _GroupCard(group: notes.groups[groupIndex], index: groupIndex),
            if (page is String && page.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    onPressed: () {
                      launchUrl(Uri.parse(page), mode: LaunchMode.externalApplication);
                    },
                    icon: AppIcon('link', size: 16, color: scheme.primary),
                    label: const Text('On GitHub'),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The timeline: a ring for the release you'd get or have, a dot for the rest.
          SizedBox(
            width: 24,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                if (!widget.last)
                  Positioned(top: 10, bottom: 0, child: Container(width: 2, color: scheme.outlineVariant)),
                Padding(
                  padding: EdgeInsets.only(top: dotTop),
                  child: Container(
                    width: dotSize,
                    height: dotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColour,
                      border: dotBorder,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    button: hasNotes,
                    expanded: expandedState,
                    label: 'Version $version',
                    child: InkWell(
                      mouseCursor: WidgetStateMouseCursor.clickable,
                      borderRadius: BorderRadius.circular(16),
                      onTap: onHeaderTap,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 10,
                                    children: [
                                      Text('v$version', style: _recoloured(textTheme.titleLarge, scheme.onSurface, fontWeight: FontWeight.bold)),
                                      if (ring)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: chipColour,
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: Text(
                                            chipText,
                                            style: _recoloured(textTheme.labelLarge, chipTextColour),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (meta.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(meta, style: _recoloured(textTheme.bodyMedium, scheme.onSurfaceVariant)),
                                    ),
                                ],
                              ),
                            ),
                            if (hasNotes)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: AnimatedRotation(
                                  turns: chevronTurns,
                                  duration: animationDuration,
                                  child: AppIcon('chevron-down', size: 24, color: scheme.onSurfaceVariant),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: animationDuration,
                    alignment: Alignment.topCenter,
                    child: notesBody,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A group of what's new in a release (a "###" heading in its notes): its icon on a tile of its
/// colour, its name and how many, then its items, the first few with Show all for the rest.
class _GroupCard extends StatefulWidget {
  const _GroupCard({required this.group, required this.index});
  final ReleaseGroup group;
  final int index;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  static const _firstShown = 4;
  bool _showAll = false;

  /// The icon for a group, picked by the words in its heading.
  static String _iconFor(String title) {
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.contains('android') || lowerTitle.contains('phone')) {
      return 'phone';
    }
    if (lowerTitle.contains('windows') || lowerTitle.contains('mac') || lowerTitle.contains('linux') || lowerTitle.contains('desktop')) {
      return 'monitor';
    }
    if (lowerTitle.contains('everywhere') || lowerTitle.contains('website')) {
      return 'globe';
    }
    if (lowerTitle.contains('timeline')) {
      return 'timeline';
    }
    if (lowerTitle.contains('board') || lowerTitle.contains('kanban')) {
      return 'kanban';
    }
    if (lowerTitle.contains('sync')) {
      return 'sync';
    }
    if (lowerTitle.contains('look') || lowerTitle.contains('theme')) {
      return 'sun';
    }
    if (lowerTitle.contains('fix') || lowerTitle.contains('easier')) {
      return 'check';
    }
    return 'star';
  }

  /// The group's card: a header with its icon, name and count, a row per item shown, and Show
  /// all when there are more than the first few.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final group = widget.group;
    // Its colours by its place: primary, tertiary, then secondary, round again.
    final tones = [
      (scheme.primaryContainer, scheme.onPrimaryContainer, scheme.primary),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer, scheme.tertiary),
      (scheme.secondaryContainer, scheme.onSecondaryContainer, scheme.secondary),
    ];
    final (tile, onTile, accent) = tones[widget.index % tones.length];
    List<ReleaseItem> shown;
    if (_showAll) {
      shown = group.items;
    } else {
      shown = group.items.take(_firstShown).toList();
    }
    return Card.outlined(
      margin: const EdgeInsets.only(top: 12),
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: scheme.outlineVariant)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: scheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(10)),
                  child: Center(child: AppIcon(_iconFor(group.title), size: 20, color: onTile)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(group.title, style: _recoloured(textTheme.titleMedium, scheme.onSurface, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(minWidth: 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                  child: Text('${group.items.length}', textAlign: TextAlign.center, style: _recoloured(textTheme.labelLarge, scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),
          for (final item in shown) ...[
            Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 7),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_capital(_headline(item)), style: _recoloured(textTheme.titleSmall, scheme.onSurface)),
                        if (item.title.isNotEmpty && item.text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(_capital(item.text), style: _recoloured(textTheme.bodyMedium, scheme.onSurfaceVariant)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!_showAll && group.items.length > _firstShown) ...[
            Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
            InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              onTap: () {
                setState(() {
                  _showAll = true;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Expanded(child: Text('Show all (${group.items.length})', style: _recoloured(textTheme.labelLarge, scheme.primary))),
                    AppIcon('chevron-down', size: 20, color: scheme.primary),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// An item's bold line: its title, or its text when it has no title.
  static String _headline(ReleaseItem item) {
    if (item.title.isEmpty) {
      return item.text;
    } else {
      return item.title;
    }
  }

  /// The text with its first letter made a capital.
  static String _capital(String text) {
    if (text.isEmpty) {
      return text;
    } else {
      return text[0].toUpperCase() + text.substring(1);
    }
  }
}
