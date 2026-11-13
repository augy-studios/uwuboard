// At a glance, outside the window (docs/desktop-features-spec.md §7 and §9), for boards: the
// spec's "live item" is a board's due cards.
//
// - Due cards, checked every minute while the app runs (open or in the tray): a notification
//   when a card falls due today, and when one goes overdue, once each per due date. Signed in,
//   the boards are fetched again each time, so a card changed on another device counts too. The
//   first check only records what's there, so opening the app doesn't announce every old card.
// - The tray countdown: one board followed outside the window. Its next due cards in the tray
//   icon's tooltip (Windows, Linux), and beside the menu bar icon and on the Dock's badge (macOS),
//   every 30 seconds.
// - Favourites: the boards (up to 10) as the Windows Jump List and taskbar thumbnail buttons, and
//   the macOS Dock menu, through the runner's channel (runner.dart).
//
// Keys: trayStop ({ code, name }: the board followed, or null), favourites, dueSeen.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api.dart';
import '../app/state.dart';
import '../data/board.dart';
import '../data/timeline_logic.dart';
import 'desk.dart';
import 'notify.dart';
import 'runner.dart';
import 'settings.dart';

/// One due card, as the glance surfaces say it.
class DueCard {
  DueCard(this.board, this.card, this.days);
  final Json board;
  final Json card;

  /// Days until it's due: 0 today, negative overdue.
  final int days;

  String get when =>
      days < 0 ? (days == -1 ? 'overdue by a day' : 'overdue by ${-days} days') : (days == 0 ? 'today' : (days == 1 ? 'tomorrow' : 'in $days days'));
}

/// A board's cards with a due date, not all ticked off, soonest first.
List<DueCard> dueCards(Json board, {DateTime? now}) {
  final today = dayOf(todayIso(now));
  final out = <DueCard>[];
  for (final card in allCards(board)) {
    final due = card['due'];
    if (!isIso(due)) continue;
    final list = checklistOf(card);
    if (list.isNotEmpty && list.every((c) => c['done'] == true)) continue;
    out.add(DueCard(board, card, dayOf(due as String) - today));
  }
  out.sort((a, b) => a.days.compareTo(b.days));
  return out;
}

/// The tray tooltip: the board's name, then one line per card, cut to 127 characters (Windows'
/// most) with an ellipsis.
String trayText(Json board, {DateTime? now}) {
  final due = dueCards(board, now: now).take(4).toList();
  final lines = <String>['${board['name']}'];
  if (due.isEmpty) {
    lines.add('No cards due');
  } else {
    for (final d in due) {
      lines.add('${d.card['title']}: ${d.when}');
    }
  }
  final text = lines.join('\n');
  return text.length <= 127 ? text : '${text.substring(0, 126)}…';
}

class Glance {
  Glance._();

  static Timer? _due;
  static Timer? _tray;
  static bool _first = true;

  /// Set by tray.dart: puts a new tooltip, title or menu up.
  static void Function(String tooltip, String title)? onTray;
  static final ValueNotifier<Json?> followed = ValueNotifier(null);

  static void start() {
    _due?.cancel();
    _due = Timer.periodic(const Duration(minutes: 1), (_) => checkDue());
    Timer(const Duration(seconds: 5), checkDue);
    _tray?.cancel();
    _tray = Timer.periodic(const Duration(seconds: 30), (_) => refreshTray());
    final stop = DeskSettings.get<Map<String, dynamic>>('trayStop');
    if (stop != null) followed.value = stop;
    AppState.I.addListener(_boardsChanged);
    _boardsChanged();
  }

  static String _lastFavs = '';

  static void _boardsChanged() {
    final favs = [
      for (final b in AppState.I.boards.take(10)) {'code': b['id'], 'name': b['name']},
    ];
    final key = favs.toString();
    if (key != _lastFavs) {
      _lastFavs = key;
      DeskSettings.write({'favourites': favs});
      Runner.setFavourites(favs);
    }
    refreshTray();
  }

  /// Follows a board in the tray, or stops (null).
  static void follow(Json? board) {
    final v = board == null ? null : {'code': board['id'], 'name': board['name']};
    DeskSettings.write({'trayStop': v});
    followed.value = v;
    refreshTray();
  }

  static Json? _followedBoard() {
    final f = followed.value;
    if (f == null) return null;
    for (final b in AppState.I.boards) {
      if (b['id'] == f['code']) return b;
    }
    return null;
  }

  static void refreshTray() {
    final board = _followedBoard();
    if (board == null) {
      onTray?.call(Desktop.name, '');
      Runner.setBadge('');
      return;
    }
    final due = dueCards(board);
    final urgent = due.where((d) => d.days <= 0).length;
    onTray?.call(trayText(board), due.isEmpty ? '' : ' ${due.first.card['title']} · ${due.first.when}');
    Runner.setBadge(urgent > 0 ? '$urgent' : '');
  }

  /// Due today and overdue, said once per card and due date.
  static Future<void> checkDue() async {
    final app = AppState.I;
    if (!app.shown) return;
    if (app.signedIn) {
      try {
        final data = await Api.call('GET', '/boards/list');
        final fresh = boardsFromJson(data['boards']);
        // Only boards whose copy here is older than the server's, so nothing typed just now is lost.
        var changed = false;
        for (final f in fresh) {
          final i = app.boards.indexWhere((b) => b['id'] == f['id']);
          if (i < 0) {
            app.boards.add(f);
            changed = true;
          } else if ((f['updatedAt'] as num? ?? 0) > (app.boards[i]['updatedAt'] as num? ?? 0)) {
            app.boards[i] = f;
            changed = true;
          }
        }
        if (changed) app.boardsChanged(fresh);
      } catch (_) {
        // Offline: what's here.
      }
    }
    final seen = Map<String, dynamic>.from(DeskSettings.get<Map<String, dynamic>>('dueSeen') ?? const {});
    final fresh = <DueCard>[];
    for (final b in app.boards) {
      for (final d in dueCards(b)) {
        if (d.days > 0) continue;
        final key = '${d.card['id']}';
        final mark = '${d.card['due']}:${d.days < 0 ? 'late' : 'today'}';
        if (seen[key] == mark) continue;
        seen[key] = mark;
        fresh.add(d);
      }
    }
    DeskSettings.write({'dueSeen': seen});
    final first = _first;
    _first = false;
    if (first || fresh.isEmpty) return;
    final d = fresh.first;
    final more = fresh.length - 1;
    DeskNotify.show(
      title: d.days < 0 ? '${d.card['title']} is overdue' : '${d.card['title']} is due today',
      body: '${d.board['name']}${more > 0 ? '\nAnd $more more…' : ''}',
      link: 'uwu://board/b/${d.board['id']}',
    );
  }
}
