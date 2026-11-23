// A card's description in the card window (the site's #card-desc-box): shown formatted, as
// Discord shows a message (lib/widgets/markdown_view.dart), and edited as text with a small
// toolbar for the marks. Empty, it's the text box straight away; leaving the box shows it
// formatted again.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/markdown.dart';
import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/markdown_view.dart';

class DescriptionField extends StatefulWidget {
  const DescriptionField({super.key, required this.controller});
  final TextEditingController controller;

  @override
  State<DescriptionField> createState() => _DescriptionFieldState();
}

class _DescriptionFieldState extends State<DescriptionField> {
  late bool _editing = widget.controller.text.trim().isEmpty;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _edit() {
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      final end = widget.controller.text.length;
      widget.controller.selection = TextSelection.collapsed(offset: end);
    });
  }

  // Focus gone from the box and its toolbar: formatted again, when there's anything to show.
  void _focusChanged(bool inside) {
    if (!inside && _editing && widget.controller.text.trim().isNotEmpty) setState(() => _editing = false);
  }

  void _format(String kind) {
    final v = widget.controller.value;
    final r = formatText(v.text, v.selection.start, v.selection.end, kind);
    widget.controller.value = TextEditingValue(
      text: r.text,
      selection: TextSelection(baseOffset: r.from, extentOffset: r.to),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final label = TextStyle(fontSize: 12.5, color: c.muted, fontWeight: FontWeight.w600);
    final box = BoxDecoration(
      color: c.surfaceStrong,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: c.border),
    );

    Widget tool(String kind, String name, Widget glyph) => Tooltip(
      message: name,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: name,
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey('md-$kind'),
          mouseCursor: WidgetStateMouseCursor.clickable,
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(8),
          onTap: () => _format(kind),
          child: Container(
            constraints: const BoxConstraints(minWidth: 36, minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: c.surfaceStrong,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            // As wide as the glyph needs, not the whole row.
            child: Center(widthFactor: 1, heightFactor: 1, child: glyph),
          ),
        ),
      ),
    );
    final glyph = TextStyle(fontSize: 15, color: c.ink);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Row(
            children: [
              Expanded(child: Text('Description', style: label)),
              if (!_editing)
                SizedBox(
                  height: 28,
                  child: OutlinedButton(
                    key: const ValueKey('desc-edit'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), visualDensity: VisualDensity.compact),
                    onPressed: _edit,
                    child: const Text('Edit', style: TextStyle(fontSize: 12)),
                  ),
                ),
            ],
          ),
        ),
        if (_editing)
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            // Only listens: it adds nothing for a screen reader, so the box keeps its own place.
            includeSemantics: false,
            onFocusChange: _focusChanged,
            child: TextFieldTapRegion(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    container: true,
                    label: 'Formatting',
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        tool('bold', 'Bold', Text('B', style: glyph.copyWith(fontWeight: FontWeight.w800))),
                        tool('italic', 'Italic', Text('I', style: glyph.copyWith(fontStyle: FontStyle.italic))),
                        tool('underline', 'Underline', Text('U', style: glyph.copyWith(decoration: TextDecoration.underline))),
                        tool('strike', 'Strikethrough', Text('S', style: glyph.copyWith(decoration: TextDecoration.lineThrough))),
                        tool('code', 'Code', AppIcon('code', size: 16, color: c.ink)),
                        tool('link', 'Link', AppIcon('link', size: 16, color: c.ink)),
                        tool('list', 'List', AppIcon('list', size: 16, color: c.ink)),
                        tool('spoiler', 'Spoiler', AppIcon('eye-off', size: 16, color: c.ink)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  CallbackShortcuts(
                    // Ctrl (⌘ on a Mac) with B, I or U, as in any editor.
                    bindings: {
                      for (final (key, kind) in [(LogicalKeyboardKey.keyB, 'bold'), (LogicalKeyboardKey.keyI, 'italic'), (LogicalKeyboardKey.keyU, 'underline')]) ...{
                        SingleActivator(key, control: true): () => _format(kind),
                        SingleActivator(key, meta: true): () => _format(kind),
                      },
                    },
                    child: TextField(
                    key: const ValueKey('card-desc-field'),
                    controller: widget.controller,
                    focusNode: _focus,
                    minLines: 3,
                    maxLines: 10,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Add a description…'),
                  ),
                  ),
                  // A reminder for the eye; a screen reader has the toolbar's named buttons, and
                  // the box keeps its own name.
                  ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '**bold** *italic* __underline__ ~~strike~~ `code` ||spoiler|| # heading > quote - list',
                        style: TextStyle(fontSize: 11.5, color: c.muted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          // A press on the formatted text edits it, unless it was on a link or a spoiler.
          GestureDetector(
            key: const ValueKey('card-desc-view'),
            behavior: HitTestBehavior.opaque,
            onTap: _edit,
            child: MouseRegion(
              cursor: SystemMouseCursors.text,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: box,
                child: MarkdownView(widget.controller.text),
              ),
            ),
          ),
      ],
    );
  }
}
