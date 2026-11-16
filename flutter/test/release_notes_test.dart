// The Updates page reads each release's notes as announcements/release-notes-<version>.md writes
// them: a summary, then groups of titled items, with the Markdown taken out.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uwuboard/features/update/release_notes.dart';

void main() {
  test('1.0.0: the summary, three groups, the download table and install steps left out', () {
    final notes = ReleaseNotes.parse(File('../announcements/release-notes-1.0.0.md').readAsStringSync());
    expect(notes.summary, startsWith('uwuBoard is now an app'));
    expect(notes.groups.map((noteGroup) {
      return noteGroup.title;
    }), ['Android app', 'Windows, macOS and Linux apps', 'Everywhere']);
    final firstItem = notes.groups.first.items.first;
    expect(firstItem.title, 'A real app');
    expect(firstItem.text, startsWith('every screen built for Android'));
    // No Markdown bold markers or code quotes are left in any item.
    for (final noteGroup in notes.groups) {
      for (final item in noteGroup.items) {
        expect('${item.title}${item.text}', isNot(contains('**')));
        expect('${item.title}${item.text}', isNot(contains('`')));
      }
    }
  });

  test('1.0.1: "What\'s fixed" is read as its changes', () {
    final notes = ReleaseNotes.parse(File('../announcements/release-notes-1.0.1.md').readAsStringSync());
    expect(notes.summary, isNotEmpty);
    expect(notes.count, greaterThan(3));
  });

  test('items without a title, and notes with no heading', () {
    final notes = ReleaseNotes.parse('Small fixes.\n\n## What\'s new\n- Faster start\n  and less memory');
    expect(notes.summary, 'Small fixes.');
    expect(notes.groups.single.items.single.title, '');
    expect(notes.groups.single.items.single.text, 'Faster start and less memory');
    expect(ReleaseNotes.parse('').groups, isEmpty);
  });
}
