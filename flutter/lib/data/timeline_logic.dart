// The Timeline's arithmetic, ported from main-site/js/timeline.js: dates as whole UTC day
// numbers (so a clock change never moves a bar), a task's span, the days on show, the header's
// two rows, and what waits for what. test/timeline_logic_test.dart checks it against the site's
// own answers (tool/expected.mjs).
import 'board.dart';

const zoomKey = 'uwuboard.timeline.zoom';

/// One of the timeline's zoom levels: how wide a day is, and how much room to leave around
/// the tasks.
class Zoom {
  const Zoom(this.id, this.label, this.pixelsPerDay, this.margin, this.newLength);
  final String id;
  final String label;

  /// Pixels per day.
  final double pixelsPerDay;
  final int margin;

  /// How long a task given dates by a press starts out.
  final int newLength;
}

const zooms = {'weeks': Zoom('weeks', 'Weeks', 40, 7, 3), 'months': Zoom('months', 'Months', 14, 21, 7), 'quarters': Zoom('quarters', 'Quarters', 4, 45, 14)};

const phaseRowHeight = 38.0, taskRowHeight = 40.0, addRowHeight = 34.0, headerHeight = 52.0;

/// The colour of a task with no label of its own, by phase.
const phaseColours = ['#4c9aff', '#ffb31f', '#36b37e', '#ff7452', '#998dd9', '#00b8d9'];
const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _daysOfWeek = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

const _millisecondsPerDay = 86400000;
final _isoDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Whether the value is a date written YYYY-MM-DD.
bool isIsoDate(Object? value) {
  return value is String && _isoDatePattern.hasMatch(value);
}

/// A YYYY-MM-DD date as a whole day number (days since 1 January 1970, UTC).
int dayOf(String iso) {
  final parts = iso.split('-').map(int.parse).toList();
  return (DateTime.utc(parts[0], parts[1], parts[2]).millisecondsSinceEpoch / _millisecondsPerDay).round();
}

DateTime dateOf(int dayNumber) {
  return DateTime.fromMillisecondsSinceEpoch(dayNumber * _millisecondsPerDay, isUtc: true);
}

/// A day number as YYYY-MM-DD.
String isoDateOf(int dayNumber) {
  final date = dateOf(dayNumber);
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// Today's date where the person is.
String todayIsoDate([DateTime? now]) {
  final DateTime today;
  if (now == null) {
    today = DateTime.now();
  } else {
    today = now;
  }
  return '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
}

/// JS's getUTCDay(): 0 for Sunday.
int _utcDay(DateTime date) {
  return date.weekday % 7;
}

/// The first and last day of a task, as day numbers.
class Span {
  const Span(this.start, this.end);
  final int start;
  final int end;
}

/// A task's span as day numbers, or null without dates: the whole bar, the work as it went
/// included. One date alone is a one-day task; a milestone is always one day, on its due date.
Span? spanOf(Json card, {String? today}) {
  final int? startDay;
  if (isIsoDate(card['start'])) {
    startDay = dayOf(card['start'] as String);
  } else {
    startDay = null;
  }
  final int? dueDay;
  if (isIsoDate(card['due'])) {
    dueDay = dayOf(card['due'] as String);
  } else {
    dueDay = null;
  }
  if (startDay == null && dueDay == null) {
    return null;
  }
  if (card['milestone'] == true) {
    final int day;
    if (dueDay != null) {
      day = dueDay;
    } else {
      day = startDay!;
    }
    return Span(day, day);
  }
  final int start;
  if (startDay != null) {
    start = startDay;
  } else {
    start = dueDay!;
  }
  final int end;
  if (dueDay != null) {
    end = dueDay;
  } else {
    end = startDay!;
  }
  final Span plan;
  if (start <= end) {
    plan = Span(start, end);
  } else {
    plan = Span(end, start);
  }
  final actual = actualOf(card, today: today);
  if (actual == null) {
    return plan;
  }
  final int firstDay;
  if (actual.start < plan.start) {
    firstDay = actual.start;
  } else {
    firstDay = plan.start;
  }
  final int lastDay;
  if (actual.end > plan.end) {
    lastDay = actual.end;
  } else {
    lastDay = plan.end;
  }
  return Span(firstDay, lastDay);
}

/// The work as it went, for a task started after its due date (work that's very late) or
/// given a completed date: from its start to the day it was completed, or to today while it's
/// still going. Otherwise null. Such a bar moves whole ([shiftDates]).
Span? actualOf(Json card, {String? today}) {
  if (card['milestone'] == true || !isIsoDate(card['start'])) {
    return null;
  }
  final start = card['start'] as String;
  final startedLate = isIsoDate(card['due']) && start.compareTo(card['due'] as String) > 0;
  final String? completed;
  if (isIsoDate(card['completed'])) {
    completed = card['completed'] as String;
  } else {
    completed = null;
  }
  if (!startedLate && completed == null) {
    return null;
  }
  final startDay = dayOf(start);
  final String endDate;
  if (completed != null) {
    endDate = completed;
  } else if (today != null) {
    endDate = today;
  } else {
    endDate = todayIsoDate();
  }
  final endDay = dayOf(endDate);
  if (endDay > startDay) {
    return Span(startDay, endDay);
  } else {
    return Span(startDay, startDay);
  }
}

/// The day a card reached the board's last column (Done; Release on a timeline) is its
/// completed date: set as it arrives (or is added there), cleared if it leaves. Moves within a
/// column, or between two others, leave it be.
void stampCompleted(Json board, Map card, String? fromColumnId, String toColumnId, {String? today}) {
  if (fromColumnId == toColumnId) {
    return;
  }
  final columns = columnsOf(board);
  if (columns.isEmpty) {
    return;
  }
  final lastColumnId = '${columns.last['id']}';
  if (toColumnId == lastColumnId) {
    if (today != null) {
      card['completed'] = today;
    } else {
      card['completed'] = todayIsoDate();
    }
  } else if (fromColumnId == lastColumnId) {
    card.remove('completed');
  }
}

/// Every date a task has, moved by `days`: a bar that shows the work as it went moves whole.
void shiftDates(Json card, int days) {
  for (final key in const ['start', 'due', 'completed']) {
    if (isIsoDate(card[key])) {
      card[key] = isoDateOf(dayOf(card[key] as String) + days);
    }
  }
}

/// How far a task's checklist is done, 0 to 1.
double progressOf(Json card) {
  final list = checklistOf(card);
  if (list.isEmpty) {
    return 0;
  } else {
    final doneCount = list.where((item) {
      return item['done'] == true;
    }).length;
    return doneCount / list.length;
  }
}

/// The task waited for ends on or after the day the waiting one starts.
bool clashes(Json? predecessor, Json card) {
  final Span? predecessorSpan;
  if (predecessor == null) {
    predecessorSpan = null;
  } else {
    predecessorSpan = spanOf(predecessor);
  }
  final cardSpan = spanOf(card);
  return predecessorSpan != null && cardSpan != null && predecessorSpan.end >= cardSpan.start;
}

/// Every task that waits for `id`, directly or down the chain: none of them can become
/// something `id` waits for, or the chain would go round in a circle.
Set<String> waitingOn(Json board, String id) {
  final waiting = <String>{};
  final stack = [id];
  while (stack.isNotEmpty) {
    final current = stack.removeLast();
    for (final card in allCards(board)) {
      final cardId = '${card['id']}';
      if (dependenciesOf(card).contains(current) && !waiting.contains(cardId)) {
        waiting.add(cardId);
        stack.add(cardId);
      }
    }
  }
  return waiting;
}

/// A card that's gone is waited for by nobody.
void pruneDependencies(Json board) {
  final ids = {for (final card in allCards(board)) card['id']};
  for (final card in allCards(board)) {
    final dependsOn = card['dependsOn'];
    if (dependsOn is List && dependsOn.isNotEmpty) {
      card['dependsOn'] = dependsOn.where(ids.contains).toList();
    }
  }
}

/// Gives a task these first and last days (a milestone only its first, as both).
void setSpan(Json card, int start, int end) {
  card['start'] = isoDateOf(start);
  final int dueDay;
  if (card['milestone'] == true) {
    dueDay = start;
  } else {
    dueDay = end;
  }
  card['due'] = isoDateOf(dueDay);
}

/* ---- layout ---- */

/// One row of the timeline: where it starts (`y`), how tall it is (`h`), and what it shows.
class TimelineRow {
  TimelineRow(this.kind, this.y, this.height, {this.column, this.card, this.colour});
  final String kind; // phase | task | add | addPhase
  final double y;
  final double height;
  final Json? column;
  final Json? card;
  final String? colour;
}

/// The rows top to bottom: each phase, its tasks, and a row to add one; then one to add a phase.
({List<TimelineRow> rows, double height}) rowsOf(Json board) {
  final rows = <TimelineRow>[];
  var y = 0.0;
  final columns = columnsOf(board);
  for (var columnIndex = 0; columnIndex < columns.length; columnIndex = columnIndex + 1) {
    final column = columns[columnIndex];
    final colour = phaseColours[columnIndex % phaseColours.length];
    rows.add(TimelineRow('phase', y, phaseRowHeight, column: column, colour: colour));
    y = y + phaseRowHeight;
    for (final card in cardsOf(column)) {
      final labels = labelsOf(card);
      final Object? ownColour;
      if (labels.isEmpty) {
        ownColour = null;
      } else {
        ownColour = labels.first['color'];
      }
      final String taskColour;
      if (ownColour is String && ownColour.isNotEmpty) {
        taskColour = ownColour;
      } else {
        taskColour = colour;
      }
      rows.add(TimelineRow('task', y, taskRowHeight, column: column, card: card, colour: taskColour));
      y = y + taskRowHeight;
    }
    rows.add(TimelineRow('add', y, addRowHeight, column: column));
    y = y + addRowHeight;
  }
  rows.add(TimelineRow('addPhase', y, addRowHeight));
  y = y + addRowHeight;
  return (rows: rows, height: y);
}

/// The days on show: the first one (`lo`), how many, and today, all as day numbers.
class TimelineRange {
  const TimelineRange(this.firstDay, this.days, this.today);
  final int firstDay;
  final int days;
  final int today;
}

/// The days on show: every task and today, with a margin, from the start of a week (Monday) or
/// month, and wide enough to fill the space there is.
TimelineRange rangeOf(Json board, String zoom, double minWidth, {String? today}) {
  final zoomLevel = zooms[zoom]!;
  final String todayDate;
  if (today == null) {
    todayDate = todayIsoDate();
  } else {
    todayDate = today;
  }
  final todayNumber = dayOf(todayDate);
  var firstDay = todayNumber;
  var lastDay = todayNumber;
  for (final card in allCards(board)) {
    final span = spanOf(card, today: today);
    if (span != null) {
      if (span.start < firstDay) {
        firstDay = span.start;
      }
      if (span.end > lastDay) {
        lastDay = span.end;
      }
    }
  }
  firstDay = firstDay - zoomLevel.margin;
  lastDay = lastDay + zoomLevel.margin;
  // Back to the Monday (weeks) or the 1st of the month (months and quarters) before.
  final firstDate = dateOf(firstDay);
  if (zoom == 'weeks') {
    firstDay = firstDay - (_utcDay(firstDate) + 6) % 7;
  } else {
    firstDay = (DateTime.utc(firstDate.year, firstDate.month, 1).millisecondsSinceEpoch / _millisecondsPerDay).round();
  }
  final daysNeeded = (minWidth / zoomLevel.pixelsPerDay).ceil();
  final int days;
  if (lastDay - firstDay + 1 > daysNeeded) {
    days = lastDay - firstDay + 1;
  } else {
    days = daysNeeded;
  }
  return TimelineRange(firstDay, days, todayNumber);
}

/// One label in the header: where it starts (`x`), its words, and its width (`w`).
class TimelineTick {
  const TimelineTick(this.x, this.text, {this.width = 0, this.weekend = false});
  final double x;
  final String text;
  final double width;
  final bool weekend;
}

/// One gridline down the chart; a strong one starts a week, month or quarter.
class TimelineLine {
  const TimelineLine(this.x, this.strong);
  final double x;
  final bool strong;
}

/// The two rows of the header and the gridlines under them.
({List<TimelineTick> top, List<TimelineTick> bottom, List<TimelineLine> lines}) scaleOf(TimelineRange range, String zoom) {
  final pixelsPerDay = zooms[zoom]!.pixelsPerDay;
  final top = <TimelineTick>[];
  final bottom = <TimelineTick>[];
  final lines = <TimelineLine>[];
  String? lastTop;
  for (var dayNumber = range.firstDay; dayNumber < range.firstDay + range.days; dayNumber = dayNumber + 1) {
    final date = dateOf(dayNumber);
    final x = (dayNumber - range.firstDay) * pixelsPerDay;
    final monthIndex = date.month - 1;
    final year = date.year;
    final day = date.day;
    final weekday = _utcDay(date);
    // The top row: a label each time the month (or quarter) changes.
    final String topKey;
    if (zoom == 'quarters') {
      topKey = '${year}Q${monthIndex ~/ 3}';
    } else {
      topKey = '$year-$monthIndex';
    }
    if (topKey != lastTop) {
      final String topText;
      if (zoom == 'quarters') {
        topText = 'Q${monthIndex ~/ 3 + 1} $year';
      } else {
        topText = '${months[monthIndex]} $year';
      }
      top.add(TimelineTick(x, topText));
      lastTop = topKey;
    }
    // The bottom row and the gridlines: every day, every Monday, or every 1st of the month.
    if (zoom == 'weeks') {
      bottom.add(TimelineTick(x, '${_daysOfWeek[weekday]} $day', width: pixelsPerDay, weekend: weekday % 6 == 0));
      lines.add(TimelineLine(x, weekday == 1));
    } else if (zoom == 'months' && weekday == 1) {
      bottom.add(TimelineTick(x, '$day', width: 7 * pixelsPerDay));
      lines.add(TimelineLine(x, day <= 7));
    } else if (zoom == 'quarters' && day == 1) {
      bottom.add(TimelineTick(x, months[monthIndex], width: 30 * pixelsPerDay));
      lines.add(TimelineLine(x, monthIndex % 3 == 0));
    }
  }
  return (top: top, bottom: bottom, lines: lines);
}

/// "3 Nov".
String formatDay(int dayNumber) {
  final date = dateOf(dayNumber);
  return '${date.day} ${months[date.month - 1]}';
}

/// A task's dates as its row says them.
String whenOf(Json card, {String? today}) {
  final span = spanOf(card, today: today);
  if (span == null) {
    return 'No dates';
  }
  final actual = actualOf(card, today: today);
  if (actual != null) {
    final String work;
    if (!isIsoDate(card['completed'])) {
      work = '${formatDay(actual.start)} – now';
    } else if (actual.start == actual.end) {
      work = formatDay(actual.start);
    } else {
      work = '${formatDay(actual.start)} – ${formatDay(actual.end)}';
    }
    if (isIsoDate(card['due'])) {
      return 'Due ${formatDay(dayOf(card['due'] as String))} · $work';
    } else {
      return work;
    }
  }
  if (span.start == span.end) {
    return formatDay(span.start);
  } else {
    return '${formatDay(span.start)} – ${formatDay(span.end)}';
  }
}

/// Late: past its due date, not completed and not all ticked off. Never a milestone.
bool isLate(Json card, {String? today}) {
  if (card['milestone'] == true) {
    return false;
  }
  if (!isIsoDate(card['due'])) {
    return false;
  }
  final due = card['due'] as String;
  final String todayDate;
  if (today == null) {
    todayDate = todayIsoDate();
  } else {
    todayDate = today;
  }
  return due.compareTo(todayDate) < 0 && !isIsoDate(card['completed']) && progressOf(card) < 1;
}
