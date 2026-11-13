// The Updates page reads each release's notes as announcements/release-notes-<version>.md writes
// them: a summary, then groups of titled items, with the Markdown taken out.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uwuboard/features/update/release_notes.dart';

void main() {
  test('1.0.0: the summary, three groups, the download table and install steps left out', () {
    final n = ReleaseNotes.parse(File('../announcements/release-notes-1.0.0.md').readAsStringSync());
    expect(n.summary, startsWith('uwuBoard is now an app'));
    expect(n.groups.map((g) => g.title), ['Android app', 'Windows, macOS and Linux apps', 'Everywhere']);
    final first = n.groups.first.items.first;
    expect(first.title, 'A real app');
    expect(first.text, startsWith('every screen built for Android'));
    for (final g in n.groups) {
      for (final i in g.items) {
        expect('${i.title}${i.text}', isNot(contains('**')));
        expect('${i.title}${i.text}', isNot(contains('`')));
      }
    }
  });

  test('1.0.1: "What\'s fixed" is read as its changes', () {
    final n = ReleaseNotes.parse(File('../announcements/release-notes-1.0.1.md').readAsStringSync());
    expect(n.summary, isNotEmpty);
    expect(n.count, greaterThan(3));
  });

  test('items without a title, and notes with no heading', () {
    final n = ReleaseNotes.parse('Small fixes.\n\n## What\'s new\n- Faster start\n  and less memory');
    expect(n.summary, 'Small fixes.');
    expect(n.groups.single.items.single.title, '');
    expect(n.groups.single.items.single.text, 'Faster start and less memory');
    expect(ReleaseNotes.parse('').groups, isEmpty);
  });
}
