import 'package:island_editor/island_editor.dart';
import 'package:markdown/markdown.dart' as md;

/// Last-resort parser: keeps markdown this codec has no block for.
///
/// The decoder stops at the first parser that returns nodes and quietly drops
/// everything else, so a post containing a fenced code block, an HTML wrapper
/// or an indented block loaded into the editor as *nothing* — the text was
/// still in the markdown, but the document (and every later save) had lost it.
///
/// This runs only after every real parser declined, and turns the element's
/// text into a paragraph so the content survives the round-trip. Formatting
/// this codec cannot represent degrades to plain text instead of vanishing.
class MarkdownFallbackParserV2 extends CustomMarkdownParser {
  const MarkdownFallbackParserV2();

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    // Recursively parsed children already handled by their own parser; only
    // the leftovers reach here.
    if (element is md.Text) {
      return _paragraphs(element.text);
    }
    if (element is! md.Element) {
      return [];
    }

    final children = element.children;
    if (children != null && children.isNotEmpty) {
      final parsed = parseElementChildren(
        children,
        parsers,
        listType: listType,
        startNumber: startNumber,
      );
      if (parsed.isNotEmpty) return parsed;
    }

    final text = element.textContent;
    if (text.trim().isEmpty) return [];
    return _paragraphs(text);
  }

  List<Node> _paragraphs(String text) {
    // Blank-line separated chunks become separate blocks, matching how the
    // decoder treats other block boundaries.
    return text
        .split(RegExp(r'\n\s*\n'))
        .map((chunk) => chunk.trimRight())
        .where((chunk) => chunk.trim().isNotEmpty)
        .map(
          (chunk) => paragraphNode(
            delta: DeltaMarkdownDecoder().convertNodes([
              ...md.Document(
                extensionSet: md.ExtensionSet.gitHubFlavored,
                encodeHtml: false,
              ).parseInline(chunk),
            ]),
          ),
        )
        .toList(growable: false);
  }
}
