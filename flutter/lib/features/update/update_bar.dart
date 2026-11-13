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

const _releasesKey = 'app.releaseNotices';
const playListing = 'https://play.google.com/store/apps/details?id=org.uwuapps.board';

/// Whether version a comes after version b, number by number: 1.10.0 after 1.9.0. The same as
/// newer() in main-site/api/app-release.js.
bool newerVersion(String a, String b) {
  List<int> parts(String v) => v.split('.').map((n) => int.tryParse(n.replaceAll(RegExp(r'\D'), '')) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d > 0;
  }
  return false;
}

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

  String get mine => Native.version ?? Env.version;

  /// The newest release, when it's newer than this copy.
  Map<String, dynamic>? get newer {
    final l = latest;
    if (l == null || l['version'] is! String) return null;
    return newerVersion(l['version'] as String, mine) ? l : null;
  }

  /// The Play build: Play updates it, so no updater of its own.
  bool get play => isPlayBuild || Native.info?['play'] == true;

  bool get offered => newer != null && !dismissed && !play;

  List<Map<String, dynamic>> get history => [
    for (final h in (latest?['history'] as List? ?? const []))
      if (h is Map) Map<String, dynamic>.from(h),
  ];

  void start() {
    if (_started || !Env.android) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    notices = Store.I.get(_releasesKey) == '1';
    // The notification "x.y.z is out", tapped: this page.
    Native.on('App', 'openUpdates', (_) => openUpdates());
    check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final at = _checkedAt;
    if (at == null || DateTime.now().difference(at) > const Duration(hours: 1)) check();
  }

  /// `fresh` asks past the site's cache, for a release published a moment ago.
  Future<void> check({bool fresh = false}) async {
    _checkedAt = DateTime.now();
    loading = true;
    notifyListeners();
    try {
      final uri = Api.uri('/app-release${fresh ? '?v=${DateTime.now().millisecondsSinceEpoch}' : ''}');
      final res = await Api.client.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
      final data = jsonDecode(res.body);
      if (data is Map) latest = Map<String, dynamic>.from(data);
      failed = false;
    } catch (_) {
      failed = latest == null;
    }
    loading = false;
    notifyListeners();
  }

  void dismiss() {
    dismissed = true;
    notifyListeners();
  }

  Future<void> install() async {
    final r = newer;
    if (r == null || progress != null) return;
    error = null;
    progress = 0;
    notifyListeners();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}uwuboard-${r['version']}.apk');
      final res = await Api.client.send(http.Request('GET', Uri.parse('${r['apk']}')));
      if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
      final total = (r['size'] as num?)?.toInt() ?? res.contentLength ?? 0;
      final sink = file.openWrite();
      var got = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) {
          progress = got / total;
          notifyListeners();
        }
      }
      await sink.close();
      final sum = (await sha256.bind(file.openRead()).first).toString();
      final expected = r['sha256'];
      if (expected is String && expected.isNotEmpty && expected.toLowerCase() != sum) {
        await file.delete();
        throw StateError('checksum');
      }
      progress = 1;
      notifyListeners();
      await Native.call('App', 'installApk', {'path': file.path});
      progress = null;
    } catch (e) {
      progress = null;
      error = e is StateError && e.message == 'checksum'
          ? 'The download didn’t match GitHub’s checksum, so it wasn’t installed. Try again.'
          : (e is NativeError && e.code == 'permission'
                ? 'Allow uwuBoard to install apps, then press Update again.'
                : 'Couldn’t download the update. Check your connection and try again.');
    }
    notifyListeners();
  }

  /// Joins or leaves the release topic (Firebase), asking for notifications first.
  Future<void> setNotices(bool on) async {
    final was = notices;
    notices = null;
    notifyListeners();
    try {
      await Native.call('App', 'setReleases', {'on': on});
      notices = on;
      Store.I.put(_releasesKey, on ? '1' : '0');
      AppNav.toast(on ? 'You’ll get a notification the moment a new version is out.' : 'No more notifications of new versions.');
    } on NativeError catch (e) {
      notices = was;
      AppNav.toast(
        e.code == 'permission'
            ? 'Notifications are off for uwuBoard. Turn them on in Android’s settings, then try again.'
            : 'Couldn’t reach Firebase. Check your connection and try again.',
        error: true,
      );
      if (e.code == 'permission') Native.tryCall('App', 'openSettings', {'page': 'notifications'});
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
      builder: (context, _) {
        final u = AndroidUpdates.I;
        if (!u.offered) return const SizedBox.shrink();
        final c = UwuColors.of(context);
        return Material(
          color: c.brandFill,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text('uwuBoard ${u.newer!['version']} is out.', style: TextStyle(color: c.onBrand, fontSize: 14)),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: c.surfaceStrong, foregroundColor: c.ink),
                    onPressed: openUpdates,
                    child: const Text('Update'),
                  ),
                  TextButton(
                    onPressed: u.dismiss,
                    style: TextButton.styleFrom(foregroundColor: c.onBrand),
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

Future<void> openUpdates() async {
  final nav = AppNav.navigatorKey.currentState;
  if (nav == null) return;
  AndroidUpdates.I.check(fresh: true);
  await nav.push(
    MaterialPageRoute<void>(
      builder: (_) => const UpdatesPage(),
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
    final dyn = brightness == Brightness.dark ? darkDynamicScheme : lightDynamicScheme;
    final theme = buildTheme(look: lookMaterial, brightness: brightness, brand: ThemeController.I.colorTheme.color, dynamicScheme: dyn);
    return Theme(data: theme, child: const _UpdatesBody());
  }
}

class _UpdatesBody extends StatelessWidget {
  const _UpdatesBody();

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: AndroidUpdates.I,
      builder: (context, _) {
        final u = AndroidUpdates.I;
        final newer = u.newer;
        final history = u.history;
        return Scaffold(
          backgroundColor: s.surface,
          body: RefreshIndicator(
            onRefresh: () => u.check(fresh: true),
            child: CustomScrollView(
              slivers: [
                SliverAppBar.large(
                  backgroundColor: s.surface,
                  surfaceTintColor: s.surfaceTint,
                  leading: IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.pop(context),
                    icon: AppIcon('arrow-left', color: s.onSurface),
                  ),
                  title: const Text('Updates'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverList.list(
                    children: [
                      _statusCard(context, u, newer),
                      if (Native.has('push')) ...[
                        const SizedBox(height: 12),
                        Card.filled(
                          color: s.surfaceContainer,
                          child: SwitchListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            secondary: AppIcon('bell', color: s.onSurfaceVariant),
                            title: const Text('New versions of the app'),
                            subtitle: const Text('A notification the moment a new version is out, even with the app closed.'),
                            value: u.notices ?? false,
                            onChanged: u.notices == null ? null : u.setNotices,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text('Every version', style: t.titleMedium?.copyWith(color: s.primary)),
                      ),
                      const SizedBox(height: 8),
                      if (history.isEmpty && u.loading)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (history.isEmpty && !u.loading)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            u.failed ? 'Couldn’t load the versions. Pull down to try again.' : 'No versions published yet.',
                            style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList.builder(
                    itemCount: history.length,
                    itemBuilder: (context, i) => _VersionCard(release: history[i], mine: u.mine),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusCard(BuildContext context, AndroidUpdates u, Map<String, dynamic>? newer) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final up = newer == null;
    return Card.filled(
      color: up ? s.surfaceContainerHigh : s.primaryContainer,
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
                        up ? 'You’re up to date' : 'uwuBoard ${newer['version']} is out',
                        style: t.titleLarge?.copyWith(color: up ? s.onSurface : s.onPrimaryContainer),
                      ),
                      const SizedBox(height: 2),
                      Text('This is version ${u.mine}.', style: t.bodyMedium?.copyWith(color: up ? s.onSurfaceVariant : s.onPrimaryContainer)),
                    ],
                  ),
                ),
              ],
            ),
            if (!up) ...[
              const SizedBox(height: 16),
              if (u.progress != null) ...[
                LinearProgressIndicator(value: u.progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
                const SizedBox(height: 6),
                Text('Downloading… ${((u.progress ?? 0) * 100).round()}%', style: t.bodySmall?.copyWith(color: s.onPrimaryContainer)),
              ] else if (u.play)
                FilledButton.icon(
                  onPressed: () => launchUrl(Uri.parse(playListing), mode: LaunchMode.externalApplication),
                  icon: AppIcon('download', size: 18, color: s.onPrimary),
                  label: const Text('Update on Google Play'),
                )
              else
                FilledButton.icon(
                  onPressed: u.install,
                  icon: AppIcon('download', size: 18, color: s.onPrimary),
                  label: Text(_size(newer['size']).isEmpty ? 'Update' : 'Update (${_size(newer['size'])})'),
                ),
              if (u.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(u.error!, style: TextStyle(color: s.error)),
                ),
            ] else ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: u.loading ? null : () => u.check(fresh: true),
                icon: u.loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : AppIcon('refresh', size: 16, color: s.primary),
                label: const Text('Check for updates'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _size(Object? bytes) => bytes is num && bytes > 0 ? '${(bytes / 1e6).toStringAsFixed(1)} MB' : '';
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.release, required this.mine});
  final Map<String, dynamic> release;
  final String mine;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final v = '${release['version']}';
    final installed = v == mine;
    final isNew = newerVersion(v, mine);
    final date = DateTime.tryParse('${release['date'] ?? ''}')?.toLocal();
    final notes = '${release['notes'] ?? ''}'.trim();
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 10),
      color: installed ? s.secondaryContainer.withValues(alpha: 0.5) : s.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(v, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                if (installed) _chip(context, 'Installed', s.secondary, s.onSecondary),
                if (isNew) _chip(context, 'New', s.primary, s.onPrimary),
                const Spacer(),
                if (date != null) Text(_date(date), style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 8),
            _Notes(notes.isEmpty ? 'Fixes and improvements.' : notes),
            if (release['page'] is String)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => launchUrl(Uri.parse(release['page'] as String), mode: LaunchMode.externalApplication),
                  child: const Text('On GitHub'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String text, Color bg, Color fg) => Container(
    margin: const EdgeInsets.only(right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
    child: Text(
      text,
      style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// A release's notes as written on GitHub: headings bold, "- " lines as bullets, the rest as it is.
class _Notes extends StatelessWidget {
  const _Notes(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final raw in lines)
          if (raw.trim().isEmpty)
            const SizedBox(height: 6)
          else if (raw.trimLeft().startsWith('#'))
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(raw.replaceFirst(RegExp(r'^\s*#+\s*'), ''), style: t.titleSmall?.copyWith(color: s.primary)),
            )
          else if (RegExp(r'^\s*[-*]\s+').hasMatch(raw))
            Padding(
              padding: EdgeInsets.only(left: raw.startsWith(' ') ? 18 : 4, bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: t.bodyMedium?.copyWith(color: s.primary)),
                  Expanded(child: Text(raw.replaceFirst(RegExp(r'^\s*[-*]\s+'), ''), style: t.bodyMedium)),
                ],
              ),
            )
          else
            Text(raw.trim(), style: t.bodyMedium),
      ],
    );
  }
}
