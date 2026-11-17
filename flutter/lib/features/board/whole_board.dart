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
import '../../theme/theme.dart';
import '../timeline/timeline_view.dart';
import 'kanban_view.dart';

/// `context` is any under the app's theme (the title bar's, the bug report's bar). At most
/// `maxHeight` pixels tall, and at most `maxSide` along its longer side, its resolution lowered
/// to fit; null if it couldn't be drawn.
Future<ui.Image?> drawWholeBoard(BuildContext context, Json board, {double maxHeight = 16384, double maxSide = 16384}) async {
  // Called from above the navigator: the navigator's overlay.
  final navigatorState = AppNavigation.navigatorKey.currentState;
  OverlayState? overlay;
  if (navigatorState != null) {
    overlay = navigatorState.overlay;
  }
  if (overlay == null) {
    return null;
  }
  final key = GlobalKey();
  OverlayEntry? entry;
  try {
    final size = MediaQuery.sizeOf(context);
    final timeline = AppState.instance.isTimeline(board);
    final theme = Theme.of(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final mediaQueryData = MediaQuery.of(context).copyWith(size: Size(size.width, maxHeight));
    entry = OverlayEntry(
      builder: (overlayContext) {
        // A Timeline is as wide as the window; a Kanban board as wide as its columns.
        double maxWidth;
        Widget boardView;
        if (timeline) {
          maxWidth = size.width;
          boardView = SizedBox(
            width: size.width,
            child: TimelineView(board: board, fullHeight: true),
          );
        } else {
          maxWidth = double.infinity;
          boardView = KanbanView(board: board, fullHeight: true);
        }
        return Positioned(
          // Far off the window, where it's drawn but never seen.
          left: -size.width * 4 - 20000,
          top: 0,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            maxWidth: maxWidth,
            minHeight: 0,
            maxHeight: maxHeight,
            child: RepaintBoundary(
              key: key,
              child: Theme(
                data: theme,
                child: Material(
                  // The page's colour: native glass's page is see-through.
                  color: theme.extension<UwuColors>()!.background,
                  child: MediaQuery(
                    data: mediaQueryData,
                    child: boardView,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(entry);
    // Long enough for the cards' pictures to arrive.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    RenderRepaintBoundary? boundary;
    if (key.currentContext != null) {
      boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary?;
    }
    if (boundary == null) {
      return null;
    }
    final longestSide = math.max(boundary.size.width, boundary.size.height);
    final pixelRatio = math.min(devicePixelRatio, math.min(maxHeight / math.max(boundary.size.height, 1), maxSide / math.max(longestSide, 1)));
    return await boundary.toImage(pixelRatio: pixelRatio);
  } finally {
    if (entry != null) {
      entry.remove();
    }
  }
}
