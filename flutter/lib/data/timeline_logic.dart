// The Timeline's arithmetic, ported from main-site/js/timeline.js: dates as whole UTC day
// numbers (so a clock change never moves a bar), a task's span, the days on show, the header's
// two rows, and what waits for what. test/timeline_logic_test.dart checks it against the site's
// own answers (tool/expected.mjs).
import 'board.dart';

const zoomKey = 'uwuboard.timeline.zoom';

class Zoom {
  const Zoom(this.id, this.label, this.ppd, this.margin, this.newLength);
  final String id;
  final String label;

  /// Pixels per day.
  final double ppd;
  final int margin;

  /// How long a task given dates by a press starts out.
  final int newLength;
}

const zooms = {'weeks': Zoom('weeks', 'Weeks', 40, 7, 3), 'months': Zoom('months', 'Months', 14, 21, 7), 'quarters': Zoom('quarters', 'Quarters', 4, 45, 14)};

const rowPhase = 38.0, rowTask = 40.0, rowAdd = 34.0, headHeight = 52.0;

/// The colour of a task with no label of its own, by phase.
const phaseColours = ['#4c9aff', '#ffb31f', '#36b37e', '#ff7452', '#998dd9', '#00b8d9'];
const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _dow = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

const _dayMs = 86400000;
final _isoRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool isIso(Object? s) => s is String && _isoRe.hasMatch(s);

int dayOf(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return (DateTime.utc(p[0], p[1], p[2]).millisecondsSinceEpoch / _dayMs).round();
}

DateTime dateOf(int n) => DateTime.fromMillisecondsSinceEpoch(n * _dayMs, isUtc: true);

String isoOf(int n) {
  final d = dateOf(n);
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Today's date where the person is.
String todayIso([DateTime? now]) {
  final t = now ?? DateTime.now();
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

/// JS's getUTCDay(): 0 for Sunday.
int _utcDay(DateTime d) => d.weekday % 7;

class Span {
  const Span(this.start, this.end);
  final int start;
  final int end;
}

/// A task's span as day numbers, or null without dates. One date alone is a one-day task; a
/// milestone is always one day, on its due date.
Span? spanOf(Json card) {
  final s = isIso(card['start']) ? dayOf(card['start'] as String) : null;
  final d = isIso(card['due']) ? dayOf(card['due'] as String) : null;
  if (s == null && d == null) return null;
  if (card['milestone'] == true) {
    final day = d ?? s!;
    return Span(day, day);
  }
  final start = s ?? d!;
  final end = d ?? s!;
  return start <= end ? Span(start, end) : Span(end, start);
}

/// How far a task's checklist is done, 0 to 1.
double progressOf(Json card) {
  final list = checklistOf(card);
  return list.isEmpty ? 0 : list.where((c) => c['done'] == true).length / list.length;
}

/// The task waited for ends on or after the day the waiting one starts.
bool clashes(Json? pred, Json card) {
  final a = pred == null ? null : spanOf(pred), b = spanOf(card);
  return a != null && b != null && a.end >= b.start;
}

/// Every task that waits for `id`, directly or down the chain: none of them can become
/// something `id` waits for, or the chain would go round in a circle.
Set<String> waitingOn(Json board, String id) {
  final out = <String>{};
  final stack = [id];
  while (stack.isNotEmpty) {
    final cur = stack.removeLast();
    for (final card in allCards(board)) {
      final cid = '${card['id']}';
      if (depsOf(card).contains(cur) && !out.contains(cid)) {
        out.add(cid);
        stack.add(cid);
      }
    }
  }
  return out;
}

/// A card that's gone is waited for by nobody.
void pruneDeps(Json board) {
  final ids = {for (final c in allCards(board)) c['id']};
  for (final card in allCards(board)) {
    final deps = card['dependsOn'];
    if (deps is List && deps.isNotEmpty) card['dependsOn'] = deps.where(ids.contains).toList();
  }
}

void setSpan(Json card, int start, int end) {
  card['start'] = isoOf(start);
  card['due'] = isoOf(card['milestone'] == true ? start : end);
}

/* ---- layout ---- */

class TlRow {
  TlRow(this.kind, this.y, this.h, {this.col, this.card, this.colour});
  final String kind; // phase | task | add | addPhase
  final double y;
  final double h;
  final Json? col;
  final Json? card;
  final String? colour;
}

/// The rows top to bottom: each phase, its tasks, and a row to add one; then one to add a phase.
({List<TlRow> rows, double height}) rowsOf(Json board) {
  final rows = <TlRow>[];
  var y = 0.0;
  final cols = columnsOf(board);
  for (var i = 0; i < cols.length; i++) {
    final col = cols[i];
    final colour = phaseColours[i % phaseColours.length];
    rows.add(TlRow('phase', y, rowPhase, col: col, colour: colour));
    y += rowPhase;
    for (final card in cardsOf(col)) {
      final labels = labelsOf(card);
      final own = labels.isEmpty ? null : labels.first['color'];
      rows.add(TlRow('task', y, rowTask, col: col, card: card, colour: own is String && own.isNotEmpty ? own : colour));
      y += rowTask;
    }
    rows.add(TlRow('add', y, rowAdd, col: col));
    y += rowAdd;
  }
  rows.add(TlRow('addPhase', y, rowAdd));
  y += rowAdd;
  return (rows: rows, height: y);
}

class TlRange {
  const TlRange(this.lo, this.days, this.today);
  final int lo;
  final int days;
  final int today;
}

/// The days on show: every task and today, with a margin, from the start of a week (Monday) or
/// month, and wide enough to fill the space there is.
TlRange rangeOf(Json board, String zoom, double minWidth, {String? today}) {
  final z = zooms[zoom]!;
  final t = dayOf(today ?? todayIso());
  var lo = t, hi = t;
  for (final card in allCards(board)) {
    final s = spanOf(card);
    if (s != null) {
      if (s.start < lo) lo = s.start;
      if (s.end > hi) hi = s.end;
    }
  }
  lo -= z.margin;
  hi += z.margin;
  final d = dateOf(lo);
  if (zoom == 'weeks') {
    lo -= (_utcDay(d) + 6) % 7;
  } else {
    lo = (DateTime.utc(d.year, d.month, 1).millisecondsSinceEpoch / _dayMs).round();
  }
  final need = (minWidth / z.ppd).ceil();
  final days = hi - lo + 1 > need ? hi - lo + 1 : need;
  return TlRange(lo, days, t);
}

class TlTick {
  const TlTick(this.x, this.text, {this.w = 0, this.weekend = false});
  final double x;
  final String text;
  final double w;
  final bool weekend;
}

class TlLine {
  const TlLine(this.x, this.strong);
  final double x;
  final bool strong;
}

/// The two rows of the header and the gridlines under them.
({List<TlTick> top, List<TlTick> bottom, List<TlLine> lines}) scaleOf(TlRange range, String zoom) {
  final ppd = zooms[zoom]!.ppd;
  final top = <TlTick>[], bottom = <TlTick>[];
  final lines = <TlLine>[];
  String? lastTop;
  for (var n = range.lo; n < range.lo + range.days; n++) {
    final d = dateOf(n);
    final x = (n - range.lo) * ppd;
    final m = d.month - 1, y = d.year, day = d.day, wd = _utcDay(d);
    final topKey = zoom == 'quarters' ? '${y}Q${m ~/ 3}' : '$y-$m';
    if (topKey != lastTop) {
      top.add(TlTick(x, zoom == 'quarters' ? 'Q${m ~/ 3 + 1} $y' : '${months[m]} $y'));
      lastTop = topKey;
    }
    if (zoom == 'weeks') {
      bottom.add(TlTick(x, '${_dow[wd]} $day', w: ppd, weekend: wd % 6 == 0));
      lines.add(TlLine(x, wd == 1));
    } else if (zoom == 'months' && wd == 1) {
      bottom.add(TlTick(x, '$day', w: 7 * ppd));
      lines.add(TlLine(x, day <= 7));
    } else if (zoom == 'quarters' && day == 1) {
      bottom.add(TlTick(x, months[m], w: 30 * ppd));
      lines.add(TlLine(x, m % 3 == 0));
    }
  }
  return (top: top, bottom: bottom, lines: lines);
}

/// "3 Nov".
String fmtDay(int n) {
  final d = dateOf(n);
  return '${d.day} ${months[d.month - 1]}';
}

/// A task's dates as its row says them.
String whenOf(Json card) {
  final s = spanOf(card);
  if (s == null) return 'No dates';
  return s.start == s.end ? fmtDay(s.start) : '${fmtDay(s.start)} – ${fmtDay(s.end)}';
}

/// Late: past its due date and not all ticked off. Never a milestone.
bool isLate(Json card, {String? today}) =>
    card['milestone'] != true && isIso(card['due']) && (card['due'] as String).compareTo(today ?? todayIso()) < 0 && progressOf(card) < 1;
