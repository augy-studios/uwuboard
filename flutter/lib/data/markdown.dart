// A card's description, formatted the way Discord formats a message: the site's
// main-site/js/markdown.js in Dart, giving the same plain data (test/parity_test.dart checks the
// two against each other, through tool/expected.mjs). lib/widgets/markdown_view.dart draws it.
//
//   Text:   **bold**  *italic* or _italic_  __underline__  ~~strikethrough~~  `code`  ||spoiler||
//   Lines:  # ## ### headings, -# small text, > quote (>>> quotes the rest), - or * bullets and
//           1. numbers (two spaces in for each level), ``` code blocks ```.
//   Links:  https:// addresses, <https://…>, and [words](https://…). Only http and https.
//   A backslash shows the next symbol as it is.
//
// Blocks:  {t: p, lines: [[inline]]}  {t: h, level, c}  {t: sub, c}  {t: quote, c: [blocks]}
//          {t: list, items: [{d, o, n, c}]}  {t: code, lang, v}
// Inline:  {t: text, v}  {t: mono, v}  {t: b|i|u|s|spoiler, c}  {t: link, href, c}
import 'board.dart' show Json;

const _escapable = r'\*_~|`[]()#>-.<';
const _maxDepth = 8;
const _trailing = '.,!?;:\'"*_~|';
final _word = RegExp(r'[\p{L}\p{N}]', unicode: true);

String _at(String s, int i) => i >= 0 && i < s.length ? s[i] : '';
bool _isSpace(String c) => c == ' ' || c == '\t' || c == '\n';
bool _isWord(String c) => c.isNotEmpty && _word.hasMatch(c);

/* ---- inline ---- */

// Where `d` closes, searching from `from`: past escapes, never at `from` itself (no empty runs),
// and for a doubled marker the last two of a longer run, so ***x*** is bold italic.
int _closeOf(String s, String d, int from) {
  for (var k = from; k < s.length; k++) {
    if (s[k] == r'\') {
      k++;
      continue;
    }
    if (k > from && s.startsWith(d, k)) {
      while (d.length == 2 && _at(s, k + 2) == d[0]) {
        k++;
      }
      return k;
    }
  }
  return -1;
}

// Where a single * or _ closes: not after a space, stepping over doubled markers, and _ only at
// the end of a word, so snake_case stays as it is.
int _italicClose(String s, String ch, int from) {
  for (var k = from; k < s.length; k++) {
    if (s[k] == r'\') {
      k++;
      continue;
    }
    if (s[k] != ch) continue;
    if (_at(s, k + 1) == ch) {
      k++;
      continue;
    }
    if (k > from && !_isSpace(s[k - 1]) && (ch == '*' || !_isWord(_at(s, k + 1)))) return k;
  }
  return -1;
}

// A bare address: trailing punctuation is the sentence's, and a ) only when unbalanced.
String _trimUrl(String url) {
  for (;;) {
    final last = url[url.length - 1];
    if (_trailing.contains(last)) {
      url = url.substring(0, url.length - 1);
    } else if (last == ')' && url.split('(').length < url.split(')').length) {
      url = url.substring(0, url.length - 1);
    } else {
      return url;
    }
  }
}

const _pairs = [('||', 'spoiler'), ('**', 'b'), ('__', 'u'), ('~~', 's')];
final _masked = RegExp(r'(https?://[^\s)]+)\)');
final _angled = RegExp(r'<(https?://[^\s>]+)>');
final _bare = RegExp(r'https?://[^\s<]+');

List<Json> inlineOf(String s, [int depth = 0, bool inLink = false]) {
  final out = <Json>[];
  final buf = StringBuffer();
  void push(Json node) {
    if (buf.isNotEmpty) {
      out.add({'t': 'text', 'v': buf.toString()});
      buf.clear();
    }
    out.add(node);
  }

  var i = 0;
  outer:
  while (i < s.length) {
    final ch = s[i];
    if (ch == r'\' && i + 1 < s.length && _escapable.contains(s[i + 1])) {
      buf.write(s[i + 1]);
      i += 2;
      continue;
    }

    if (ch == '`') {
      final fence = s.startsWith('``', i) ? '``' : '`';
      final end = s.indexOf(fence, i + fence.length);
      if (end > i + fence.length) {
        push({'t': 'mono', 'v': s.substring(i + fence.length, end)});
        i = end + fence.length;
        continue;
      }
    }

    if (depth < _maxDepth) {
      for (final (d, t) in _pairs) {
        if (!s.startsWith(d, i)) continue;
        final end = _closeOf(s, d, i + d.length);
        if (end != -1) {
          push({'t': t, 'c': inlineOf(s.substring(i + d.length, end), depth + 1, inLink)});
          i = end + d.length;
          continue outer;
        }
      }
      if ((ch == '*' || ch == '_') && _at(s, i + 1).isNotEmpty && !_isSpace(s[i + 1]) && (ch == '*' || !_isWord(_at(s, i - 1)))) {
        final end = _italicClose(s, ch, i + 1);
        if (end != -1) {
          push({'t': 'i', 'c': inlineOf(s.substring(i + 1, end), depth + 1, inLink)});
          i = end + 1;
          continue;
        }
      }
    }

    if (!inLink) {
      if (ch == '[') {
        final mid = s.indexOf('](', i + 1);
        if (mid > i + 1) {
          final m = _masked.matchAsPrefix(s, mid + 2);
          if (m != null) {
            push({'t': 'link', 'href': m[1], 'c': inlineOf(s.substring(i + 1, mid), depth + 1, true)});
            i = m.end;
            continue;
          }
        }
      }
      if (ch == '<') {
        final m = _angled.matchAsPrefix(s, i);
        if (m != null) {
          push({
            't': 'link',
            'href': m[1],
            'c': [
              {'t': 'text', 'v': m[1]},
            ],
          });
          i = m.end;
          continue;
        }
      }
      if (ch == 'h' && !_isWord(_at(s, i - 1))) {
        final m = _bare.matchAsPrefix(s, i);
        if (m != null) {
          final url = _trimUrl(m[0]!);
          if (url.length > url.indexOf('//') + 2) {
            push({
              't': 'link',
              'href': url,
              'c': [
                {'t': 'text', 'v': url},
              ],
            });
            i += url.length;
            continue;
          }
        }
      }
    }

    buf.write(ch);
    i++;
  }
  if (buf.isNotEmpty) out.add({'t': 'text', 'v': buf.toString()});
  return out;
}

/* ---- blocks ---- */

final _fence = RegExp(r'^\s*```(.*)$');
final _bigQuote = RegExp(r'^>>> (.*)$');
final _quote = RegExp(r'^> |^>$');
final _heading = RegExp(r'^(#{1,3}) +(\S.*)$');
final _sub = RegExp(r'^-# +(\S.*)$');
final _item = RegExp(r'^( *)([-*]|\d{1,9}\.) +(\S.*)$');
final _lang = RegExp(r'^[\w+#.-]{1,20}$');

List<Json> parseMarkdown(String? src, [bool inQuote = false]) {
  final lines = (src ?? '').replaceAll(RegExp(r'\r\n?'), '\n').split('\n');
  final blocks = <Json>[];
  Json? open; // the paragraph or list the next line can join
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    RegExpMatch? m;

    if ((m = _fence.firstMatch(line)) != null) {
      final after = m![1]!;
      final same = after.indexOf('```');
      if (same > 0) {
        blocks.add({'t': 'code', 'lang': '', 'v': after.substring(0, same)});
        open = null;
        continue;
      }
      if (same == -1) {
        var k = i + 1;
        while (k < lines.length && !lines[k].contains('```')) {
          k++;
        }
        if (k < lines.length) {
          final body = <String>[];
          final lang = _lang.hasMatch(after.trim()) ? after.trim() : '';
          if (lang.isEmpty && after.trim().isNotEmpty) body.add(after);
          body.addAll(lines.sublist(i + 1, k));
          final tail = lines[k].substring(0, lines[k].indexOf('```'));
          if (tail.trim().isNotEmpty) body.add(tail);
          blocks.add({'t': 'code', 'lang': lang, 'v': body.join('\n')});
          open = null;
          i = k;
          continue;
        }
      }
    }

    if (!inQuote) {
      if ((m = _bigQuote.firstMatch(line)) != null) {
        blocks.add({'t': 'quote', 'c': parseMarkdown([m![1]!, ...lines.sublist(i + 1)].join('\n'), true)});
        return blocks;
      }
      if (_quote.hasMatch(line)) {
        final q = <String>[];
        while (i < lines.length && _quote.hasMatch(lines[i])) {
          final l = lines[i++];
          q.add(l.length > 2 ? l.substring(2) : '');
        }
        i--;
        blocks.add({'t': 'quote', 'c': parseMarkdown(q.join('\n'), true)});
        open = null;
        continue;
      }
    }

    if ((m = _heading.firstMatch(line)) != null) {
      blocks.add({'t': 'h', 'level': m![1]!.length, 'c': inlineOf(m[2]!.trim())});
      open = null;
      continue;
    }
    if ((m = _sub.firstMatch(line)) != null) {
      blocks.add({'t': 'sub', 'c': inlineOf(m![1]!)});
      open = null;
      continue;
    }
    if ((m = _item.firstMatch(line)) != null) {
      final mark = m![2]!;
      final o = mark.endsWith('.');
      final item = <String, dynamic>{
        'd': (m[1]!.length ~/ 2).clamp(0, 3),
        'o': o,
        'n': o ? int.parse(mark.substring(0, mark.length - 1)) : null,
        'c': inlineOf(m[3]!),
      };
      if (open != null && open['t'] == 'list') {
        (open['items'] as List).add(item);
      } else {
        open = {
          't': 'list',
          'items': [item],
        };
        blocks.add(open);
      }
      continue;
    }
    if (line.trim().isEmpty) {
      open = null;
      continue;
    }

    if (open != null && open['t'] == 'p') {
      (open['lines'] as List).add(inlineOf(line));
    } else {
      open = {
        't': 'p',
        'lines': [inlineOf(line)],
      };
      blocks.add(open);
    }
  }
  return blocks;
}

/// The first lines of a description, for the card on the board: block marks dropped (a heading
/// goes bold, an item keeps its bullet), at most `max` of them.
List<List<Json>> snippetLines(List<Json> blocks, [int max = 2]) {
  final out = <List<Json>>[];
  void walk(List<Json> bs) {
    for (final b in bs) {
      if (out.length >= max) return;
      switch (b['t']) {
        case 'p':
          out.addAll((b['lines'] as List).take(max - out.length).map((l) => (l as List).cast<Json>()));
        case 'h':
          out.add([
            {'t': 'b', 'c': b['c']},
          ]);
        case 'sub':
          out.add((b['c'] as List).cast<Json>());
        case 'quote':
          walk((b['c'] as List).cast<Json>());
        case 'list':
          for (final it in (b['items'] as List).take(max - out.length)) {
            out.add([
              {'t': 'text', 'v': it['o'] == true ? '${it['n']}. ' : '• '},
              ...(it['c'] as List).cast<Json>(),
            ]);
          }
        case 'code':
          final v = '${b['v']}';
          if (v.trim().isNotEmpty) {
            out.add([
              {'t': 'mono', 'v': v.split('\n').firstWhere((l) => l.trim().isNotEmpty)},
            ]);
          }
      }
    }
  }

  walk(blocks);
  return out;
}

/// The words alone, for a screen reader's summary of a card: a spoiler stays a spoiler.
String plainOf(List<Json> nodes) =>
    nodes.map((n) => n['t'] == 'spoiler' ? '(spoiler)' : n['v'] ?? plainOf((n['c'] as List? ?? const []).cast<Json>())).join();

/// The toolbar's, as the site's Markdown.format: wraps the selection (`a` to `b`) in a mark, or
/// puts an empty pair at the caret; makes it a link; or starts each selected line with "- " (or
/// takes it off, when they all have one). The new text, and what to select in it.
({String text, int from, int to}) formatText(String value, int a, int b, String kind) {
  if (a < 0 || b < 0) a = b = value.length;
  if (a > b) (a, b) = (b, a);
  final sel = value.substring(a, b);
  const marks = {'bold': '**', 'italic': '*', 'strike': '~~', 'code': '`', 'spoiler': '||', 'underline': '__'};
  final m = marks[kind];
  if (m != null) {
    return (text: value.replaceRange(a, b, '$m$sel$m'), from: a + m.length, to: a + m.length + sel.length);
  }
  if (kind == 'link') {
    final isUrl = RegExp(r'^https?://\S+$').hasMatch(sel);
    final put = isUrl ? '[]($sel)' : '[${sel.isEmpty ? 'link' : sel}](https://)';
    final text = value.replaceRange(a, b, put);
    return isUrl ? (text: text, from: a + 1, to: a + 1) : (text: text, from: a + put.length - 9, to: a + put.length - 1);
  }
  if (kind == 'list') {
    final start = a == 0 ? 0 : value.lastIndexOf('\n', a - 1) + 1;
    final nl = value.indexOf('\n', b);
    final end = nl == -1 ? value.length : nl;
    final lines = value.substring(start, end).split('\n');
    final all = lines.every((l) => l.startsWith('- '));
    final put = lines.map((l) => all ? l.substring(2) : '- $l').join('\n');
    return (text: value.replaceRange(start, end, put), from: start + put.length, to: start + put.length);
  }
  return (text: value, from: a, to: b);
}
