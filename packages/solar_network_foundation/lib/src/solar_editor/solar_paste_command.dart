import 'dart:async';

import 'package:island_editor/island_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'solar_markdown_codec.dart';

/// Paste that understands markdown.
///
/// Island Editor's own `pasteCommand` falls back to `pastePlainText`, which splits
/// the clipboard on newlines and emits one plain paragraph per line — so
/// `# Heading`, `**bold**`, `- item` and fenced code all arrive as literal
/// characters. This command parses the clipboard with
/// [solarMarkdownToDocument] instead, so pasted markdown keeps its block
/// types, inline styles and Solar syntaxes, then inserts the resulting nodes
/// at the caret.
///
/// [onPaste] runs first and is the host's seam for clipboard payloads the
/// text path cannot represent — images and files. The host reads the platform
/// clipboard itself (the app already ships `pasteboard`), uploads what it
/// found and returns `true`; the text path is then skipped. Returning `false`
/// (no image, no file) pastes the clipboard text as markdown.
///
/// A single-line clipboard that parses to one plain paragraph is still
/// inserted inline (no block split), matching what pasting "hello" should do.
CommandShortcutEvent buildSolarPasteCommand({
  Future<bool> Function()? onPaste,
}) {
  return CommandShortcutEvent(
    key: 'solar paste markdown',
    getDescription: () => IslandEditorL10n.current.cmdPasteContent,
    command: 'ctrl+v',
    macOSCommand: 'cmd+v',
    handler: (editorState) => _solarPasteHandler(editorState, onPaste),
  );
}

KeyEventResult _solarPasteHandler(
  EditorState editorState,
  Future<bool> Function()? onPaste,
) {
  if (editorState.selection == null) {
    return KeyEventResult.ignored;
  }

  unawaited(() async {
    if (onPaste != null && await onPaste()) return;
    // Only the text flavour is read: IslandClipboard.getData hardcodes
    // `html: null`, so an HTML branch here would never run.
    final text = (await IslandClipboard.getData()).text;
    if (text != null && text.isNotEmpty) {
      await _pasteMarkdown(editorState, text);
    }
  }());

  return KeyEventResult.handled;
}

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

/// Inserts parsed [nodes] at the caret, reusing Island Editor's paste helpers so
/// the caret, selection and undo history behave exactly like a normal paste.
///
/// A single node only pastes inline when it is a plain paragraph (or when the
/// caret sits in an empty paragraph, which Island Editor replaces outright).
/// Island Editor's `pasteSingleLineNode` flattens everything else to plain text, so
/// pasting a lone `# Heading`, divider or image into a paragraph would drop
/// the block type; those are inserted as their own block instead.
Future<void> _insertNodes(EditorState editorState, List<Node> nodes) async {
  if (nodes.length != 1) {
    await editorState.pasteMultiLineNodes(nodes);
    return;
  }

  final node = nodes.first;
  final selection = editorState.selection;
  final current = selection == null
      ? null
      : editorState.getNodeAtPath(selection.end.path);
  final isEmptyParagraph =
      current != null &&
      current.type == ParagraphBlockKeys.type &&
      (current.delta?.isEmpty ?? true);
  if (node.type == ParagraphBlockKeys.type || isEmptyParagraph) {
    await editorState.pasteSingleLineNode(node);
    return;
  }

  final insertPath =
      current?.path.next ?? editorState.document.root.children.lastOrNull?.path.next ?? [0];
  final transaction = editorState.transaction
    ..insertNode(insertPath, node)
    ..afterSelection = Selection.collapsed(
      Position(path: [...insertPath, 0], offset: 0),
    );
  await editorState.apply(transaction);
}

/// Catches pastes that arrive through the platform text-input channel
/// instead of the Cmd/Ctrl+V shortcut — mobile keyboards and some IMEs
/// deliver the clipboard as one insertion, which would otherwise insert the
/// markdown literally.
///
/// Only insertions with block-level markdown syntax are intercepted;
/// ordinary typing (including a pasted single word) stays on the fast
/// built-in path.
class SolarMarkdownPasteInterceptor extends IslandKeyboardServiceInterceptor {
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
    if (!_blockSyntax.hasMatch(text)) return false;

    await _pasteMarkdown(editorState, text);
    return true;
  }
}
