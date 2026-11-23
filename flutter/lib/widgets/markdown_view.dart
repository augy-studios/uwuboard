// A card's description drawn formatted (lib/data/markdown.dart): in the card window, where its
// links open and its spoilers show when pressed, and as a couple of lines on the card on the
// board, where a press opens the card instead. The site draws the same with js/markdown.js.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/board.dart' show Json;
import '../data/markdown.dart';
import '../theme/theme.dart';

const _mono = TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Consolas', 'Menlo', 'DejaVu Sans Mono', 'Liberation Mono']);

/// Turns inline nodes into spans. `still`: links only coloured and spoilers kept hidden, for a
/// card on the board. Otherwise links open in the browser and a spoiler shows when pressed; the
/// recognizers made go into `recognizers`, for the widget to dispose of.
class _Spans {
  _Spans(this.c, {this.still = false, this.revealed = const {}, this.onReveal, List<TapGestureRecognizer>? recognizers}) : recognizers = recognizers ?? [];

  final UwuColors c;
  final bool still;
  final Set<int> revealed;
  final void Function(int index)? onReveal;
  final List<TapGestureRecognizer> recognizers;
  int _spoiler = 0;

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final r = TapGestureRecognizer()..onTap = onTap;
    recognizers.add(r);
    return r;
  }

  static TextDecoration _plus(TextDecoration? had, TextDecoration add) => had == null || had == TextDecoration.none ? add : TextDecoration.combine([had, add]);

  List<InlineSpan> of(List<Json> nodes, TextStyle style, [TapGestureRecognizer? tap]) => [for (final n in nodes) ..._one(n, style, tap)];

  Iterable<InlineSpan> _one(Json n, TextStyle style, TapGestureRecognizer? tap) sync* {
    List<Json> kids() => (n['c'] as List).cast<Json>();
    final cursor = tap == null ? MouseCursor.defer : SystemMouseCursors.click;
    switch (n['t']) {
      case 'text':
        yield TextSpan(text: '${n['v']}', style: style, recognizer: tap, mouseCursor: cursor);
      case 'mono':
        yield TextSpan(
          text: '${n['v']}',
          style: style.merge(_mono).copyWith(fontSize: (style.fontSize ?? 14) * 0.9, backgroundColor: c.ink.withValues(alpha: 0.09)),
          recognizer: tap,
          mouseCursor: cursor,
        );
      case 'b':
        yield* of(kids(), style.copyWith(fontWeight: FontWeight.w700), tap);
      case 'i':
        yield* of(kids(), style.copyWith(fontStyle: FontStyle.italic), tap);
      case 'u':
        yield* of(kids(), style.copyWith(decoration: _plus(style.decoration, TextDecoration.underline)), tap);
      case 's':
        yield* of(kids(), style.copyWith(decoration: _plus(style.decoration, TextDecoration.lineThrough)), tap);
      case 'spoiler':
        final index = _spoiler++;
        if (!still && revealed.contains(index)) {
          yield* of(kids(), style.copyWith(backgroundColor: c.ink.withValues(alpha: 0.12)), tap);
        } else {
          // Hidden: the words in the box's own colour, read out as a spoiler, not as themselves.
          yield TextSpan(
            text: plainOf(kids()),
            semanticsLabel: still ? 'spoiler' : 'Spoiler, press to show',
            style: style.copyWith(color: c.muted, backgroundColor: c.muted, decoration: TextDecoration.none),
            recognizer: still || onReveal == null ? null : _tap(() => onReveal!(index)),
            mouseCursor: still ? MouseCursor.defer : SystemMouseCursors.click,
          );
        }
      case 'link':
        final href = '${n['href']}';
        final linkStyle = style.copyWith(color: c.brandInk, decoration: _plus(style.decoration, TextDecoration.underline));
        yield* of(kids(), linkStyle, still ? null : _tap(() => launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication)));
    }
  }
}

/// The whole description, formatted.
class MarkdownView extends StatefulWidget {
  const MarkdownView(this.text, {super.key});
  final String text;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  final _recognizers = <TapGestureRecognizer>[];
  final _revealed = <int>{};
  late List<Json> _blocks = parseMarkdown(widget.text);

  @override
  void didUpdateWidget(MarkdownView old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _blocks = parseMarkdown(widget.text);
      _revealed.clear();
    }
  }

  void _dropRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _dropRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _dropRecognizers();
    final c = UwuColors.of(context);
    final base = DefaultTextStyle.of(context).style.copyWith(color: c.ink, fontSize: 14, height: 1.45);
    final spans = _Spans(c, revealed: _revealed, onReveal: (i) => setState(() => _revealed.add(i)), recognizers: _recognizers);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: _blocksOf(_blocks, spans, base, c));
  }

  List<Widget> _blocksOf(List<Json> blocks, _Spans spans, TextStyle base, UwuColors c) {
    Widget gap(Widget child, [double bottom = 6]) => Padding(padding: EdgeInsets.only(bottom: bottom), child: child);
    List<Json> kids(Object? v) => (v as List).cast<Json>();
    final out = <Widget>[];
    for (final b in blocks) {
      switch (b['t']) {
        case 'p':
          final lines = (b['lines'] as List).map((l) => (l as List).cast<Json>()).toList();
          out.add(
            gap(
              Text.rich(
                TextSpan(
                  children: [
                    for (var i = 0; i < lines.length; i++) ...[if (i > 0) TextSpan(text: '\n', style: base), ...spans.of(lines[i], base)],
                  ],
                ),
              ),
            ),
          );
        case 'h':
          final level = b['level'] as int;
          final size = 14 * const [1.45, 1.25, 1.1][level - 1];
          out.add(
            Padding(
              padding: EdgeInsets.only(top: out.isEmpty ? 0 : 6, bottom: 4),
              child: Semantics(
                header: true,
                child: Text.rich(TextSpan(children: spans.of(kids(b['c']), base.copyWith(fontSize: size, fontWeight: FontWeight.w700, height: 1.3)))),
              ),
            ),
          );
        case 'sub':
          out.add(gap(Text.rich(TextSpan(children: spans.of(kids(b['c']), base.copyWith(fontSize: 14 * 0.82, color: c.muted))))));
        case 'quote':
          out.add(
            gap(
              Container(
                padding: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: c.border, width: 4)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _blocksOf(kids(b['c']), spans, base, c)),
              ),
            ),
          );
        case 'list':
          out.add(
            gap(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final it in kids(b['items']))
                    Padding(
                      padding: EdgeInsets.only(left: 18.0 * (it['d'] as int)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ExcludeSemantics(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 14),
                              child: Text(it['o'] == true ? '${it['n']}.' : '•', style: base.copyWith(color: c.muted)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(child: Text.rich(TextSpan(children: spans.of(kids(it['c']), base)))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        case 'code':
          out.add(
            gap(
              Container(
                decoration: BoxDecoration(
                  color: c.ink.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: c.ink.withValues(alpha: 0.14)),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Text('${b['v']}', style: base.merge(_mono).copyWith(fontSize: 13, height: 1.4)),
                ),
              ),
            ),
          );
      }
    }
    if (out.isNotEmpty && out.last is Padding) {
      // No space after the last block.
      final last = out.removeLast() as Padding;
      out.add(last.child!);
    }
    return out;
  }
}

/// The first two lines of a description, for the card on the board: formatted, but nothing in
/// it pressable (a press opens the card), and spoilers stay hidden.
class MarkdownSnippet extends StatelessWidget {
  const MarkdownSnippet(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final lines = snippetLines(parseMarkdown(text));
    if (lines.isEmpty) return const SizedBox.shrink();
    final base = (style ?? TextStyle(fontSize: 12, color: c.muted, height: 1.35));
    final spans = _Spans(c, still: true);
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < lines.length; i++) ...[if (i > 0) TextSpan(text: '\n', style: base), ...spans.of(lines[i], base)],
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// A snippet's words alone, for a card's screen-reader summary.
String snippetPlain(String text) => snippetLines(parseMarkdown(text)).map(plainOf).join(' ');
