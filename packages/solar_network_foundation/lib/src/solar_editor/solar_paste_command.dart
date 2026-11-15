import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'solar_markdown_codec.dart';

/// Paste that understands markdown.
///
/// AppFlowy's own `pasteCommand` falls back to `pastePlainText`, which splits
/// the clipboard on newlines and emits one plain paragraph per line — so
/// `# Heading`, `**bold**`, `- item` and fenced code all arrive as literal
/// characters. This command parses the clipboard with
/// [solarMarkdownToDocument] instead, so pasted markdown keeps its block
/// types, inline styles and Solar syntaxes, then inserts the resulting nodes
/// at the caret.
///
/// A single-line clipboard that parses to one plain paragraph is still
/// inserted inline (no block split), matching what pasting "hello" should do.
final CommandShortcutEvent solarPasteCommand = CommandShortcutEvent(
  key: 'solar paste markdown',
  getDescription: () => AppFlowyEditorL10n.current.cmdPasteContent,
  command: 'ctrl+v',
  macOSCommand: 'cmd+v',
  handler: _solarPasteHandler,
);

CommandShortcutEventHandler _solarPasteHandler = (editorState) {
  if (editorState.selection == null) {
    return KeyEventResult.ignored;
  }

  () async {
    // Only the text flavour is read: AppFlowyClipboard.getData hardcodes
    // `html: null`, so an HTML branch here would never run.
    final text = (await AppFlowyClipboard.getData()).text;
    if (text != null && text.isNotEmpty) {
      await _pasteMarkdown(editorState, text);
    }
  }();

  return KeyEventResult.handled;
};

/// Parses [markdown] into editor nodes and inserts them at the caret.
Future<void> _pasteMarkdown(EditorState editorState, String markdown) async {
  final nodes = _trimEmptyEdges(solarMarkdownToDocument(markdown).root.children);
  if (nodes.isEmpty) return;
  await _insertNodes(editorState, nodes);
}

/// Drops the leading and trailing blank lines the decoders emit around
/// content, so pasting does not leave stray empty blocks behind.
List<Node> _trimEmptyEdges(Iterable<Node> children) {
  final nodes = children.toList();
  while (nodes.isNotEmpty &&
      nodes.first.delta?.isEmpty == true &&
      nodes.first.children.isEmpty) {
    nodes.removeAt(0);
  }
  while (nodes.isNotEmpty &&
      nodes.last.delta?.isEmpty == true &&
      nodes.last.children.isEmpty) {
    nodes.removeLast();
  }
  return nodes;
}

/// Inserts parsed [nodes] at the caret, reusing AppFlowy's paste helpers so
/// the caret, selection and undo history behave exactly like a normal paste.
Future<void> _insertNodes(EditorState editorState, List<Node> nodes) async {
  if (nodes.length == 1) {
    await editorState.pasteSingleLineNode(nodes.first);
  } else {
    await editorState.pasteMultiLineNodes(nodes);
  }
}

/// Catches pastes that arrive through the platform text-input channel
/// instead of the Cmd/Ctrl+V shortcut — mobile keyboards and some IMEs
/// deliver the clipboard as one insertion, which would otherwise insert the
/// markdown literally.
///
/// Only multi-line insertions with block-level markdown syntax are
/// intercepted; ordinary typing (including a pasted single word) stays on
/// the fast built-in path.
class SolarMarkdownPasteInterceptor extends AppFlowyKeyboardServiceInterceptor {
  SolarMarkdownPasteInterceptor();

  static final _blockSyntax = RegExp(
    r'^(#{1,6}\s|[-*+]\s|\d+[.)]\s|>\s|```|\|.*\|)',
    multiLine: true,
  );

  @override
  Future<bool> interceptInsert(
    TextEditingDeltaInsertion insertion,
    EditorState editorState,
    List<CharacterShortcutEvent> characterShortcutEvents,
  ) async {
    final text = insertion.textInserted;
    if (!text.contains('\n') && !_blockSyntax.hasMatch(text)) return false;
    if (!_blockSyntax.hasMatch(text)) return false;

    await _pasteMarkdown(editorState, text);
    return true;
  }
}
