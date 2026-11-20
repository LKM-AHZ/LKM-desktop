import 'package:island_editor/island_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Pumps a few frames without settling — the editor keeps a caret blink timer
/// alive, so [WidgetTester.pumpAndSettle] never returns.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps the editor on the current platform. Call inside [_onPlatform].
Future<void> _pumpEditor(
  WidgetTester tester,
  SolarEditorController controller,
) async {
  await tester.pumpWidget(
    _host(
      Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: SolarBlockEditor(controller: controller),
        ),
      ),
    ),
  );
  await _frames(tester);
}

/// Right-clicks the paragraph text.
Future<void> _rightClickText(WidgetTester tester) async {
  final target = tester.getCenter(find.byType(RichText).last);
  final gesture = await tester.startGesture(
    target,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await _frames(tester);
}

/// Selects the first five characters of the single paragraph.
void _selectRange(SolarEditorController controller) {
  controller.editorState.updateSelectionWithReason(
    Selection.single(path: [0], startOffset: 0, endOffset: 5),
    reason: SelectionUpdateReason.uiEvent,
  );
}

/// Runs [body] with [platform] reported as the target. The override is
/// unwound inside the body because flutter_test asserts every foundation debug
/// variable is unset by the time the test body returns.
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
  late SolarEditorController controller;

  setUp(() {
    IslandClipboard.lastText = null;
    controller = SolarEditorController(
      initialMarkdown: 'hello **world** and more text',
    );
  });

  tearDown(() {
    IslandClipboard.mockSetData(null);
    controller.dispose();
  });

  testWidgets('right-click opens a menu with the clipboard actions', (
    tester,
  ) async {
    await _onPlatform(TargetPlatform.macOS, () async {
      await _pumpEditor(tester, controller);
      _selectRange(controller);
      await _frames(tester);

      await _rightClickText(tester);

      // Before this change Island Editor rendered nothing at all: its context menu
      // only appears when the host supplies a builder.
      expect(find.text('Cut'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('select all'), findsOneWidget);
    });
  });

  testWidgets('copy from the menu puts the selection on the clipboard', (
    tester,
  ) async {
    await _onPlatform(TargetPlatform.macOS, () async {
      await _pumpEditor(tester, controller);
      _selectRange(controller);
      await _frames(tester);
      await _rightClickText(tester);

      await tester.tap(find.text('Copy'));
      await _frames(tester);

      // The editor wrote the selected text through its clipboard bridge.
      expect(IslandClipboard.lastText, contains('hello'));
    });
  });

  testWidgets('menu paste uses the markdown-aware command', (tester) async {
    IslandClipboard.mockSetData(
      const IslandClipboardData(text: '# Piped', html: null),
    );

    await _onPlatform(TargetPlatform.macOS, () async {
      await _pumpEditor(tester, controller);
      controller.editorState.updateSelectionWithReason(
        Selection.collapsed(Position(path: [0], offset: 0)),
        reason: SelectionUpdateReason.uiEvent,
      );
      await _frames(tester);
      await _rightClickText(tester);

      await tester.tap(find.text('Paste'));
      await _frames(tester);

      // Parsed as a heading, not pasted as the literal text "# Piped".
      expect(
        controller.editorState.document.root.children.any(
          (n) => n.type == 'heading',
        ),
        isTrue,
      );
    });
  });

  testWidgets('cut removes the selection', (tester) async {
    await _onPlatform(TargetPlatform.macOS, () async {
      await _pumpEditor(tester, controller);
      _selectRange(controller);
      await _frames(tester);
      await _rightClickText(tester);

      await tester.tap(find.text('Cut'));
      await _frames(tester);

      final text = controller.editorState.document.root.children.first.delta!
          .toPlainText();
      expect(text, isNot(startsWith('hello')));
    });
  });

  testWidgets('mobile selection shows the platform clipboard toolbar', (
    tester,
  ) async {
    final mobileController = SolarEditorController(
      initialMarkdown: 'hello **world** and more text',
    );

    await _onPlatform(TargetPlatform.iOS, () async {
      await _pumpEditor(tester, mobileController);
      _selectRange(mobileController);
      await _frames(tester);

      // The labels come from MaterialLocalizations, so finding them proves
      // Island Editor raised a toolbar for the selection — without the host's
      // toolbar builder it renders nothing on mobile.
      expect(find.text('Cut'), findsWidgets);
      expect(find.text('Copy'), findsWidgets);
    });
    mobileController.dispose();
  });
}
