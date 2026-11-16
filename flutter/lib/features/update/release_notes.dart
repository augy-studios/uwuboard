// What's new in a release, for the Updates page, from its notes on GitHub as
// announcements/release-notes-<version>.md writes them: the first paragraph as the summary, and
// under "## What's new" (or "What's fixed", "What's changed") each "###" heading as a group of its
// items, "- **Title**: text" as a title and its text. Plain text, the Markdown taken out. The same
// as notesOf() in sgbus-timings' main-site/api/_lib/release.js, done here so it reads the site's
// /api/app-release as it is.

class ReleaseItem {
  ReleaseItem(this.title, this.text);
  final String title;
  String text;
}

class ReleaseGroup {
  ReleaseGroup(this.title);
  final String title;
  final List<ReleaseItem> items = [];
}

class ReleaseNotes {
  ReleaseNotes(this.summary, this.groups);
  final String summary;
  final List<ReleaseGroup> groups;

  /// How many items there are across all the groups.
  int get count {
    return groups.fold(0, (total, group) {
      return total + group.items.length;
    });
  }

  /// The Markdown in [markdown] taken out: bold, code, links and underscored emphasis become
  /// their plain words, and runs of whitespace become one space.
  static String plain(String markdown) {
    return markdown
        .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (match) {
          return match[1]!;
        })
        .replaceAllMapped(RegExp(r'`([^`]+)`'), (match) {
          return match[1]!;
        })
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (match) {
          return match[1]!;
        })
        .replaceAllMapped(RegExp(r'(^|[\s(])_([^_]+)_(?=[\s).,:;]|$)'), (match) {
          return '${match[1]}${match[2]}';
        })
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Reads a release's Markdown notes: the first paragraph as the summary (unless it is a
  /// heading or a table), then the groups and items under the "What's new" heading.
  static ReleaseNotes parse(String? body) {
    String bodyText;
    if (body == null) {
      bodyText = '';
    } else {
      bodyText = body;
    }
    final text = bodyText.replaceAll('\r\n', '\n');
    final firstParagraph = text.trim().split(RegExp(r'\n\s*\n')).first;
    String summary;
    if (firstParagraph.startsWith('#') || firstParagraph.startsWith('|')) {
      summary = '';
    } else {
      summary = plain(firstParagraph);
    }
    final groups = <ReleaseGroup>[];
    final whatsNewHeading = RegExp(r"^##\s+What.s (new|fixed|changed)\s*$", multiLine: true, caseSensitive: false).firstMatch(text);
    if (whatsNewHeading != null) {
      ReleaseGroup? group;
      for (final line in text.substring(whatsNewHeading.end).split('\n')) {
        // The next "##" heading ends the section.
        if (RegExp(r'^##\s').hasMatch(line)) {
          break;
        }
        final groupHeading = RegExp(r'^###\s+(.+)').firstMatch(line);
        if (groupHeading != null) {
          group = ReleaseGroup(plain(groupHeading[1]!));
          groups.add(group);
          continue;
        }
        final item = RegExp(r'^[-*]\s+(.+)').firstMatch(line);
        if (item != null) {
          // An item before any "###" heading goes in a group of its own.
          if (group == null) {
            group = ReleaseGroup('What’s new');
            groups.add(group);
          }
          final titled = RegExp(r'^\*\*(.+?)\*\*\s*[:.]?\s*(.*)$').firstMatch(item[1]!);
          ReleaseItem releaseItem;
          if (titled != null) {
            releaseItem = ReleaseItem(plain(titled[1]!).replaceFirst(RegExp(r'[:.]$'), ''), plain(titled[2]!));
          } else {
            releaseItem = ReleaseItem('', plain(item[1]!));
          }
          group.items.add(releaseItem);
        } else if (group != null && group.items.isNotEmpty && RegExp(r'^\s+\S').hasMatch(line)) {
          // A line carried on, or a point under the item: part of the item.
          final lastItem = group.items.last;
          lastItem.text = '${lastItem.text} ${plain(line.replaceFirst(RegExp(r'^\s*[-*]\s+'), ''))}'.trim();
        }
      }
    }
    final nonEmptyGroups = groups.where((group) {
      return group.items.isNotEmpty;
    }).toList();
    return ReleaseNotes(summary, nonEmptyGroups);
  }
}
