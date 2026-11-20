library;

import 'dart:convert';

import 'package:island_editor/island_editor.dart';
import 'package:markdown/markdown.dart' as md;

/// Converts a markdown to [Document].
///
/// [customParsers] is a list of custom parsers that will be used to parse the markdown.
Document markdownToDocument(
  String markdown, {
  List<CustomMarkdownParser> markdownParsers = const [],
  List<md.InlineSyntax> inlineSyntaxes = const [],
}) {
  return IslandEditorMarkdownCodec(
    markdownInlineSyntaxes: inlineSyntaxes,
    markdownParsers: [
      ...markdownParsers,
      const MarkdownParagraphParserV2(),
      const MarkdownHeadingParserV2(),
      const MarkdownTodoListParserV2(),
      const MarkdownUnorderedListParserV2(),
      const MarkdownOrderedListParserV2(),
      const MarkdownUnorderedListItemParserV2(),
      const MarkdownOrderedListItemParserV2(),
      const MarkdownBlockQuoteParserV2(),
      const MarkdownTableListParserV2(),
      const MarkdownDividerParserV2(),
      const MarkdownImageParserV2(),
      // Keeps markdown no other parser understands (code fences, HTML,
      // indented blocks) instead of silently dropping it.
      const MarkdownFallbackParserV2(),
    ],
  ).decode(markdown);
}

/// Converts a [Document] to markdown.
///
/// [customParsers] is a list of custom parsers that will be used to parse the markdown.
String documentToMarkdown(
  Document document, {
  List<NodeParser> customParsers = const [],
  String lineBreak = '',
}) {
  return IslandEditorMarkdownCodec(
    encodeParsers: [
      ...customParsers,
      const TextNodeParser(),
      const BulletedListNodeParser(),
      const NumberedListNodeParser(),
      const TodoListNodeParser(),
      const QuoteNodeParser(),
      const CodeBlockNodeParser(),
      const HeadingNodeParser(),
      const ImageNodeParser(),
      const TableNodeParser(),
      const DividerNodeParser(),
    ],
    lineBreak: lineBreak,
  ).encode(document);
}

class IslandEditorMarkdownCodec extends Codec<Document, String> {
  const IslandEditorMarkdownCodec({
    this.markdownInlineSyntaxes = const [],
    this.markdownParsers = const [],
    this.encodeParsers = const [],
    this.lineBreak = '',
  });

  final List<NodeParser> encodeParsers;
  final List<CustomMarkdownParser> markdownParsers;
  final List<md.InlineSyntax> markdownInlineSyntaxes;
  final String lineBreak;

  @override
  Converter<String, Document> get decoder => DocumentMarkdownDecoder(
        markdownElementParsers: markdownParsers,
        inlineSyntaxes: markdownInlineSyntaxes,
      );

  @override
  Converter<Document, String> get encoder => DocumentMarkdownEncoder(
        parsers: encodeParsers,
        lineBreak: lineBreak,
      );
}
