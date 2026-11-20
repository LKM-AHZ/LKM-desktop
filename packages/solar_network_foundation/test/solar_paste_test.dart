import 'package:island_editor/island_editor.dart'
    show IslandClipboard, IslandClipboardData;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart';

/// A paste command with no host hook — the plain markdown text path.
final _pasteCommand = buildSolarPasteCommand();

/// Copies markdown to the (mocked) clipboard, then fires the Solar paste
/// shortcut through the real editor state.
Future<void> _paste(WidgetTester tester, EditorState state, String markdown) async {
  IslandClipboard.mockSetData(
    IslandClipboardData(text: markdown, html: null),
  );
  addTearDown(() => IslandClipboard.mockSetData(null));
  // The command resolves the clipboard asynchronously; pump until the
  // document settles.
  await _pasteCommand.handler(state);
  await tester.pumpAndSettle();
}

List<String> _types(EditorState state) =>
    state.document.root.children.map((n) => n.type).toList();

void main() {
  late EditorState state;

  setUp(() {
    // A blank editor starts with a single empty paragraph, like the real
    // composer; parsing '' would give zero nodes to select into.
    state = EditorState.blank(withInitialText: true);
  });

  tearDown(() => state.dispose());

  testWidgets('pasted markdown keeps its block structure', (tester) async {
    state.selection = Selection.collapsed(
      Position(path: state.document.root.children.first.path, offset: 0),
    );

    await _paste(tester, state, '# Title\n\nhello **bold** world\n\n- one\n- two');

    // The heading, paragraph and both list items all survive as their real
    // block types instead of becoming literal `#`/`-` text.
    expect(_types(state), ['heading', 'paragraph', 'bulleted_list', 'bulleted_list']);
    final heading = state.document.root.children.first;
    expect(heading.delta!.toPlainText(), 'Title');
    final paragraph = state.document.root.children.elementAt(1);
    final boldRun = paragraph.delta!
        .toList()
        .firstWhere((op) => op.attributes?['bold'] == true);
    expect(boldRun.data, 'bold');
  });

  testWidgets('pasted Solar syntaxes are annotated, not literal', (tester) async {
    state.selection = Selection.collapsed(
      Position(path: state.document.root.children.first.path, offset: 0),
    );

    await _paste(tester, state, 'hi @alice and :fire+red: here');

    final ops = state.document.root.children.first.delta!.toList();
    expect(
      ops.any((op) => op.attributes?.containsKey(SolarInlineKeys.mention) == true),
      isTrue,
    );
    expect(
      ops.any((op) => op.attributes?.containsKey(SolarInlineKeys.sticker) == true),
      isTrue,
    );
  });

  testWidgets('a single plain line pastes inline at the caret', (tester) async {
    state.document.root.children.first.updateAttributes({
      'delta': (Delta()..insert('start ')).toJson(),
    });
    state.selection = Selection.collapsed(
      Position(path: state.document.root.children.first.path, offset: 6),
    );

    await _paste(tester, state, 'pasted');

    // No extra block: the single line joined the existing paragraph.
    expect(_types(state), ['paragraph']);
    expect(state.document.root.children.first.delta!.toPlainText(),
        'start pasted');
  });

  testWidgets('empty clipboard leaves the document untouched', (tester) async {
    state.document.root.children.first.updateAttributes({
      'delta': (Delta()..insert('keep me')).toJson(),
    });
    state.selection = Selection.collapsed(
      Position(path: state.document.root.children.first.path, offset: 7),
    );

    await _paste(tester, state, '');

    expect(state.document.root.children.first.delta!.toPlainText(), 'keep me');
  });

  testWidgets('a markdown insertion from the text-input channel is parsed', (
    tester,
  ) async {
    // Mobile keyboards and some IMEs deliver a paste through the text input
    // channel rather than Cmd+V; the interceptor must parse it the same way.
    state.selection = Selection.collapsed(
      Position(path: state.document.root.children.first.path, offset: 0),
    );

    final handled = await SolarMarkdownPasteInterceptor().interceptInsert(
      TextEditingDeltaInsertion(
        oldText: '',
        textInserted: '# Title\n\nhello **bold**',
        selection: const TextSelection.collapsed(offset: 21),
        composing: TextRange.empty,
        insertionOffset: 0,
      ),
      state,
      const [],
    );

    expect(handled, isTrue);
    await tester.pumpAndSettle();
    expect(_types(state), ['heading', 'paragraph']);
    final boldRun = state.document.root.children
        .elementAt(1)
        .delta!
        .toList()
        .firstWhere((op) => op.attributes?['bold'] == true);
    expect(boldRun.data, 'bold');
  });

  testWidgets('ordinary typing is never intercepted', (tester) async {
    state.selection = Selection.collapsed(
      Position(path: state.document.root.children.first.path, offset: 0),
    );

    final handled = await SolarMarkdownPasteInterceptor().interceptInsert(
      TextEditingDeltaInsertion(
        oldText: '',
        textInserted: 'h',
        selection: const TextSelection.collapsed(offset: 1),
        composing: TextRange.empty,
        insertionOffset: 0,
      ),
      state,
      const [],
    );

    expect(handled, isFalse);
    await tester.pumpAndSettle();
  });


  testWidgets('a consuming host hook skips the markdown text path', (
    tester,
  ) async {
    state.selection = Selection.collapsed(
      Position(path: state.document.root.children.first.path, offset: 0),
    );
    IslandClipboard.mockSetData(
      const IslandClipboardData(text: '# markdown', html: null),
    );
    addTearDown(() => IslandClipboard.mockSetData(null));

    var hookCalls = 0;
    final command = buildSolarPasteCommand(
      onPaste: () async {
        hookCalls++;
        return true;
      },
    );
    expect(await command.handler(state), KeyEventResult.handled);
    await tester.pumpAndSettle();

    // The hook ran; the markdown never reached the document.
    expect(hookCalls, 1);
    expect(_types(state), ['paragraph']);
  });

  testWidgets('a declining host hook falls through to markdown', (
    tester,
  ) async {
    state.selection = Selection.collapsed(
      Position(path: state.document.root.children.first.path, offset: 0),
    );
    IslandClipboard.mockSetData(
      const IslandClipboardData(text: '# Title', html: null),
    );
    addTearDown(() => IslandClipboard.mockSetData(null));

    final command = buildSolarPasteCommand(onPaste: () async => false);
    expect(await command.handler(state), KeyEventResult.handled);
    await tester.pumpAndSettle();

    // The parsed trailing paragraph merges into the pre-existing blank
    // paragraph, so a lone heading is the expected result.
    expect(_types(state), ['heading']);
    expect(
      state.document.root.children.first.delta!.toPlainText(),
      'Title',
    );
  });
}
