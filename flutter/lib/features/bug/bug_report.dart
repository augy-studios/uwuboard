// Report a bug (the site's js/bug-report.js, and SG Bus Timings' own): what went wrong, a way to
// be reached if they'd like an answer, up to three pictures (from the device, or a screenshot of a
// page of the app), and what helps find it (the app's version, the device and the page on show:
// the kind of page and the window open, never a board's or a card's name), sent to Augy on
// Telegram by /api/bug-report. What's typed stays until it's sent, closed or not.
//
// Screenshot a page puts the report away and leaves you in the app, to go to the page you want
// (open a card, switch to the Timeline), with Screenshot this page floating at the bottom. That
// takes the whole page: the open board drawn whole, every column top to bottom
// (features/board/whole_board.dart), or with a window open, the screen as it is. Then it brings
// you back to the report. The bar floats outside the part of the screen that's taken, so it isn't
// in the picture. A whole board goes marked `full`, so it also reaches Augy as a file, at its
// full size.
//
// Once it's sent, the report says its ID (api/bug-report.js, reportId), to quote.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as image_library;
import 'package:url_launcher/url_launcher.dart';

import '../../api/api.dart';
import '../../app/env.dart';
import '../../app/files.dart';
import '../../app/nav.dart';
import '../../app/state.dart';
import '../../data/store.dart';
import '../../native/bridge.dart';
import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../../widgets/sheet.dart';
import '../board/whole_board.dart';

const _email = 'augy@augystudios.com';
const _draftKey = 'uwuboard.bugDraft';
const _maxShots = 3;

/// Opens the Report a bug window.
Future<void> openBugReport(BuildContext context) {
  return AppSheet.show(
    context,
    id: 'bug',
    width: 480,
    builder: (context) {
      return const BugReport();
    },
  );
}

/// A report's pictures, which outlive its window while you go and find a page to take.
class BugPictures {
  BugPictures._();
  static final List<String> shots = []; // JPEG data URLs
  static final Set<int> full = {}; // whole pages among them: each also goes as a file, at its full size

  static void clear() {
    shots.clear();
    full.clear();
  }

  /// Takes out the picture at [index], and moves down the place of each whole page after it so
  /// they still point at the same pictures.
  static void removeAt(int index) {
    shots.removeAt(index);
    final moved = <int>{};
    for (final pictureIndex in full) {
      if (pictureIndex != index) {
        if (pictureIndex > index) {
          moved.add(pictureIndex - 1);
        } else {
          moved.add(pictureIndex);
        }
      }
    }
    full.clear();
    full.addAll(moved);
  }
}

// ---------- pictures, made away from the screen's thread ----------

/// An image as a JPEG data URL, at most 1600 pixels a side and about 900 KB.
String? bugPhotoJpeg(Uint8List bytes) {
  var image = image_library.decodeImage(bytes);
  if (image == null) {
    return null;
  }
  final side = math.max(image.width, image.height);
  if (side > 1600) {
    image = image_library.copyResize(image, width: (image.width * 1600 / side).round(), height: (image.height * 1600 / side).round());
  }
  // Rougher and rougher until it's small enough; the roughest is taken whatever its size.
  for (final quality in [82, 70, 55, 40]) {
    final encoded = image_library.encodeJpg(image, quality: quality);
    if (encoded.length <= 900 * 1024 || quality == 40) {
      return 'data:image/jpeg;base64,${base64Encode(encoded)}';
    }
  }
  return null;
}

/// A whole page as a JPEG data URL that Telegram takes as a photo: no more than 1080 pixels across
/// its shorter side, its longer side no more than 20 times that (any more is cut off at the bottom
/// or the right), its sides adding up to at most 9998, and about 900 KB, rougher and then smaller
/// till it is.
String? bugPageJpeg(Uint8List bytes) {
  final image = image_library.decodeImage(bytes);
  if (image == null) {
    return null;
  }
  final shortSide = math.min(image.width, image.height);
  final width = math.min(image.width, shortSide * 20);
  final height = math.min(image.height, shortSide * 20);
  var scale = math.min(1.0, math.min(1080 / shortSide, 9998 / (width + height)));
  image_library.Image page;
  if (width == image.width && height == image.height) {
    page = image;
  } else {
    page = image_library.copyCrop(image, x: 0, y: 0, width: width, height: height);
  }
  // Up to eight tries: the first two only rougher, then each one smaller as well.
  for (var tries = 0; tries < 8; tries = tries + 1) {
    image_library.Image toEncode;
    if (scale >= 1) {
      toEncode = page;
    } else {
      toEncode = image_library.copyResize(page, width: math.max(1, (width * scale).floor()), height: math.max(1, (height * scale).floor()), interpolation: image_library.Interpolation.average);
    }
    int quality;
    if (tries < 2) {
      quality = 80;
    } else {
      quality = 68;
    }
    final encoded = image_library.encodeJpg(
      toEncode,
      quality: quality,
    );
    if (encoded.length <= 900 * 1024 || tries == 7) {
      return 'data:image/jpeg;base64,${base64Encode(encoded)}';
    }
    if (tries >= 1) {
      scale = scale * 0.82;
    }
  }
  return null;
}

// ---------- Screenshot a page ----------

/// The bar over the app while you find the page to take. Shown by the app's root (app.dart),
/// outside the part of the screen that's taken.
class BugShot {
  BugShot._();
  static final ValueNotifier<bool> shooting = ValueNotifier(false);

  /// Off to the app to find the page to take: the report's window closed, what's typed kept.
  static void start() {
    shooting.value = true;
    AppNavigation.closeSheets();
  }

  /// Back from finding a page: the bar goes and the report's window opens again.
  static void back() {
    shooting.value = false;
    final context = AppNavigation.context;
    if (context != null) {
      openBugReport(context);
    }
  }

  /// The page as it is: with no window open, the open board drawn whole; otherwise the screen.
  /// Returns the picture and whether it's a whole page (bigger than the screen).
  static Future<(String, bool)?> take(BuildContext context) async {
    final board = AppState.instance.activeBoard;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final screen = MediaQuery.sizeOf(context) * devicePixelRatio;
    final background = UwuColors.of(context).background;
    ui.Image? picture;
    var whole = false;
    if (board != null && !AppSheet.anyOpen) {
      picture = await drawWholeBoard(context, board, maxHeight: 16000, maxSide: 16000);
      whole = picture != null && (picture.height > screen.height + 4 || picture.width > screen.width + 4);
    }
    // No board, a window open, or the board couldn't be drawn: the screen as it is.
    if (picture == null) {
      RenderObject? renderObject;
      if (AppNavigation.repaintKey.currentContext != null) {
        renderObject = AppNavigation.repaintKey.currentContext!.findRenderObject();
      }
      if (renderObject is! RenderRepaintBoundary) {
        return null;
      }
      picture = await flattenOnto(await renderObject.toImage(pixelRatio: math.min(2, devicePixelRatio)), background);
    }
    final pngData = await picture.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    if (pngData == null) {
      return null;
    }
    final bytes = pngData.buffer.asUint8List();
    String? Function(Uint8List) makeJpeg;
    if (whole) {
      makeJpeg = bugPageJpeg;
    } else {
      makeJpeg = bugPhotoJpeg;
    }
    final jpeg = await compute(makeJpeg, bytes);
    if (jpeg == null) {
      return null;
    } else {
      return (jpeg, whole);
    }
  }
}

class BugShotBar extends StatefulWidget {
  const BugShotBar({super.key});

  @override
  State<BugShotBar> createState() {
    return _BugShotBarState();
  }
}

class _BugShotBarState extends State<BugShotBar> {
  bool _busy = false;

  /// Takes the page, adds it to the report's pictures (if there's room), and goes back to the
  /// report. If it can't, says so.
  Future<void> _take() async {
    setState(() {
      _busy = true;
    });
    // The button's press drawn and gone before the page is.
    await WidgetsBinding.instance.endOfFrame;
    try {
      (String, bool)? taken;
      if (mounted) {
        taken = await BugShot.take(context);
      } else {
        taken = null;
      }
      if (taken == null) {
        throw StateError('no picture');
      }
      if (BugPictures.shots.length < _maxShots) {
        BugPictures.shots.add(taken.$1);
        if (taken.$2) {
          BugPictures.full.add(BugPictures.shots.length - 1);
        }
      }
    } catch (error) {
      AppNavigation.toast('Couldn’t take a screenshot here. Take one with your device and add it instead.', error: true);
    }
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
    BugShot.back();
  }

  /// The floating bar: Screenshot this page (a spinner while it's taken) and a cross to cancel.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    VoidCallback? onTake;
    VoidCallback? onCancel;
    Widget takeIcon;
    String takeLabel;
    if (_busy) {
      onTake = null;
      onCancel = null;
      takeIcon = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
      takeLabel = 'Taking a screenshot…';
    } else {
      onTake = _take;
      onCancel = BugShot.back;
      takeIcon = AppIcon('screenshot', size: 16, color: colors.onBrand);
      takeLabel = 'Screenshot this page';
    }
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Material(
              color: colors.surfaceStrong,
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: colors.border)),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: FilledButton.icon(
                        key: const ValueKey('bug-shot-take'),
                        onPressed: onTake,
                        icon: takeIcon,
                        label: Text(takeLabel, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Semantics(
                      button: true,
                      label: 'Cancel',
                      excludeSemantics: true,
                      child: IconButton(
                        key: const ValueKey('bug-shot-cancel'),
                        onPressed: onCancel,
                        icon: AppIcon('close', size: 18, color: colors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- the report ----------

/// The windows that can be open over the page (AppSheet ids), by what they're called.
const _windows = {
  'card': 'card window',
  'col-picker': 'Move to column',
  'newboard': 'New board',
  'rename-col': 'Rename column',
  'reorder-cols': 'Reorder columns',
  'profile': 'Profile',
  'delete-account': 'Delete account',
  'theme': 'Theme',
  'sync': 'Sync',
  'tour': 'Show me around',
};

class BugReport extends StatefulWidget {
  const BugReport({super.key});

  /// What's sent with it, as the site's form sends it.
  static Map<String, String> details(BuildContext context) {
    final info = Native.info;
    final size = MediaQuery.sizeOf(context);
    final screen = '${size.width.round()}×${size.height.round()}';
    final String platform;
    final String device;
    if (Environment.android) {
      platform = 'android';
      Object release = '';
      if (info != null) {
        final infoRelease = info['release'];
        if (infoRelease != null) {
          release = infoRelease;
        }
      }
      device = [
        'Android $release'.trim(),
        if (info != null && info['model'] != null) '${info['model']}',
        if (info != null && info['sdk'] != null) 'API ${info['sdk']}',
        screen,
      ].join(' · ');
    } else if (Environment.desktop) {
      platform = 'desktop';
      Object operatingSystemValue = '';
      if (info != null) {
        final operatingSystemFromInfo = info['os'];
        if (operatingSystemFromInfo != null) {
          operatingSystemValue = operatingSystemFromInfo;
        }
      }
      final operatingSystem = '$operatingSystemValue'.trim();
      String systemName;
      if (operatingSystem.isNotEmpty) {
        systemName = operatingSystem;
      } else {
        systemName = defaultTargetPlatform.name;
      }
      device = [systemName, screen].join(' · ');
    } else {
      platform = 'web';
      device = ['Flutter web', screen].join(' · ');
    }
    String version;
    final nativeVersion = Native.version;
    if (nativeVersion == null) {
      version = Environment.version;
    } else {
      version = nativeVersion;
    }
    return {'version': version, 'platform': platform, 'device': device, 'page': page()};
  }

  /// The page on show, and the windows open over it, except this one: never a name.
  static String page() {
    final app = AppState.instance;
    final board = app.activeBoard;
    String pageKind;
    if (board == null) {
      pageKind = 'No board open';
    } else if (app.isTimeline(board)) {
      pageKind = 'Timeline';
    } else {
      pageKind = 'Kanban board';
    }
    final parts = <String>[pageKind];
    for (final id in AppSheet.open.value) {
      final name = _windows[id];
      if (name != null) {
        parts.add(name);
      }
    }
    return parts.join(', ');
  }

  static const _platformNames = {'android': 'Android app', 'desktop': 'Desktop app', 'web': 'Web'};

  /// The details as one line, for the window and for an email: the kind of app, its version,
  /// the device and the page, leaving out any that are missing.
  static String detailsText(Map<String, String> details) {
    return [_platformNames[details['platform']], details['version'], details['device'], details['page']].where((value) {
      return value != null && value.isNotEmpty;
    }).join(' · ');
  }

  @override
  State<BugReport> createState() {
    return _BugReportState();
  }
}

class _BugReportState extends State<BugReport> {
  late final Map<String, dynamic> _draft = _readDraft();
  late final _text = TextEditingController(text: _draftText(_draft, 'text'));
  late final _contact = TextEditingController(text: _draftText(_draft, 'contact'));
  // What it adds, as the window opened: the page under it, not this window.
  Map<String, String>? _details;
  List<String> get _shots {
    return BugPictures.shots;
  }

  bool _sending = false;
  String _status = '';
  bool _offerEmail = false;

  /// What was typed before, kept on the device until it's sent; empty if there's none.
  static Map<String, dynamic> _readDraft() {
    try {
      String saved;
      final stored = Store.instance.get(_draftKey);
      if (stored == null) {
        saved = '{}';
      } else {
        saved = stored;
      }
      final decoded = jsonDecode(saved);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      } else {
        return {};
      }
    } catch (error) {
      return {};
    }
  }

  /// One box's text from the draft, or '' when it has none.
  static String _draftText(Map<String, dynamic> draft, String key) {
    final value = draft[key] as String?;
    if (value == null) {
      return '';
    }
    return value;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final details = _details;
    if (details == null) {
      _details = BugReport.details(context);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _contact.dispose();
    super.dispose();
  }

  /// Saves what's typed, so it's still there next time the window opens.
  void _keep() {
    Store.instance.put(_draftKey, jsonEncode({'text': _text.text, 'contact': _contact.text}));
  }

  /// Adds pictures from the device, as many as there's room for, each made a smaller JPEG.
  Future<void> _pick() async {
    final files = await pickImages();
    for (final file in files.take(_maxShots - _shots.length)) {
      final picture = await compute(bugPhotoJpeg, await file.readAsBytes()).catchError((error) {
        return null;
      });
      if (picture != null) {
        _shots.add(picture);
      } else if (mounted) {
        setState(() {
          _status = 'Couldn’t add that picture.';
        });
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  /// Screenshot a page: keeps what's typed and goes off to find the page.
  void _screenshot() {
    _keep();
    BugShot.start();
  }

  /// Sends the report. Says when there's too little written or no connection; once sent, clears
  /// it and gives its ID. If the server can't take it, offers to email it instead.
  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.length < 5) {
      setState(() {
        _status = 'Please say what went wrong first.';
      });
      return;
    }
    if (Api.offline.value) {
      setState(() {
        _status = 'You’re offline. It’s kept here: send it once you’re back online.';
      });
      return;
    }
    setState(() {
      _sending = true;
      _status = 'Sending…';
      _offerEmail = false;
    });
    try {
      final fullPages = BugPictures.full.toList();
      fullPages.sort();
      final response = await Api.call('POST', '/bug-report', {
        ..._details!,
        'text': text,
        'contact': _contact.text.trim(),
        'website': '',
        'images': _shots,
        'full': fullPages,
      });
      String? id;
      if (response['id'] is String) {
        id = response['id'] as String;
      } else {
        id = null;
      }
      _text.clear();
      _contact.clear();
      BugPictures.clear();
      Store.instance.put(_draftKey, null);
      if (id != null) {
        _status = 'Sent as report $id. Thank you! Augy will look into it.';
      } else {
        _status = 'Sent. Thank you! Augy will look into it.';
      }
    } on ApiError catch (error) {
      // Something about what was typed, or too many at once: said as it is. Otherwise, email.
      if (error.status == 400 || error.status == 413 || error.status == 429) {
        if (error.message.isNotEmpty) {
          _status = error.message;
        } else {
          _status = 'Couldn’t send it right now.';
        }
      } else {
        if (error.status == 503) {
          _status = 'Bug reports can’t be sent from the app yet.';
        } else {
          _status = 'Couldn’t send it right now.';
        }
        _offerEmail = true;
      }
    } catch (error) {
      _status = 'Couldn’t send it right now.';
      _offerEmail = true;
    }
    if (mounted) {
      setState(() {
        _sending = false;
      });
    }
  }

  /// Opens an email to Augy with the report and its details already filled in.
  void _emailInstead() {
    final body = '${_text.text.trim()}\n\n${BugReport.detailsText(_details!)}';
    final uri = Uri.parse('mailto:$_email?subject=${Uri.encodeComponent('uwuBoard bug report')}&body=${Uri.encodeComponent(body)}');
    launchUrl(uri, mode: LaunchMode.externalApplication).catchError((error) {
      return false;
    });
  }

  /// The window: what went wrong, how to reach you, the pictures (with buttons to add one or
  /// take a page), what's sent with it, and the status after sending.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final full = _shots.length >= _maxShots;
    final note = TextStyle(color: colors.muted, fontSize: 12.5);
    VoidCallback? onSend;
    if (_sending) {
      onSend = null;
    } else {
      onSend = _send;
    }
    // With three pictures there's no room for more.
    VoidCallback? onAddPictures;
    VoidCallback? onScreenshot;
    Color addIconColor;
    if (full) {
      onAddPictures = null;
      onScreenshot = null;
      addIconColor = colors.muted;
    } else {
      onAddPictures = _pick;
      onScreenshot = _screenshot;
      addIconColor = colors.ink;
    }

    /// One picture's thumbnail, with a cross in its corner to take it out.
    Widget pictureThumbnail(int index, String picture) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              base64Decode(picture.split(',').last),
              width: 72,
              height: 96,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              semanticLabel: 'Picture ${index + 1}',
            ),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: Semantics(
              button: true,
              label: 'Remove picture ${index + 1}',
              excludeSemantics: true,
              child: InkWell(
                mouseCursor: WidgetStateMouseCursor.clickable,
                customBorder: const CircleBorder(),
                onTap: () {
                  setState(() {
                    BugPictures.removeAt(index);
                  });
                },
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(color: Color(0xA6000000), shape: BoxShape.circle),
                  child: const Center(child: AppIcon('close', size: 14, color: Colors.white)),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return SheetFrame(
      title: 'Report a bug',
      footer: [
        const SizedBox.shrink(),
        FilledButton.icon(
          key: const ValueKey('bug-send'),
          onPressed: onSend,
          icon: AppIcon('send', size: 16, color: colors.onBrand),
          label: const Text('Send'),
        ),
      ],
      children: [
        // Each box carries its label as its name, so a screen reader still says what it is once
        // there's text in it: its hint, the only name it had before, goes when it's filled in.
        // The label above is the same words, so it isn't read twice.
        const ExcludeSemantics(child: FieldLabel('What went wrong?')),
        Semantics(
          label: 'What went wrong?',
          child: TextField(
            key: const ValueKey('bug-text'),
            controller: _text,
            minLines: 4,
            maxLines: 10,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (value) {
              _keep();
            },
            decoration: const InputDecoration(hintText: 'What you did, what happened, and what you expected', counterText: ''),
          ),
        ),
        const ExcludeSemantics(child: FieldLabel('How to reach you', note: '(optional)')),
        Semantics(
          label: 'How to reach you (optional)',
          child: TextField(
            key: const ValueKey('bug-contact'),
            controller: _contact,
            maxLength: 200,
            autocorrect: false,
            onChanged: (value) {
              _keep();
            },
            decoration: const InputDecoration(hintText: 'Telegram @name or email, for an answer', counterText: ''),
          ),
        ),
        const FieldLabel('Pictures', note: '(optional)'),
        if (_shots.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (index, picture) in _shots.indexed) pictureThumbnail(index, picture),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('bug-add-pictures'),
              onPressed: onAddPictures,
              icon: AppIcon('image', size: 16, color: addIconColor),
              label: const Text('Add pictures'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('bug-screenshot'),
              onPressed: onScreenshot,
              icon: AppIcon('screenshot', size: 16, color: addIconColor),
              label: const Text('Screenshot a page'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Up to 3. Screenshot a page puts this away: go to the page you want (open a card, or switch to the Timeline), '
            'then press Screenshot this page. It takes the whole page, top to bottom, and brings you back here.',
            style: note,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('Sent with it, to help find the bug: ${BugReport.detailsText(_details!)}.', style: note),
        ),
        if (_status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(_status, key: const ValueKey('bug-status'), style: TextStyle(color: colors.ink, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
        if (_offerEmail)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _emailInstead, child: const Text('Email it instead.')),
          ),
      ],
    );
  }
}
