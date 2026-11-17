// First-visit tours (main-site/js/tour.js, docs/page-tour-spec.md): the page dims, one thing on
// it is lit, and an arrow runs to it from a line saying what it does. A tour for each thing that
// can be on screen, shown the first time it is (a board as columns, as a Timeline, the New Board
// window, a card's details), and the welcome the first time the app opens, joined onto the
// view's own steps. "Show me around" in the tray replays any of them. Seen under the site's keys.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/env.dart';
import '../../app/nav.dart';
import '../../app/state.dart';
import '../../data/board.dart';
import '../../data/store.dart';
import '../../theme/theme.dart';
import '../../widgets/sheet.dart';

const _welcomeKey = 'uwuboard.tour.welcome';
const _pagesKey = 'uwuboard.tour.pages';

/// Things a tour can point at, by name: each widget that can be pointed at carries one of these
/// keys.
class TourTargets {
  TourTargets._();
  static final Map<String, GlobalKey> _keys = {};

  /// The key for the thing named [id], made the first time it's asked for.
  static GlobalKey key(String id) {
    return _keys.putIfAbsent(id, () {
      return GlobalKey(debugLabel: 'tour:$id');
    });
  }

  /// Where the thing is, measured from the top left of the navigator's overlay, which is where the
  /// tour draws. That isn't the window's top left on the desktop, whose title bar sits above it.
  static Rect? rectOf(String id) {
    final targetKey = _keys[id];
    BuildContext? targetContext;
    if (targetKey != null) {
      targetContext = targetKey.currentContext;
    }
    RenderObject? box;
    if (targetContext != null) {
      box = targetContext.findRenderObject();
    }
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return null;
    }
    // The overlay's own render box, whose top left the tour measures from.
    final navigatorState = AppNav.navigatorKey.currentState;
    OverlayState? overlay;
    if (navigatorState != null) {
      overlay = navigatorState.overlay;
    }
    RenderObject? layer;
    if (overlay != null) {
      layer = overlay.context.findRenderObject();
    }
    Offset origin;
    if (layer is RenderBox && layer.attached) {
      origin = layer.localToGlobal(Offset.zero);
    } else {
      origin = Offset.zero;
    }
    final rect = (box.localToGlobal(Offset.zero) - origin) & box.size;
    if (rect.width > 0 && rect.height > 0) {
      return rect;
    } else {
      return null;
    }
  }
}

class TourStep {
  const TourStep(this.targets, this.text, {this.when});

  /// Alternatives, in order: the first on screen is used.
  final List<String> targets;
  final String text;
  final bool Function()? when;
}

class TourDefinition {
  const TourDefinition(this.label, this.steps, {this.page, this.available, this.why});
  final String label;
  final List<TourStep> steps;
  final String? page;
  final bool Function()? available;
  final String? why;
}

/// Whether the app is phone-sized (no context yet counts as not).
bool _narrow() {
  final context = AppNav.context;
  return context != null && MediaQuery.sizeOf(context).width <= Env.phoneWidth;
}

/// Whether a board is open.
bool _hasBoard() {
  return AppState.I.activeBoard != null;
}

/// The open board's first card, or null if there's no board or no card.
Json? _firstCard() {
  final board = AppState.I.activeBoard;
  if (board == null) {
    return null;
  }
  for (final card in allCards(board)) {
    return card;
  }
  return null;
}

final tours = <String, TourDefinition>{
  'welcome': TourDefinition('Welcome', [
    const TourStep(['empty-new-board'], 'Start here: make a board. It can be a Kanban board or a Timeline.'),
    TourStep(
      const ['board-list'],
      'All your boards are listed here, with New Board below to make another.',
      when: () {
        return !_narrow();
      },
    ),
    TourStep(const ['menu'], 'Your boards are in here, with New Board to make another.', when: _narrow),
    const TourStep(
      ['tray-buttons', 'tray-tab'],
      'Theme, Show me around, and the open board’s view, Export, Import and Delete live here. Press and hold one to see what it does; the arrow tucks them away.',
    ),
    const TourStep(['tray-sync', 'tray-tab'], 'Sync copies boards straight to your other phone or computer, no account needed.'),
  ]),
  'kanban': TourDefinition(
    'Kanban board',
    const [
      TourStep(['add-card'], 'Add a card to a column.'),
      TourStep(['first-card'], 'Drag a card to the next column as the work moves along. Tap it for its details.'),
      TourStep(['col-menu'], 'Rename or delete a column here.'),
      TourStep(['add-column'], 'Add another column.'),
      TourStep(['tray-view', 'tray-tab'], 'See this board as a Timeline: the same cards, as bars across dates.'),
    ],
    page: 'kanban',
    available: _hasBoard,
    why: 'Open a board first',
  ),
  'timeline': TourDefinition(
    'Timeline',
    const [
      TourStep(['tl-bar'], 'Each task is a bar across its dates. Drag it to move them, or drag an end to change how long it takes.'),
      TourStep(['tl-undated'], 'No dates yet: press a day in its row to give it some.'),
      TourStep(['tl-zoom'], 'See weeks in detail, or months and quarters at once. Today brings you back.'),
      TourStep(['tl-phase'], 'Phases are this board’s columns. Press one to rename it; add tasks and phases under them.'),
      TourStep(['tray-view', 'tray-tab'], 'Back to Kanban any time: the same cards, as columns.'),
    ],
    page: 'timeline',
    available: _hasBoard,
    why: 'Open a board first',
  ),
  'newboard': const TourDefinition('New board', [
    TourStep(['nb-name'], 'Name the board after what it’s for.'),
    TourStep(['nb-type'], 'Kanban moves cards across columns; Timeline lays tasks out as bars across dates. You can switch later.'),
    TourStep(['nb-cols'], 'The columns it starts with: phases, on a Timeline. Tap one to remove it, or Add for another.'),
    TourStep(['nb-create'], 'Create makes the board and opens it.'),
  ], page: 'newboard'),
  'card': TourDefinition(
    'Card details',
    const [
      TourStep(['card-desc'], 'Notes on the card go here.'),
      TourStep(['card-dates'], 'A due date and a priority, both shown on the card.'),
      TourStep(['card-tl'], 'On a Timeline: when it starts, whether it’s a milestone, and what it waits for.'),
      TourStep(['card-col'], 'Move the card to another column without dragging it.'),
      TourStep(['card-images'], 'Add images. The one you star shows on the card.'),
      TourStep(['card-check'], 'Break the card into steps; the card shows how many are done.'),
      TourStep(['card-save'], 'Save keeps what you’ve changed.'),
    ],
    page: 'card',
    available: () {
      return _firstCard() != null;
    },
    why: 'Add a card first',
  ),
};

const tourOrder = ['welcome', 'kanban', 'timeline', 'newboard', 'card'];

class Tour {
  Tour._();

  static OverlayEntry? _entry;
  static bool _starting = false;
  static List<({String target, String text})> _steps = [];
  static List<String> _toursToMarkSeen = [];
  static final ValueNotifier<int> _currentStepIndex = ValueNotifier(0);
  static Timer? _waitTimer;

  /// What the page is now, for its tour.
  static String? Function()? currentPage;

  /// Opens a page for a tour to run on: the New Board window, the first card, or the open
  /// board as a view.
  static Future<void> Function(String page)? openPage;

  /// Whether a tour is on screen or about to be.
  static bool get active {
    return _entry != null || _starting;
  }

  /// The page on show now, or null if it can't be told.
  static String? _pageNow() {
    final pageGetter = currentPage;
    if (pageGetter == null) {
      return null;
    }
    return pageGetter();
  }

  /// The ids of the page tours seen, as saved (a JSON list); '[]' when nothing is saved.
  static String _storedPages() {
    final stored = Store.I.get(_pagesKey);
    if (stored == null) {
      return '[]';
    }
    return stored;
  }

  /// Whether the tour [id] has been seen on this device.
  static bool seen(String id) {
    try {
      if (id == 'welcome') {
        return Store.I.get(_welcomeKey) == 'done';
      }
      return (jsonDecode(_storedPages()) as List).contains(id);
    } catch (error) {
      // Broken storage counts every tour as seen, rather than showing one on every visit.
      return true;
    }
  }

  /// Saves that the tour [id] has been seen, under the site's keys.
  static void markSeen(String id) {
    try {
      if (id == 'welcome') {
        Store.I.put(_welcomeKey, 'done');
        return;
      }
      final list = (jsonDecode(_storedPages()) as List).cast<Object?>();
      if (!list.contains(id)) {
        Store.I.put(_pagesKey, jsonEncode([...list, id]));
      }
    } catch (error) {
      // Shown again next time.
    }
  }

  static StreamSubscription<void>? _pageChangesSubscription;

  /// Once the app is on screen: the first tour, unless a link opened something.
  static void init({bool skipFirst = false}) {
    final existingSubscription = _pageChangesSubscription;
    if (existingSubscription == null) {
      _pageChangesSubscription = AppState.I.pageChanges.listen((event) {
        forPage();
      });
    }
    if (!skipFirst) {
      forPage();
    }
  }

  /// Whether the page [id] is ready for its tour: a board view only once the boards have loaded.
  static bool _ready(String id) {
    return !(id == 'kanban' || id == 'timeline' || id == 'empty') || AppState.I.boardsReady;
  }

  /// The tour for what's on screen, the first time, once it's drawn.
  static void forPage() {
    if (active) {
      return;
    }
    final id = _pageNow();
    if (id == null) {
      return;
    }
    // The welcome joins onto the first board view's tour.
    final welcome = !seen('welcome') && (id == 'kanban' || id == 'timeline' || id == 'empty');
    if (!welcome && (!tours.containsKey(id) || seen(id))) {
      return;
    }
    final previousTimer = _waitTimer;
    if (previousTimer != null) {
      previousTimer.cancel();
    }
    // Checks every half second: a moment for a ready page to settle, up to eight seconds for
    // the boards to load. Gives up if the page changes or a tour starts meanwhile.
    var tries = 0;
    _waitTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      tries = tries + 1;
      if (_pageNow() != id || active) {
        timer.cancel();
        return;
      }
      bool keepWaiting;
      if (_ready(id)) {
        keepWaiting = tries < 2;
      } else {
        keepWaiting = tries <= 16;
      }
      if (keepWaiting) {
        return;
      }
      timer.cancel();
      // A window open over the page that isn't the page itself.
      final ownWindow = {'card': 'card', 'newboard': 'newboard'}[id];
      final otherWindowOpen = AppSheet.open.value.any((windowId) {
        return windowId != ownWindow;
      });
      if (otherWindowOpen) {
        return;
      }
      start(id, withWelcome: welcome);
    });
  }

  /// Starts the tour [id] (with the welcome's steps after it if [withWelcome]): goes to its page
  /// first if it has one, keeps only the steps whose target is on screen, and puts the tour's
  /// layer over the app. A tour with nothing to point at is marked seen and goes no further.
  static Future<void> start(String id, {bool withWelcome = false}) async {
    final tour = tours[id];
    if (active || (tour == null && !withWelcome)) {
      return;
    }
    final from = _pageNow();
    if (from == null) {
      return;
    }
    String? goTo;
    if (tour != null) {
      goTo = tour.page;
    }
    _starting = true;
    if (goTo != null && from != goTo) {
      final pageOpener = openPage;
      if (pageOpener != null) {
        await pageOpener(goTo);
      }
      await Future<void>.delayed(const Duration(milliseconds: 450));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _starting = false;
    // What's on screen changed while the page was drawn (a window closed): not this tour, now.
    String expectedPage;
    if (goTo != null) {
      expectedPage = goTo;
    } else {
      expectedPage = from;
    }
    if (_pageNow() != expectedPage) {
      Timer(const Duration(milliseconds: 600), forPage);
      return;
    }
    final candidateSteps = <TourStep>[
      if (tour != null) ...tour.steps,
      if (withWelcome && id != 'welcome') ...tours['welcome']!.steps,
    ];
    final steps = <({String target, String text})>[];
    String? lastTarget;
    for (final step in candidateSteps) {
      final condition = step.when;
      if (condition != null && !condition()) {
        continue;
      }
      final target = step.targets.where((targetName) {
        return TourTargets.rectOf(targetName) != null;
      }).firstOrNull;
      // Two steps can land on the same thing, such as the collapsed tray's tab.
      if (target == null || target == lastTarget) {
        continue;
      }
      lastTarget = target;
      steps.add((target: target, text: step.text));
    }
    final toursShown = [if (withWelcome) 'welcome', if (tour != null) id];
    if (steps.isEmpty) {
      toursShown.forEach(markSeen);
      _backTo(from);
      return;
    }
    _toursToMarkSeen = toursShown;
    _steps = steps;
    _currentStepIndex.value = 0;
    _startPage = from;
    final navigatorState = AppNav.navigatorKey.currentState;
    OverlayState? overlay;
    if (navigatorState != null) {
      overlay = navigatorState.overlay;
    }
    if (overlay == null) {
      return;
    }
    final entry = OverlayEntry(
      builder: (context) {
        return const _TourLayer();
      },
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static String? _startPage;

  /// The next step, or the end after the last one.
  static void next() {
    if (_currentStepIndex.value < _steps.length - 1) {
      _currentStepIndex.value = _currentStepIndex.value + 1;
    } else {
      end();
    }
  }

  /// Ends the tour: marks it seen, takes its layer away, and goes back to where it began (or
  /// looks for the next page's tour).
  static void end() {
    for (final id in _toursToMarkSeen) {
      markSeen(id);
    }
    _toursToMarkSeen = [];
    final entry = _entry;
    if (entry != null) {
      entry.remove();
    }
    _entry = null;
    final back = _startPage;
    _startPage = null;
    if (!_backTo(back)) {
      Timer(const Duration(milliseconds: 600), forPage);
    }
  }

  /// Back where a tour began, if it was a board view the tour changed (the open board shown as
  /// the other view, or a window the tour opened over it). Never a window: one that has closed
  /// since stays closed. True if it went back.
  static bool _backTo(String? page) {
    const views = {'kanban', 'timeline', 'empty'};
    if (page == null || !views.contains(page) || _pageNow() == page) {
      return false;
    }
    final pageOpener = openPage;
    if (pageOpener != null) {
      pageOpener(page);
    }
    return true;
  }
}

class _TourLayer extends StatefulWidget {
  const _TourLayer();

  @override
  State<_TourLayer> createState() {
    return _TourLayerState();
  }
}

class _TourLayerState extends State<_TourLayer> {
  final _focusNode = FocusNode();
  final _placement = _Placement();

  @override
  void initState() {
    super.initState();
    Tour._currentStepIndex.addListener(_reveal);
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _focusNode.requestFocus();
      _reveal();
    });
  }

  @override
  void dispose() {
    Tour._currentStepIndex.removeListener(_reveal);
    _focusNode.dispose();
    super.dispose();
  }

  /// The step's target scrolled into view if it's off the edge of what scrolls it (a column past
  /// the right of the board, a field below the fold of a window), then the spotlight moved to it.
  Future<void> _reveal() async {
    if (Tour._steps.isEmpty) {
      return;
    }
    final targetKey = TourTargets._keys[Tour._steps[Tour._currentStepIndex.value].target];
    BuildContext? targetContext;
    if (targetKey != null) {
      targetContext = targetKey.currentContext;
    }
    if (targetContext == null) {
      return;
    }
    const scrollDuration = Duration(milliseconds: 220);
    for (final policy in [ScrollPositionAlignmentPolicy.keepVisibleAtEnd, ScrollPositionAlignmentPolicy.keepVisibleAtStart]) {
      if (!targetContext.mounted) {
        return;
      }
      await Scrollable.ensureVisible(targetContext, duration: scrollDuration, alignmentPolicy: policy);
    }
    if (mounted) {
      setState(() {});
    }
  }

  /// The tour's layer: the page dimmed except for the lit target, the card with the step's words,
  /// its dots and Next (Done on the last), and Skip at the top left. Escape skips; the right
  /// arrow or Enter goes on.
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Tour._currentStepIndex,
      builder: (context, stepIndex, child) {
        final colors = UwuColors.of(context);
        final step = Tour._steps[stepIndex];
        final size = MediaQuery.sizeOf(context);
        final safePadding = MediaQuery.paddingOf(context);
        final screen = Offset.zero & size;
        // Lit up to the screen's edge, never past it.
        final target = TourTargets.rectOf(step.target);
        Rect? lit;
        if (target != null) {
          lit = target.inflate(8).intersect(screen.deflate(2));
        }
        Rect? hole;
        if (lit != null && lit.width > 0 && lit.height > 0) {
          hole = lit;
        } else {
          hole = null;
        }
        // Where the card may go: inside the screen and its safe area, and clear of Skip.
        final bounds = Rect.fromLTRB(safePadding.left + 12, safePadding.top + 60, size.width - safePadding.right - 12, size.height - safePadding.bottom - 12);
        final cardWidth = math.min(340.0, bounds.width);
        final isLastStep = stepIndex == Tour._steps.length - 1;
        String nextLabel;
        if (isLastStep) {
          nextLabel = 'Done';
        } else {
          nextLabel = 'Next';
        }

        /// One of the dots under the words, filled for the step on show.
        Widget stepDot(int index) {
          Color dotColor;
          if (index == stepIndex) {
            dotColor = colors.brandInk;
          } else {
            dotColor = colors.border;
          }
          return Container(
            margin: const EdgeInsets.only(right: 5),
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          );
        }

        return Focus(
          focusNode: _focusNode,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              Tour.end();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight || event.logicalKey == LogicalKeyboardKey.enter) {
              Tour.next();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: CustomPaint(painter: _DimPainter(hole, colors.scrim.withValues(alpha: 0.62), _placement, colors.brand)),
                  ),
                ),
                Positioned.fill(
                  child: CustomSingleChildLayout(
                    delegate: _CardLayout(hole, bounds, cardWidth, _placement),
                    child: Semantics(
                      scopesRoute: true,
                      namesRoute: true,
                      label: 'Tour',
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(colors.surfaceStrong, colors.bg),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Scrolls inside the card, rather than off the screen, with very
                            // large text on a small screen.
                            Flexible(
                              child: SingleChildScrollView(
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(step.text, style: TextStyle(color: colors.ink, fontSize: 15, height: 1.35)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                for (var index = 0; index < Tour._steps.length; index = index + 1) stepDot(index),
                                const Spacer(),
                                FilledButton(onPressed: Tour.next, child: Text(nextLabel)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Top left, as on the site: the top right is the tray's, which steps point at.
                Positioned(
                  top: safePadding.top + 10,
                  left: safePadding.left + 14,
                  child: OutlinedButton(onPressed: Tour.end, child: const Text('Skip')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Where the card went and where its arrow runs, worked out as the card is laid out (when its
/// height is known) and read as the arrow is painted, later in the same frame.
class _Placement {
  Offset? from;
  Offset? tip;
}

/// The card beside the lit thing: below it if it fits, else above, else to its right or left,
/// and if none fits (a target nearly the screen's size), over it at the bottom, without an arrow.
/// Always inside [bounds].
class _CardLayout extends SingleChildLayoutDelegate {
  _CardLayout(this.hole, this.bounds, this.width, this.placed);
  final Rect? hole;
  final Rect bounds;
  final double width;
  final _Placement placed;

  static const gap = 56.0;
  static const sideGap = 48.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(minWidth: width, maxWidth: width, maxHeight: math.max(0, bounds.height));
  }

  /// Picks the card's place (see the class's comment) and records where its arrow runs from and
  /// to, for the painter.
  @override
  Offset getPositionForChild(Size size, Size card) {
    final cardWidth = card.width;
    final cardHeight = card.height;

    /// A left edge moved so the card stays inside [bounds] across.
    double keepInsideX(double value) {
      return value.clamp(bounds.left, math.max(bounds.left, bounds.right - cardWidth));
    }

    /// A top edge moved so the card stays inside [bounds] down.
    double keepInsideY(double value) {
      return value.clamp(bounds.top, math.max(bounds.top, bounds.bottom - cardHeight));
    }

    placed.from = null;
    placed.tip = null;
    final litRect = hole;
    if (litRect == null) {
      return Offset(keepInsideX(bounds.center.dx - cardWidth / 2), keepInsideY(bounds.center.dy - cardHeight / 2));
    }

    // The arrow meets the lit box near its middle, but not at a rounded corner.
    double alongX(Rect rect) {
      if (rect.width > 24) {
        return rect.center.dx.clamp(rect.left + 12, rect.right - 12);
      } else {
        return rect.center.dx;
      }
    }

    double alongY(Rect rect) {
      if (rect.height > 24) {
        return rect.center.dy.clamp(rect.top + 12, rect.bottom - 12);
      } else {
        return rect.center.dy;
      }
    }

    // Below.
    if (bounds.bottom - litRect.bottom >= cardHeight + gap) {
      final cardPosition = Offset(keepInsideX(litRect.center.dx - cardWidth / 2), litRect.bottom + gap);
      final tip = Offset(alongX(litRect), litRect.bottom + 4);
      placed.tip = tip;
      placed.from = Offset(tip.dx.clamp(cardPosition.dx + 24, cardPosition.dx + cardWidth - 24), cardPosition.dy - 4);
      return cardPosition;
    }
    // Above.
    if (litRect.top - bounds.top >= cardHeight + gap) {
      final cardPosition = Offset(keepInsideX(litRect.center.dx - cardWidth / 2), litRect.top - gap - cardHeight);
      final tip = Offset(alongX(litRect), litRect.top - 4);
      placed.tip = tip;
      placed.from = Offset(tip.dx.clamp(cardPosition.dx + 24, cardPosition.dx + cardWidth - 24), cardPosition.dy + cardHeight + 4);
      return cardPosition;
    }
    // To the right.
    if (bounds.right - litRect.right >= cardWidth + sideGap) {
      final cardPosition = Offset(litRect.right + sideGap, keepInsideY(litRect.center.dy - cardHeight / 2));
      final tip = Offset(litRect.right + 4, alongY(litRect));
      placed.tip = tip;
      placed.from = Offset(cardPosition.dx - 4, tip.dy.clamp(cardPosition.dy + 20, cardPosition.dy + cardHeight - 20));
      return cardPosition;
    }
    // To the left.
    if (litRect.left - bounds.left >= cardWidth + sideGap) {
      final cardPosition = Offset(litRect.left - sideGap - cardWidth, keepInsideY(litRect.center.dy - cardHeight / 2));
      final tip = Offset(litRect.left - 4, alongY(litRect));
      placed.tip = tip;
      placed.from = Offset(cardPosition.dx + cardWidth + 4, tip.dy.clamp(cardPosition.dy + 20, cardPosition.dy + cardHeight - 20));
      return cardPosition;
    }
    // Nowhere beside it: over it, at the bottom.
    return Offset(keepInsideX(litRect.center.dx - cardWidth / 2), keepInsideY(bounds.bottom - cardHeight));
  }

  @override
  bool shouldRelayout(_CardLayout oldDelegate) {
    return oldDelegate.hole != hole || oldDelegate.bounds != bounds || oldDelegate.width != width;
  }
}

/// Paints the dimmed page with a rounded hole over the lit thing, a chalk outline round the hole,
/// and the chalk arrow from the card to it.
class _DimPainter extends CustomPainter {
  _DimPainter(this.hole, this.dimColor, this.placed, this.chalkColor);
  final Rect? hole;
  final Color dimColor;
  final _Placement placed;
  final Color chalkColor;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path();
    outer.addRect(Offset.zero & size);
    final litRect = hole;
    if (litRect == null) {
      final dimPaint = Paint();
      dimPaint.color = dimColor;
      canvas.drawPath(outer, dimPaint);
      return;
    }
    final cut = Path();
    cut.addRRect(RRect.fromRectAndRadius(litRect, const Radius.circular(12)));
    final dimPaint = Paint();
    dimPaint.color = dimColor;
    canvas.drawPath(Path.combine(PathOperation.difference, outer, cut), dimPaint);
    final outlinePaint = Paint();
    outlinePaint.color = chalkColor;
    outlinePaint.style = PaintingStyle.stroke;
    outlinePaint.strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(litRect, const Radius.circular(12)),
      outlinePaint,
    );
    // The chalk arrow, from the card to the thing it's about, with a slight bow.
    final start = placed.from;
    final tip = placed.tip;
    if (start == null || tip == null || (tip - start).distance < 8) {
      return;
    }
    final along = tip - start;
    final bow = Offset(-along.dy, along.dx) / along.distance * 24;
    final controlPoint = Offset((start.dx + tip.dx) / 2, (start.dy + tip.dy) / 2) + bow;
    final line = Paint();
    line.color = chalkColor;
    line.strokeWidth = 3;
    line.style = PaintingStyle.stroke;
    line.strokeCap = StrokeCap.round;
    final arrowPath = Path();
    arrowPath.moveTo(start.dx, start.dy);
    arrowPath.quadraticBezierTo(controlPoint.dx, controlPoint.dy, tip.dx, tip.dy);
    canvas.drawPath(
      arrowPath,
      line,
    );
    // The arrowhead: two short strokes back from the tip.
    final angle = math.atan2(tip.dy - controlPoint.dy, tip.dx - controlPoint.dx);
    for (final headAngle in [angle + math.pi * 0.8, angle - math.pi * 0.8]) {
      canvas.drawLine(tip, tip + Offset(math.cos(headAngle) * 14, math.sin(headAngle) * 14), line);
    }
  }

  // The card's place is only known once it's laid out, in the same frame, so always repaint.
  @override
  bool shouldRepaint(_DimPainter oldDelegate) {
    return true;
  }
}

/// "Show me around": a button per tour, each only while there's something for it to show.
Future<void> openTourPicker(BuildContext context) {
  return AppSheet.show(
    context,
    id: 'tour',
    width: 420,
    builder: (context) {
      final colors = UwuColors.of(context);
      return SheetFrame(
        title: 'Show me around',
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in tourOrder)
                Builder(
                  builder: (context) {
                    final tourDefinition = tours[id]!;
                    final available = tourDefinition.available;
                    final unavailable = available != null && !available();
                    // A tour with nothing to show can't be pressed, and its tooltip says why.
                    String tooltipMessage;
                    VoidCallback? onPressed;
                    if (unavailable) {
                      tooltipMessage = tourDefinition.why!;
                      onPressed = null;
                    } else {
                      tooltipMessage = '';
                      onPressed = () {
                        AppSheet.close(context);
                        Timer(const Duration(milliseconds: 300), () {
                          Tour.start(id);
                        });
                      };
                    }
                    return Tooltip(
                      message: tooltipMessage,
                      child: OutlinedButton(
                        onPressed: onPressed,
                        child: Text(tourDefinition.label),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Each part of uwuBoard shows you around the first time you open it. Pick one to see its tour again.',
            style: TextStyle(color: colors.muted, fontSize: 12.5),
          ),
        ],
      );
    },
  );
}
