// The title bar's two screenshot buttons (docs/desktop-features-spec.md §5):
// - Screenshot: a picture of the app's content (not the title bar), copied to the clipboard and
//   saved in Downloads as "uwuBoard YYYY-MM-DD HH.MM.SS.png".
// - Long screenshot: the whole of the open board, top to bottom, not just what's on screen:
//   every column at its whole height, or every row of a Timeline, up to 16384 px tall; saved as
//   "… (long).png". Only one at a time.
// A notification says it's saved; clicking it shows it in its folder.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pasteboard/pasteboard.dart';

import '../app/nav.dart';
import '../app/state.dart';
import '../features/board/kanban_view.dart';
import '../features/timeline/timeline_view.dart';
import 'desk.dart';
import 'notify.dart';

class Screenshots {
  Screenshots._();

  static final ValueNotifier<bool> busy = ValueNotifier(false);
  static const maxHeight = 16384.0;

  static String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}.${two(n.minute)}.${two(n.second)}';
  }

  static Future<ui.Image?> _capture(GlobalKey key, double ratio) async {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary) return null;
    if (box.debugNeedsPaint) await Future<void>.delayed(const Duration(milliseconds: 40));
    return box.toImage(pixelRatio: ratio);
  }

  static Future<void> _save(ui.Image image, String name, String said) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('no picture');
    final bytes = data.buffer.asUint8List();
    final dir = Directory(Desktop.downloads)..createSync(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    try {
      await Pasteboard.writeImage(bytes);
    } catch (_) {}
    AppNav.toast('Screenshot copied and saved');
    DeskNotify.show(title: said, body: name, onClick: () => Desktop.showInFolder(file.path));
  }

  static Future<void> take(BuildContext context) async {
    if (busy.value) return;
    busy.value = true;
    try {
      final ratio = MediaQuery.devicePixelRatioOf(context);
      final image = await _capture(AppNav.repaintKey, ratio);
      if (image == null) throw StateError('nothing to capture');
      await _save(image, '${Desktop.name} ${_stamp()}.png', 'Screenshot saved');
    } catch (_) {
      AppNav.toast('Couldn’t take a screenshot', error: true);
    } finally {
      busy.value = false;
    }
  }

  /// The open board drawn whole, off to the side of the window, then captured.
  static Future<void> takeLong(BuildContext context) async {
    final board = AppState.I.activeBoard;
    if (board == null) return take(context);
    if (busy.value) return;
    busy.value = true;
    // Called from the title bar, above the navigator: the navigator's overlay.
    final overlay = AppNav.navigatorKey.currentState?.overlay;
    final key = GlobalKey();
    OverlayEntry? entry;
    try {
      if (overlay == null) throw StateError('no overlay');
      final size = MediaQuery.sizeOf(context);
      final timeline = AppState.I.isTimeline(board);
      final theme = Theme.of(context);
      final ratio = MediaQuery.devicePixelRatioOf(context);
      final mq = MediaQuery.of(context).copyWith(size: Size(size.width, maxHeight));
      entry = OverlayEntry(
        builder: (_) => Positioned(
          // Far off the window, where it's drawn but never seen.
          left: -size.width * 4 - 20000,
          top: 0,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            maxWidth: timeline ? size.width : double.infinity,
            minHeight: 0,
            maxHeight: maxHeight,
            child: RepaintBoundary(
              key: key,
              child: Theme(
                data: theme,
                child: Material(
                  color: theme.scaffoldBackgroundColor,
                  child: MediaQuery(
                    data: mq,
                    child: timeline
                        ? SizedBox(
                            width: size.width,
                            child: TimelineView(board: board, fullHeight: true),
                          )
                        : KanbanView(board: board, fullHeight: true),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      overlay.insert(entry);
      // Long enough for the cards' pictures to arrive.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final box = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (box == null) throw StateError('nothing drawn');
      final r = math.min(ratio, maxHeight / math.max(box.size.height, 1));
      final image = await box.toImage(pixelRatio: r);
      await _save(image, '${Desktop.name} ${_stamp()} (long).png', 'Long screenshot saved');
    } catch (_) {
      AppNav.toast('Couldn’t take a screenshot', error: true);
    } finally {
      entry?.remove();
      busy.value = false;
    }
  }
}
