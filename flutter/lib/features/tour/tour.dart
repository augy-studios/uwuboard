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
  static GlobalKey key(String id) => _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'tour:$id'));

  /// Where the thing is, measured from the top left of the navigator's overlay, which is where the
  /// tour draws. That isn't the window's top left on the desktop, whose title bar sits above it.
  static Rect? rectOf(String id) {
    final ctx = _keys[id]?.currentContext;
    final box = ctx?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final layer = AppNav.navigatorKey.currentState?.overlay?.context.findRenderObject();
    final origin = layer is RenderBox && layer.attached ? layer.localToGlobal(Offset.zero) : Offset.zero;
    final r = (box.localToGlobal(Offset.zero) - origin) & box.size;
    return r.width > 0 && r.height > 0 ? r : null;
  }
}

class TourStep {
  const TourStep(this.targets, this.text, {this.when});

  /// Alternatives, in order: the first on screen is used.
  final List<String> targets;
  final String text;
  final bool Function()? when;
}

class TourDef {
  const TourDef(this.label, this.steps, {this.page, this.available, this.why});
  final String label;
  final List<TourStep> steps;
  final String? page;
  final bool Function()? available;
  final String? why;
}

bool _narrow() {
  final ctx = AppNav.context;
  return ctx != null && MediaQuery.sizeOf(ctx).width <= Env.phoneWidth;
}

bool _hasBoard() => AppState.I.activeBoard != null;
Json? _firstCard() {
  final b = AppState.I.activeBoard;
  if (b == null) return null;
  for (final c in allCards(b)) {
    return c;
  }
  return null;
}

final tours = <String, TourDef>{
  'welcome': TourDef('Welcome', [
    const TourStep(['empty-new-board'], 'Start here: make a board. It can be a Kanban board or a Timeline.'),
    TourStep(const ['board-list'], 'All your boards are listed here, with New Board below to make another.', when: () => !_narrow()),
    TourStep(const ['menu'], 'Your boards are in here, with New Board to make another.', when: _narrow),
    const TourStep(
      ['tray-buttons', 'tray-tab'],
      'Theme, Show me around, and the open board’s view, Export, Import and Delete live here. Press and hold one to see what it does; the arrow tucks them away.',
    ),
    const TourStep(['tray-sync', 'tray-tab'], 'Sync copies boards straight to your other phone or computer, no account needed.'),
  ]),
  'kanban': TourDef(
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
  'timeline': TourDef(
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
  'newboard': const TourDef('New board', [
    TourStep(['nb-name'], 'Name the board after what it’s for.'),
    TourStep(['nb-type'], 'Kanban moves cards across columns; Timeline lays tasks out as bars across dates. You can switch later.'),
    TourStep(['nb-cols'], 'The columns it starts with: phases, on a Timeline. Tap one to remove it, or Add for another.'),
    TourStep(['nb-create'], 'Create makes the board and opens it.'),
  ], page: 'newboard'),
  'card': TourDef(
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
    available: () => _firstCard() != null,
    why: 'Add a card first',
  ),
};

const tourOrder = ['welcome', 'kanban', 'timeline', 'newboard', 'card'];

class Tour {
  Tour._();

  static OverlayEntry? _entry;
  static bool _starting = false;
  static List<({String target, String text})> _steps = [];
  static List<String> _marks = [];
  static final ValueNotifier<int> _at = ValueNotifier(0);
  static Timer? _waiting;

  /// What the page is now, for its tour.
  static String? Function()? currentPage;

  /// Opens a page for a tour to run on: the New Board window, the first card, or the open
  /// board as a view.
  static Future<void> Function(String page)? openPage;

  static bool get active => _entry != null || _starting;

  static bool seen(String id) {
    try {
      if (id == 'welcome') return Store.I.get(_welcomeKey) == 'done';
      return (jsonDecode(Store.I.get(_pagesKey) ?? '[]') as List).contains(id);
    } catch (_) {
      // Broken storage counts every tour as seen, rather than showing one on every visit.
      return true;
    }
  }

  static void markSeen(String id) {
    try {
      if (id == 'welcome') return Store.I.put(_welcomeKey, 'done');
      final list = (jsonDecode(Store.I.get(_pagesKey) ?? '[]') as List).cast<Object?>();
      if (!list.contains(id)) Store.I.put(_pagesKey, jsonEncode([...list, id]));
    } catch (_) {
      // Shown again next time.
    }
  }

  static StreamSubscription<void>? _sub;

  /// Once the app is on screen: the first tour, unless a link opened something.
  static void init({bool skipFirst = false}) {
    _sub ??= AppState.I.pageChanges.listen((_) => forPage());
    if (!skipFirst) forPage();
  }

  static bool _ready(String id) => !(id == 'kanban' || id == 'timeline' || id == 'empty') || AppState.I.boardsReady;

  /// The tour for what's on screen, the first time, once it's drawn.
  static void forPage() {
    if (active) return;
    final id = currentPage?.call();
    if (id == null) return;
    final welcome = !seen('welcome') && (id == 'kanban' || id == 'timeline' || id == 'empty');
    if (!welcome && (!tours.containsKey(id) || seen(id))) return;
    _waiting?.cancel();
    var tries = 0;
    _waiting = Timer.periodic(const Duration(milliseconds: 500), (t) {
      tries++;
      if (currentPage?.call() != id || active) return t.cancel();
      if (_ready(id) ? tries < 2 : tries <= 16) return;
      t.cancel();
      // A window open over the page that isn't the page itself.
      final own = {'card': 'card', 'newboard': 'newboard'}[id];
      if (AppSheet.open.value.any((s) => s != own)) return;
      start(id, withWelcome: welcome);
    });
  }

  static Future<void> start(String id, {bool withWelcome = false}) async {
    final tour = tours[id];
    if (active || (tour == null && !withWelcome)) return;
    final from = currentPage?.call();
    if (from == null) return;
    final goTo = tour?.page;
    _starting = true;
    if (goTo != null && from != goTo) {
      await openPage?.call(goTo);
      await Future<void>.delayed(const Duration(milliseconds: 450));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _starting = false;
    // What's on screen changed while the page was drawn (a window closed): not this tour, now.
    if (currentPage?.call() != (goTo ?? from)) {
      Timer(const Duration(milliseconds: 600), forPage);
      return;
    }
    final list = [...?tour?.steps, if (withWelcome && id != 'welcome') ...tours['welcome']!.steps];
    final steps = <({String target, String text})>[];
    String? lastTarget;
    for (final s in list) {
      if (s.when != null && !s.when!()) continue;
      final target = s.targets.where((t) => TourTargets.rectOf(t) != null).firstOrNull;
      // Two steps can land on the same thing, such as the collapsed tray's tab.
      if (target == null || target == lastTarget) continue;
      lastTarget = target;
      steps.add((target: target, text: s.text));
    }
    final done = [if (withWelcome) 'welcome', if (tour != null) id];
    if (steps.isEmpty) {
      done.forEach(markSeen);
      _backTo(from);
      return;
    }
    _marks = done;
    _steps = steps;
    _at.value = 0;
    _began = from;
    final overlay = AppNav.navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _entry = OverlayEntry(builder: (_) => const _TourLayer());
    overlay.insert(_entry!);
  }

  static String? _began;

  static void next() {
    if (_at.value < _steps.length - 1) {
      _at.value++;
    } else {
      end();
    }
  }

  static void end() {
    for (final id in _marks) {
      markSeen(id);
    }
    _marks = [];
    _entry?.remove();
    _entry = null;
    final back = _began;
    _began = null;
    if (!_backTo(back)) Timer(const Duration(milliseconds: 600), forPage);
  }

  /// Back where a tour began, if it was a board view the tour changed (the open board shown as
  /// the other view, or a window the tour opened over it). Never a window: one that has closed
  /// since stays closed. True if it went back.
  static bool _backTo(String? page) {
    const views = {'kanban', 'timeline', 'empty'};
    if (page == null || !views.contains(page) || currentPage?.call() == page) return false;
    openPage?.call(page);
    return true;
  }
}

class _TourLayer extends StatefulWidget {
  const _TourLayer();

  @override
  State<_TourLayer> createState() => _TourLayerState();
}

class _TourLayerState extends State<_TourLayer> {
  final _focus = FocusNode();
  final _placed = _Placement();

  @override
  void initState() {
    super.initState();
    Tour._at.addListener(_reveal);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _reveal();
    });
  }

  @override
  void dispose() {
    Tour._at.removeListener(_reveal);
    _focus.dispose();
    super.dispose();
  }

  /// The step's target scrolled into view if it's off the edge of what scrolls it (a column past
  /// the right of the board, a field below the fold of a window), then the spotlight moved to it.
  Future<void> _reveal() async {
    if (Tour._steps.isEmpty) return;
    final ctx = TourTargets._keys[Tour._steps[Tour._at.value].target]?.currentContext;
    if (ctx == null) return;
    const d = Duration(milliseconds: 220);
    for (final policy in [ScrollPositionAlignmentPolicy.keepVisibleAtEnd, ScrollPositionAlignmentPolicy.keepVisibleAtStart]) {
      if (!ctx.mounted) return;
      await Scrollable.ensureVisible(ctx, duration: d, alignmentPolicy: policy);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Tour._at,
      builder: (context, at, _) {
        final c = UwuColors.of(context);
        final step = Tour._steps[at];
        final size = MediaQuery.sizeOf(context);
        final pad = MediaQuery.paddingOf(context);
        final screen = Offset.zero & size;
        // Lit up to the screen's edge, never past it.
        final target = TourTargets.rectOf(step.target);
        final lit = target?.inflate(8).intersect(screen.deflate(2));
        final hole = lit != null && lit.width > 0 && lit.height > 0 ? lit : null;
        // Where the card may go: inside the screen and its safe area, and clear of Skip.
        final bounds = Rect.fromLTRB(pad.left + 12, pad.top + 60, size.width - pad.right - 12, size.height - pad.bottom - 12);
        final cardW = math.min(340.0, bounds.width);
        final last = at == Tour._steps.length - 1;
        return Focus(
          focusNode: _focus,
          onKeyEvent: (_, e) {
            if (e is! KeyDownEvent) return KeyEventResult.ignored;
            if (e.logicalKey == LogicalKeyboardKey.escape) {
              Tour.end();
              return KeyEventResult.handled;
            }
            if (e.logicalKey == LogicalKeyboardKey.arrowRight || e.logicalKey == LogicalKeyboardKey.enter) {
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
                    child: CustomPaint(painter: _DimPainter(hole, c.scrim.withValues(alpha: 0.62), _placed, c.brand)),
                  ),
                ),
                Positioned.fill(
                  child: CustomSingleChildLayout(
                    delegate: _CardLayout(hole, bounds, cardW, _placed),
                    child: Semantics(
                      scopesRoute: true,
                      namesRoute: true,
                      label: 'Tour',
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(c.surfaceStrong, c.bg),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: c.border),
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
                                  child: Text(step.text, style: TextStyle(color: c.ink, fontSize: 15, height: 1.35)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                for (var i = 0; i < Tour._steps.length; i++)
                                  Container(
                                    margin: const EdgeInsets.only(right: 5),
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(shape: BoxShape.circle, color: i == at ? c.brandInk : c.border),
                                  ),
                                const Spacer(),
                                FilledButton(onPressed: Tour.next, child: Text(last ? 'Done' : 'Next')),
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
                  top: pad.top + 10,
                  left: pad.left + 14,
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
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(minWidth: width, maxWidth: width, maxHeight: math.max(0, bounds.height));

  @override
  Offset getPositionForChild(Size size, Size card) {
    final w = card.width, h = card.height;
    double x(double v) => v.clamp(bounds.left, math.max(bounds.left, bounds.right - w));
    double y(double v) => v.clamp(bounds.top, math.max(bounds.top, bounds.bottom - h));
    placed.from = null;
    placed.tip = null;
    final r = hole;
    if (r == null) return Offset(x(bounds.center.dx - w / 2), y(bounds.center.dy - h / 2));

    // The arrow meets the lit box near its middle, but not at a rounded corner.
    double alongX(Rect a) => a.width > 24 ? a.center.dx.clamp(a.left + 12, a.right - 12) : a.center.dx;
    double alongY(Rect a) => a.height > 24 ? a.center.dy.clamp(a.top + 12, a.bottom - 12) : a.center.dy;

    if (bounds.bottom - r.bottom >= h + gap) {
      final at = Offset(x(r.center.dx - w / 2), r.bottom + gap);
      placed.tip = Offset(alongX(r), r.bottom + 4);
      placed.from = Offset(placed.tip!.dx.clamp(at.dx + 24, at.dx + w - 24), at.dy - 4);
      return at;
    }
    if (r.top - bounds.top >= h + gap) {
      final at = Offset(x(r.center.dx - w / 2), r.top - gap - h);
      placed.tip = Offset(alongX(r), r.top - 4);
      placed.from = Offset(placed.tip!.dx.clamp(at.dx + 24, at.dx + w - 24), at.dy + h + 4);
      return at;
    }
    if (bounds.right - r.right >= w + sideGap) {
      final at = Offset(r.right + sideGap, y(r.center.dy - h / 2));
      placed.tip = Offset(r.right + 4, alongY(r));
      placed.from = Offset(at.dx - 4, placed.tip!.dy.clamp(at.dy + 20, at.dy + h - 20));
      return at;
    }
    if (r.left - bounds.left >= w + sideGap) {
      final at = Offset(r.left - sideGap - w, y(r.center.dy - h / 2));
      placed.tip = Offset(r.left - 4, alongY(r));
      placed.from = Offset(at.dx + w + 4, placed.tip!.dy.clamp(at.dy + 20, at.dy + h - 20));
      return at;
    }
    return Offset(x(r.center.dx - w / 2), y(bounds.bottom - h));
  }

  @override
  bool shouldRelayout(_CardLayout old) => old.hole != hole || old.bounds != bounds || old.width != width;
}

class _DimPainter extends CustomPainter {
  _DimPainter(this.hole, this.dim, this.placed, this.chalk);
  final Rect? hole;
  final Color dim;
  final _Placement placed;
  final Color chalk;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    final r = hole;
    if (r == null) {
      canvas.drawPath(outer, Paint()..color = dim);
      return;
    }
    final cut = Path()..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(12)));
    canvas.drawPath(Path.combine(PathOperation.difference, outer, cut), Paint()..color = dim);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(12)),
      Paint()
        ..color = chalk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // The chalk arrow, from the card to the thing it's about, with a slight bow.
    final start = placed.from, tip = placed.tip;
    if (start == null || tip == null || (tip - start).distance < 8) return;
    final along = tip - start;
    final bow = Offset(-along.dy, along.dx) / along.distance * 24;
    final ctrl = Offset((start.dx + tip.dx) / 2, (start.dy + tip.dy) / 2) + bow;
    final line = Paint()
      ..color = chalk
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, tip.dx, tip.dy),
      line,
    );
    final ang = math.atan2(tip.dy - ctrl.dy, tip.dx - ctrl.dx);
    for (final a in [ang + math.pi * 0.8, ang - math.pi * 0.8]) {
      canvas.drawLine(tip, tip + Offset(math.cos(a) * 14, math.sin(a) * 14), line);
    }
  }

  // The card's place is only known once it's laid out, in the same frame, so always repaint.
  @override
  bool shouldRepaint(_DimPainter old) => true;
}

/// "Show me around": a button per tour, each only while there's something for it to show.
Future<void> openTourPicker(BuildContext context) {
  return AppSheet.show(
    context,
    id: 'tour',
    width: 420,
    builder: (context) {
      final c = UwuColors.of(context);
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
                    final t = tours[id]!;
                    final off = t.available != null && !t.available!();
                    return Tooltip(
                      message: off ? t.why! : '',
                      child: OutlinedButton(
                        onPressed: off
                            ? null
                            : () {
                                AppSheet.close(context);
                                Timer(const Duration(milliseconds: 300), () => Tour.start(id));
                              },
                        child: Text(t.label),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Each part of uwuBoard shows you around the first time you open it. Pick one to see its tour again.',
            style: TextStyle(color: c.muted, fontSize: 12.5),
          ),
        ],
      );
    },
  );
}
