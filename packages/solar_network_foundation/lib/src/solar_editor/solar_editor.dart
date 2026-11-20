/// The Solar Network editor, built on [island_editor].
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
/// - [Document] ⇄ mail HTML through [solarHTMLToDocument] /
///   [solarDocumentToHTML]: `<br>` kept as a soft break, lists, quotes,
///   headings and inline code round-tripped, `<pre>` kept as text.
library;

// Re-exported so hosts can register the editor's localization delegate.
export 'package:island_editor/island_editor.dart'
    show
        IslandEditorLocalizations,
        Delta,
        Document,
        EditorState,
        Node,
        Position,
        Selection;

export 'solar_block_editor.dart';
export 'solar_context_menu.dart';
export 'solar_paste_command.dart';
export 'solar_html_codec.dart';
export 'solar_markdown_codec.dart';
export 'blocks/solar_highlight_spoiler_syntaxes.dart';
