/// The Solar Network editor, built on [appflowy_editor].
///
/// This module owns everything editor-related so every Solar Network client
/// (Solian, SolWatt, …) renders and serializes the same way:
///
/// - [solarDocumentToMarkdown] / [solarMarkdownToDocument]: the markdown
///   bridge, including Solar's own inline syntaxes (`@mention`,
///   `==highlight==`, `=!spoiler!=`, `:sticker:`).
/// - [SolarBlockEditor]: the configured editor widget (standard blocks,
///   Solar text styles, `/` menu, floating toolbar).
/// - [SolarEditorConfig]: the extension point for host-specific custom
///   blocks, slash-menu items, the image-insert handler and the trigger
///   character.
library;

// Re-exported so hosts can register the editor's localization delegate.
export 'package:appflowy_editor/appflowy_editor.dart'
    show
        AppFlowyEditorLocalizations,
        Delta,
        Document,
        EditorState,
        Node,
        Position,
        Selection;

export 'solar_block_editor.dart';
export 'solar_paste_command.dart';
export 'solar_markdown_codec.dart';
export 'blocks/solar_highlight_spoiler_syntaxes.dart';
