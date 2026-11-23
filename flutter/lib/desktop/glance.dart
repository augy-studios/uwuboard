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

  /// When it's due, in words: 'overdue by 3 days', 'today', 'tomorrow', 'in 5 days'.
  String get when {
    if (days < 0) {
      if (days == -1) {
        return 'overdue by a day';
      } else {
        return 'overdue by ${-days} days';
      }
    } else {
      if (days == 0) {
        return 'today';
      } else if (days == 1) {
        return 'tomorrow';
      } else {
        return 'in $days days';
      }
    }
  }
}

/// A board's cards with a due date, not all ticked off, soonest first.
List<DueCard> dueCards(Json board, {DateTime? now}) {
  final today = dayOf(todayIsoDate(now));
  final result = <DueCard>[];
  for (final card in allCards(board)) {
    final due = card['due'];
    if (!isIsoDate(due)) {
      continue;
    }
    final checklist = checklistOf(card);
    // A card whose checklist is all ticked off is done, so it isn't due any more.
    if (checklist.isNotEmpty &&
        checklist.every((item) {
          return item['done'] == true;
        })) {
      continue;
    }
    result.add(DueCard(board, card, dayOf(due as String) - today));
  }
  result.sort((first, second) {
    return first.days.compareTo(second.days);
  });
  return result;
}

/// The tray tooltip: the board's name, then one line per card, cut to 127 characters (Windows'
/// most) with an ellipsis.
String trayText(Json board, {DateTime? now}) {
  final due = dueCards(board, now: now).take(4).toList();
  final lines = <String>['${board['name']}'];
  if (due.isEmpty) {
    lines.add('No cards due');
  } else {
    for (final dueCard in due) {
      lines.add('${dueCard.card['title']}: ${dueCard.when}');
    }
  }
  final text = lines.join('\n');
  if (text.length <= 127) {
    return text;
  } else {
    return '${text.substring(0, 126)}…';
  }
}

class Glance {
  Glance._();

  static Timer? _dueTimer;
  static Timer? _trayTimer;

  /// True until the first due check has run (that one only records what's already due).
  static bool _firstCheck = true;

  /// Set by tray.dart: puts a new tooltip, title or menu up.
  static void Function(String tooltip, String title)? onTray;
  static final ValueNotifier<Json?> followed = ValueNotifier(null);

  /// Starts the due-card check (every minute, first after 5 seconds) and the tray countdown
  /// (every 30 seconds), and picks up the board followed last time.
  static void start() {
    final oldDueTimer = _dueTimer;
    if (oldDueTimer != null) {
      oldDueTimer.cancel();
    }
    _dueTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      checkDue();
    });
    Timer(const Duration(seconds: 5), checkDue);
    final oldTrayTimer = _trayTimer;
    if (oldTrayTimer != null) {
      oldTrayTimer.cancel();
    }
    _trayTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      refreshTray();
    });
    final stop = DeskSettings.get<Map<String, dynamic>>('trayStop');
    if (stop != null) {
      followed.value = stop;
    }
    AppState.instance.addListener(_boardsChanged);
    _boardsChanged();
  }

  /// The favourites last sent to the runner, as text, so they're only sent again when changed.
  static String _lastFavourites = '';

  /// The boards changed: sends the first 10 to the runner as favourites (if they're different
  /// from last time) and refreshes the tray countdown.
  static void _boardsChanged() {
    final favourites = [
      for (final board in AppState.instance.boards.take(10)) {'code': board['id'], 'name': board['name']},
    ];
    final key = favourites.toString();
    if (key != _lastFavourites) {
      _lastFavourites = key;
      DeskSettings.write({'favourites': favourites});
      Runner.setFavourites(favourites);
    }
    refreshTray();
  }

  /// Follows a board in the tray, or stops (null).
  static void follow(Json? board) {
    Map<String, dynamic>? followedBoard;
    if (board == null) {
      followedBoard = null;
    } else {
      followedBoard = {'code': board['id'], 'name': board['name']};
    }
    DeskSettings.write({'trayStop': followedBoard});
    followed.value = followedBoard;
    refreshTray();
  }

  /// The board being followed in the tray, found among the boards here, or null.
  static Json? _followedBoard() {
    final following = followed.value;
    if (following == null) {
      return null;
    }
    for (final board in AppState.instance.boards) {
      if (board['id'] == following['code']) {
        return board;
      }
    }
    return null;
  }

  /// Puts the followed board's due cards in the tray tooltip, beside the menu bar icon and on
  /// the Dock's badge; or clears them when no board is followed.
  static void refreshTray() {
    final board = _followedBoard();
    if (board == null) {
      final trayHandler = onTray;
      if (trayHandler != null) {
        trayHandler(Desktop.name, '');
      }
      Runner.setBadge('');
      return;
    }
    final due = dueCards(board);
    final urgent = due.where((dueCard) {
      return dueCard.days <= 0;
    }).length;
    final trayHandler = onTray;
    if (trayHandler != null) {
      final tooltip = trayText(board);
      String title;
      if (due.isEmpty) {
        title = '';
      } else {
        title = ' ${due.first.card['title']} · ${due.first.when}';
      }
      trayHandler(tooltip, title);
    }
    String badge;
    if (urgent > 0) {
      badge = '$urgent';
    } else {
      badge = '';
    }
    Runner.setBadge(badge);
  }

  /// A board's last-changed time, or 0 if it has none.
  static num _updatedAtOf(Json board) {
    final updatedAt = board['updatedAt'] as num?;
    if (updatedAt == null) {
      return 0;
    }
    return updatedAt;
  }

  /// Due today and overdue, said once per card and due date.
  static Future<void> checkDue() async {
    final app = AppState.instance;
    if (!app.shown) {
      return;
    }
    // Signed in: fetch the boards again, so a card changed on another device counts too.
    if (app.signedIn) {
      try {
        final data = await Api.call('GET', '/boards/list');
        final freshBoards = boardsFromJson(data['boards']);
        // Only boards whose copy here is older than the server's, so nothing typed just now is lost.
        var changed = false;
        for (final freshBoard in freshBoards) {
          final index = app.boards.indexWhere((board) {
            return board['id'] == freshBoard['id'];
          });
          if (index < 0) {
            app.boards.add(freshBoard);
            changed = true;
          } else if (_updatedAtOf(freshBoard) > _updatedAtOf(app.boards[index])) {
            app.boards[index] = freshBoard;
            changed = true;
          }
        }
        if (changed) {
          app.boardsChanged(freshBoards);
        }
      } catch (error) {
        // Offline: what's here.
      }
    }
    // Find the cards due today or overdue that haven't been announced for this due date yet.
    Map<String, dynamic>? seenBefore = DeskSettings.get<Map<String, dynamic>>('dueSeen');
    if (seenBefore == null) {
      seenBefore = const {};
    }
    final seen = Map<String, dynamic>.from(seenBefore);
    final newlyDue = <DueCard>[];
    for (final board in app.boards) {
      for (final dueCard in dueCards(board)) {
        if (dueCard.days > 0) {
          continue;
        }
        final key = '${dueCard.card['id']}';
        String state;
        if (dueCard.days < 0) {
          state = 'late';
        } else {
          state = 'today';
        }
        final mark = '${dueCard.card['due']}:$state';
        if (seen[key] == mark) {
          continue;
        }
        seen[key] = mark;
        newlyDue.add(dueCard);
      }
    }
    DeskSettings.write({'dueSeen': seen});
    final first = _firstCheck;
    _firstCheck = false;
    if (first || newlyDue.isEmpty) {
      return;
    }
    // One notification: the first card, and how many more there are.
    final dueCard = newlyDue.first;
    final more = newlyDue.length - 1;
    String title;
    if (dueCard.days < 0) {
      title = '${dueCard.card['title']} is overdue';
    } else {
      title = '${dueCard.card['title']} is due today';
    }
    String moreText;
    if (more > 0) {
      moreText = '\nAnd $more more…';
    } else {
      moreText = '';
    }
    DeskNotify.show(
      title: title,
      body: '${dueCard.board['name']}$moreText',
      link: 'uwu://board/b/${dueCard.board['id']}',
    );
  }
}
