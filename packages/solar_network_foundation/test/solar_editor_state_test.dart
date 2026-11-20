import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island_editor/island_editor.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart';

/// The editor keeps a caret blink timer alive, so [WidgetTester.pumpAndSettle]
/// never returns; pump a bounded number of frames instead.
Future<void> _frames(WidgetTester tester, {int count = 6}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> _pumpEditor(
  WidgetTester tester,
  SolarEditorController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: SolarBlockEditor(controller: controller),
          ),
        ),
      ),
    ),
  );
  await _frames(tester);
}

/// The text the editor is actually painting (what the user sees).
String _paintedText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((richText) => richText.text.toPlainText())
    .join('|');

/// The text stored in the document (what edit operations act on).
String _documentText(SolarEditorController controller) => controller
    .editorState
    .document
    .root
    .children
    .map((node) => node.delta?.toPlainText() ?? '')
    .join('|');

/// Taps the editor surface. [RichText] is not hit-testable on its own, so the
/// tap goes through the editor's render box instead.
Offset _editorCenter(WidgetTester tester) =>
    tester.getCenter(find.byType(SolarBlockEditor));

/// Runs [body] with [platform] as the reported target platform. Unwound inside
/// the body because flutter_test asserts every debug variable is clear when the
/// test returns.
Future<void> _onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  group('controller document ownership', () {
    testWidgets('setMarkdown re-renders the live editor', (tester) async {
      final controller = SolarEditorController(initialMarkdown: 'original');
      addTearDown(controller.dispose);
      await _pumpEditor(tester, controller);

      // Draft restore / placeholder insertion / import all land here.
      controller.setMarkdown('restored **draft** body');
      await _frames(tester);

      // Rebuilding the EditorState used to leave the widget tree pointing at
      // the disposed one, so the editor kept painting the previous document
      // and looked empty after opening an existing post.
      expect(_paintedText(tester), contains('restored'));
      expect(_documentText(controller), contains('restored'));
      expect(controller.markdown, contains('**draft**'));
    });

    testWidgets('setMarkdown is editable afterwards', (tester) async {
      final controller = SolarEditorController(initialMarkdown: 'original');
      addTearDown(controller.dispose);
      await _pumpEditor(tester, controller);

      controller.setMarkdown('imported body');
      await _frames(tester);

      controller.editorState.updateSelectionWithReason(
        Selection.collapsed(Position(path: [0], offset: 0)),
        reason: SelectionUpdateReason.uiEvent,
      );
      await _frames(tester);
      controller.insertText('X');
      await _frames(tester);

      expect(_documentText(controller), startsWith('X'));
      expect(controller.markdown, startsWith('X'));
    });

    testWidgets('setMarkdown clears undo history', (tester) async {
      final controller = SolarEditorController(initialMarkdown: 'original');
      addTearDown(controller.dispose);
      await _pumpEditor(tester, controller);

      controller.insertText('typed');
      await _frames(tester);
      controller.setMarkdown('imported body');
      await _frames(tester);

      // An import is not an editing step: undoing it would resurrect the
      // previous document.
      expect(controller.editorState.undoManager.undoStack.isEmpty, isTrue);
    });

    testWidgets('setMarkdown with empty markdown keeps one paragraph', (
      tester,
    ) async {
      final controller = SolarEditorController(initialMarkdown: 'body');
      addTearDown(controller.dispose);
      await _pumpEditor(tester, controller);

      controller.setMarkdown('');
      await _frames(tester);

      // An empty document would leave nothing to focus, so the composer could
      // never be typed into again.
      expect(controller.editorState.document.root.children, isNotEmpty);
      expect(controller.isEmpty, isTrue);
    });
  });

  group('IME composition', () {
    testWidgets('dictation keeps text inside the composing range', (
      tester,
    ) async {
      final controller = SolarEditorController(initialMarkdown: '');
      addTearDown(controller.dispose);

      await _onPlatform(TargetPlatform.iOS, () async {
        await _pumpEditor(tester, controller);
        await tester.tapAt(_editorCenter(tester));
        await _frames(tester);

        // iOS dictation re-sends the whole utterance on every update with the
        // composing range covering it. Solar markers inside the text used to
        // be normalized mid-composition, which rewrote the text under the IME
        // and made the next delta land at the wrong offset — the utterance
        // disappeared and only reappeared after one more keystroke.
        const utterance = 'it is ==great== to be here @alice';
        final input = tester.testTextInput;
        for (var i = 1; i <= utterance.length; i++) {
          final text = utterance.substring(0, i);
          input.updateEditingValue(
            TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length),
              composing: TextRange(start: 0, end: text.length),
            ),
          );
          await _frames(tester, count: 2);
        }

        expect(_documentText(controller), utterance);
      });
    });

    testWidgets('markers are annotated once the IME commits', (tester) async {
      final controller = SolarEditorController(initialMarkdown: '');
      addTearDown(controller.dispose);

      await _onPlatform(TargetPlatform.iOS, () async {
        await _pumpEditor(tester, controller);
        await tester.tapAt(_editorCenter(tester));
        await _frames(tester);

        const utterance = 'it is ==great== to be here';
        final input = tester.testTextInput;
        input.updateEditingValue(
          const TextEditingValue(
            text: utterance,
            selection: TextSelection.collapsed(offset: 24),
            composing: TextRange(start: 0, end: 24),
          ),
        );
        await _frames(tester);

        // Commit: the IME hands the text over with an empty composing range.
        input.updateEditingValue(
          const TextEditingValue(
            text: utterance,
            selection: TextSelection.collapsed(offset: 24),
            composing: TextRange.empty,
          ),
        );
        await _frames(tester);

        // Still plain on screen (the markers show as annotated style), and
        // the markdown keeps them.
        expect(_documentText(controller), 'it is great to be here');
        expect(controller.markdown, 'it is ==great== to be here');
      });
    });

    testWidgets(
      'rapid voice dictation clear-then-restore within debounce window does not wipe text',
      (tester) async {
        final controller = SolarEditorController(initialMarkdown: '');
        addTearDown(controller.dispose);

        await _onPlatform(TargetPlatform.iOS, () async {
          await _pumpEditor(tester, controller);
          await tester.tapAt(_editorCenter(tester));
          await _frames(tester);

          const utterance = 'hello from voice input';
          final input = tester.testTextInput;

          // Voice dictation inserts the utterance and settles.
          input.updateEditingValue(
            const TextEditingValue(
              text: ' $utterance',
              selection: TextSelection.collapsed(offset: utterance.length + 1),
              composing: TextRange.empty,
            ),
          );
          await _frames(tester);
          expect(_documentText(controller), utterance);

          // Simulate rapid mobile voice IME jitter: transient clear followed
          // within <10ms by the same committed text. Previously the second
          // update returned early without cancelling the debounce timer, so the
          // stale deletion fired 10ms later and wiped the text until the next
          // character was typed.
          input.updateEditingValue(
            const TextEditingValue(
              text: ' ',
              selection: TextSelection.collapsed(offset: 1),
              composing: TextRange.empty,
            ),
          );
          await tester.pump(const Duration(milliseconds: 3));
          input.updateEditingValue(
            const TextEditingValue(
              text: ' $utterance',
              selection: TextSelection.collapsed(offset: utterance.length + 1),
              composing: TextRange.empty,
            ),
          );
          await _frames(tester);

          expect(_documentText(controller), utterance);
          expect(_paintedText(tester), contains(utterance));
        });
      },
    );
  });

  group('decoder never drops content', () {
    test('a fenced code block survives the round-trip', () {
      // The decoder has no code-block parser; before the fallback this
      // returned an empty document and the code was lost on the next save.
      const src = '```ts\nconst a = 1;\n```';
      final document = solarMarkdownToDocument(src);
      expect(document.root.children, isNotEmpty);
      expect(solarDocumentToMarkdown(document), contains('const a = 1;'));
    });

    test('text around a dropped block is kept', () {
      const src = 'intro\n\n```ts\nconst a = 1;\n```\n\nafter';
      final out = solarDocumentToMarkdown(solarMarkdownToDocument(src));
      expect(out, contains('intro'));
      expect(out, contains('after'));
      expect(out, contains('const a = 1;'));
    });

    test('raw HTML is kept as text', () {
      const src = '<div align="center">\n<img src="x" />\n</div>';
      final out = solarDocumentToMarkdown(solarMarkdownToDocument(src));
      expect(out, contains('<div align="center">'));
    });

    test('indented blocks are kept as text', () {
      const src = '    indented text';
      final out = solarDocumentToMarkdown(solarMarkdownToDocument(src));
      expect(out, contains('indented text'));
    });
  });
}
