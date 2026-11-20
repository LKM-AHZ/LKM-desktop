import 'package:island_editor/island_editor.dart';
import 'package:flutter/material.dart';

final List<CommandShortcutEvent> toggleMarkdownCommands = [
  toggleBoldCommand,
  toggleItalicCommand,
  toggleUnderlineCommand,
  toggleStrikethroughCommand,
  toggleCodeCommand,
];

/// Markdown key event.
///
/// Cmd / Ctrl + B: toggle bold
/// Cmd / Ctrl + I: toggle italic
/// Cmd / Ctrl + U: toggle underline
/// Cmd / Ctrl + Shift + S: toggle strikethrough
/// Cmd / Ctrl + E: code
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent toggleBoldCommand = CommandShortcutEvent(
  key: 'toggle bold',
  getDescription: () => IslandEditorL10n.current.cmdToggleBold,
  command: 'ctrl+b',
  macOSCommand: 'cmd+b',
  handler: (editorState) => _toggleAttribute(
    editorState,
    IslandRichTextKeys.bold,
  ),
);

final CommandShortcutEvent toggleItalicCommand = CommandShortcutEvent(
  key: 'toggle italic',
  getDescription: () => IslandEditorL10n.current.cmdToggleItalic,
  command: 'ctrl+i',
  macOSCommand: 'cmd+i',
  handler: (editorState) => _toggleAttribute(
    editorState,
    IslandRichTextKeys.italic,
  ),
);

final CommandShortcutEvent toggleUnderlineCommand = CommandShortcutEvent(
  key: 'toggle underline',
  getDescription: () => IslandEditorL10n.current.cmdToggleUnderline,
  command: 'ctrl+u',
  macOSCommand: 'cmd+u',
  handler: (editorState) => _toggleAttribute(
    editorState,
    IslandRichTextKeys.underline,
  ),
);

final CommandShortcutEvent toggleStrikethroughCommand = CommandShortcutEvent(
  key: 'toggle strikethrough',
  getDescription: () => IslandEditorL10n.current.cmdToggleStrikethrough,
  command: 'ctrl+shift+s',
  macOSCommand: 'cmd+shift+s',
  handler: (editorState) => _toggleAttribute(
    editorState,
    IslandRichTextKeys.strikethrough,
  ),
);

final CommandShortcutEvent toggleCodeCommand = CommandShortcutEvent(
  key: 'toggle code',
  getDescription: () => IslandEditorL10n.current.cmdToggleCode,
  command: 'ctrl+e',
  macOSCommand: 'cmd+e',
  handler: (editorState) => _toggleAttribute(
    editorState,
    IslandRichTextKeys.code,
  ),
);

KeyEventResult _toggleAttribute(
  EditorState editorState,
  String key,
) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }

  editorState.toggleAttribute(key);

  return KeyEventResult.handled;
}
