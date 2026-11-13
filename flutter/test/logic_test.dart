// The app's own logic: links, version order, the desktop's update files and the glance texts.
import 'package:flutter_test/flutter_test.dart';
import 'package:uwuboard/app/links.dart';
import 'package:uwuboard/data/board.dart';
import 'package:uwuboard/desktop/glance.dart';
import 'package:uwuboard/desktop/updater.dart';
import 'package:uwuboard/features/update/update_bar.dart';

void main() {
  group('links', () {
    test('the site and the uwu://board/ scheme map to the same places', () {
      expect(parseLink('https://board.uwuapps.org/#sync/BCD234'), isA<LinkSync>().having((l) => l.code, 'code', 'BCD234'));
      expect(parseLink('uwu://board/sync/BCD234'), isA<LinkSync>());
      expect(parseLink('uwu://board/b/abc123'), isA<LinkBoard>().having((l) => l.id, 'id', 'abc123'));
      expect(parseLink('uwu://board/new'), isA<LinkNewBoard>());
      expect(parseLink('uwu://board/updates'), isA<LinkUpdates>());
      expect(parseLink('uwu://board/'), isA<LinkHome>());
      expect(parseLink('#sync/BCD234'), isA<LinkSync>());
      expect(parseLink('https://example.com/x'), isA<LinkOut>());
    });

    test("another app's host, or anything not a plain path, isn't the app's", () {
      expect(parseLink('uwu://sgbus/84009'), isNull);
      expect(parseLink('uwu://board/b/<script>'), isNull);
      expect(parseLink('javascript:alert(1)'), isNull);
      expect(parseLink('just words'), isNull);
    });
  });

  test('versions compare number by number', () {
    expect(newerVersion('1.10.0', '1.9.0'), isTrue);
    expect(newerVersion('1.0.0', '1.0.0'), isFalse);
    expect(newerVersion('1.0', '1.0.1'), isFalse);
    expect(Updater.newer('2.0.0', '1.99.99'), isTrue);
  });

  test("the desktop's update file picks this processor's file", () {
    const mac = '''
version: 1.2.0
files:
  - url: uwuboard-1.2.0-mac-arm64.zip
    sha512: ARM=
    size: 10
  - url: uwuboard-1.2.0-mac-x64.zip
    sha512: X64=
    size: 11
  - url: uwuboard-1.2.0-mac-arm64.dmg
    sha512: DMG=
    size: 12
path: uwuboard-1.2.0-mac-arm64.zip
sha512: ARM=
''';
    expect(UpdateInfo.parse(mac, arm64: true)!.file, 'uwuboard-1.2.0-mac-arm64.zip');
    expect(UpdateInfo.parse(mac)!.sha512, 'X64=');
    const win = 'version: 1.2.0\nfiles:\n  - url: uwuboard-1.2.0-setup.exe\n    sha512: EXE=\n    size: 9\npath: uwuboard-1.2.0-setup.exe\nsha512: EXE=\n';
    expect(UpdateInfo.parse(win)!.size, 9);
    expect(UpdateInfo.parse('not: yaml: at all'), isNull);
  });

  test("the tray says a board's due cards, soonest first, under 128 characters", () {
    final now = DateTime(2026, 11, 14, 9);
    Json card(String t, String due, [List<dynamic> checklist = const []]) => {'id': t, 'title': t, 'due': due, 'checklist': checklist};
    final board = {
      'id': 'b',
      'name': 'Launch',
      'columns': [
        {
          'id': 'c',
          'name': 'To Do',
          'cards': [
            card('Later', '2026-11-20'),
            card('Late', '2026-11-12'),
            card('Today', '2026-11-14'),
            card('Done already', '2026-11-13', [{'text': 'x', 'done': true}]),
            card('No date', ''),
          ],
        },
      ],
    };
    final due = dueCards(board, now: now);
    expect(due.map((d) => d.card['title']), ['Late', 'Today', 'Later']);
    expect(due.map((d) => d.when), ['overdue by 2 days', 'today', 'in 6 days']);
    expect(trayText(board, now: now), 'Launch\nLate: overdue by 2 days\nToday: today\nLater: in 6 days');
    final long = {...board, 'name': 'x' * 200};
    expect(trayText(long, now: now).length, 127);
  });
}
