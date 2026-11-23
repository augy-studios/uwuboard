// A card's description: shown formatted (as Discord formats a message), edited as text with a
// toolbar, formatted again on leaving the box; and its first lines on the card on the board.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwuboard/features/card/description_field.dart';
import 'package:uwuboard/theme/theme.dart';
import 'package:uwuboard/widgets/markdown_view.dart';

void main() {
  Future<TextEditingController> pump(WidgetTester tester, String text) async {
    final controller = TextEditingController(text: text);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(look: lookUwuApps, brightness: Brightness.light, brand: colorThemes.first.color),
        home: Scaffold(
          body: Column(
            children: [
              DescriptionField(controller: controller),
              const TextField(key: ValueKey('other')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  // Every word on screen, formatted or not.
  String shown(WidgetTester tester) =>
      tester.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText(includeSemanticsLabels: false)).join('\n');

  testWidgets('a description is shown formatted, and edited as text', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = await pump(tester, '# Plan\nShip it **this week**\n- one\n||secret||');
    expect(find.byKey(const ValueKey('card-desc-field')), findsNothing);
    expect(shown(tester), contains('Plan'));
    expect(shown(tester), contains('Ship it this week'));
    expect(shown(tester), isNot(contains('**')));
    // The spoiler is hidden from a screen reader too: it hears that it's a spoiler.
    final tree = tester.getSemantics(find.byKey(const ValueKey('card-desc-view'))).toStringDeep();
    expect(tree, contains('Spoiler, press to show'));
    expect(tree, isNot(contains('secret')));
    semantics.dispose();

    await tester.tap(find.byKey(const ValueKey('desc-edit')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('card-desc-field'));
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

    // The toolbar wraps the selection and keeps the box in focus.
    controller.selection = const TextSelection(baseOffset: 7, extentOffset: 14);
    await tester.tap(find.byKey(const ValueKey('md-italic')));
    await tester.pumpAndSettle();
    expect(controller.text, startsWith('# Plan\n*Ship it* **this week**'));
    expect(find.byKey(const ValueKey('card-desc-field')), findsOneWidget);

    // Leaving the box shows it formatted again.
    await tester.tap(find.byKey(const ValueKey('other')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('card-desc-field')), findsNothing);
    expect(find.byKey(const ValueKey('card-desc-view')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty description is the text box straight away, and stays one', (tester) async {
    await pump(tester, '');
    expect(find.byKey(const ValueKey('card-desc-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('desc-edit')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('other')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('card-desc-field')), findsOneWidget);
  });

  testWidgets('on the board, two lines at most, spoilers hidden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(look: lookUwuApps, brightness: Brightness.light, brand: colorThemes.first.color),
        home: const Scaffold(body: MarkdownSnippet('# Title\n- one ||two||\n- three')),
      ),
    );
    final text = tester.widget<RichText>(find.byType(RichText)).text;
    expect(text.toPlainText(includeSemanticsLabels: false), 'Title\n• one two');
    // A screen reader hears that it's a spoiler, not what it hides.
    expect(text.toPlainText(), 'Title\n• one spoiler');
    expect(tester.widget<RichText>(find.byType(RichText)).maxLines, 2);
    expect(snippetPlain('# Title\n- one ||two||'), 'Title • one (spoiler)');
  });
}
