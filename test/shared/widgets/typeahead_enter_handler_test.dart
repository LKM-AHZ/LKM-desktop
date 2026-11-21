import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:island/shared/widgets/typeahead_enter_handler.dart';

void main() {
  testWidgets('Enter confirms IME composition before submitting text', (
    tester,
  ) async {
    final controller = TextEditingController();
    final suggestions = SuggestionsController<String>();
    var submissions = 0;
    addTearDown(controller.dispose);
    addTearDown(suggestions.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TypeAheadEnterHandler<String>(
            controller: controller,
            suggestionsController: suggestions,
            onEnter: () => submissions++,
            child: TextField(controller: controller, maxLines: null),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    controller.value = const TextEditingValue(
      text: 'ni',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(submissions, 0);

    controller.value = const TextEditingValue(
      text: '你',
      selection: TextSelection.collapsed(offset: 1),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(submissions, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    expect(submissions, 2);
  });

  testWidgets('Enter selects a highlighted suggestion before submitting', (
    tester,
  ) async {
    final controller = TextEditingController(text: '@ni');
    final suggestions = SuggestionsController<String>();
    var submissions = 0;
    String? selected;
    addTearDown(controller.dispose);
    addTearDown(suggestions.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TypeAheadEnterHandler<String>(
            controller: controller,
            suggestionsController: suggestions,
            onEnter: () => submissions++,
            child: TextField(controller: controller),
          ),
        ),
      ),
    );
    final subscription = suggestions.selections.listen((value) {
      selected = value;
    });
    addTearDown(subscription.cancel);
    await tester.tap(find.byType(TextField));
    suggestions.suggestions = ['Nia'];
    suggestions.open();
    suggestions.highlighted = 0;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, 'Nia');
    expect(submissions, 0);
  });
}
