// The open board drawn whole, not just what's on screen: every column at its whole height, or
// every row of a Timeline. Drawn off to the side of the window, where it's never seen, then
// captured. For the desktop's Long screenshot (lib/desktop/screenshot.dart) and a bug report's
// Screenshot a page (lib/features/bug/bug_report.dart).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/nav.dart';
import '../../app/state.dart';
import '../../data/board.dart';
import '../timeline/timeline_view.dart';
import 'kanban_view.dart';

/// `context` is any under the app's theme (the title bar's, the bug report's bar). At most
/// `maxHeight` pixels tall, and at most `maxSide` along its longer side, its resolution lowered
/// to fit; null if it couldn't be drawn.
Future<ui.Image?> drawWholeBoard(BuildContext context, Json board, {double maxHeight = 16384, double maxSide = 16384}) async {
  // Called from above the navigator: the navigator's overlay.
  final overlay = AppNav.navigatorKey.currentState?.overlay;
  if (overlay == null) return null;
  final key = GlobalKey();
  OverlayEntry? entry;
  try {
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
    if (box == null) return null;
    final longest = math.max(box.size.width, box.size.height);
    final r = math.min(ratio, math.min(maxHeight / math.max(box.size.height, 1), maxSide / math.max(longest, 1)));
    return await box.toImage(pixelRatio: r);
  } finally {
    entry?.remove();
  }
}
