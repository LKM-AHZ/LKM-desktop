/// Solar's own inline markdown syntaxes for the AppFlowy editor bridge.
///
/// These are the syntaxes Solian's renderer (`MarkdownTextContent`) already
/// supports; registering them with the editor's markdown codec keeps the
/// editor and the published post in agreement:
///
/// - `@user`, `@r/realm`, `@p/publisher` → `mention` attribute
/// - `==text==` → `highlight` attribute (rendered as background color)
/// - `=!text!=` → `spoiler` attribute
/// - `:pack+slug:` → `sticker` attribute
library;

import 'package:markdown/markdown.dart' as md;

/// Attribute keys used inside editor deltas for Solar-specific inline runs.
///
/// They flow through `textSpanDecoratorForCustomAttributes` for rendering
/// and through [solarMarkdownToDocument]/[solarDocumentToMarkdown] for the
/// markdown round-trip.
class SolarInlineKeys {
  SolarInlineKeys._();

  /// `@alias` — value: the alias without the `@` (`u/xxx`, `r/realm`, …).
  static const mention = 'solar_mention';

  /// `==text==` — value: always `true`.
  static const highlight = 'solar_highlight';

  /// `=!text!=` — value: always `true`.
  static const spoiler = 'solar_spoiler';

  /// `:pack+slug:` — value: the slug (`pack+slug`).
  static const sticker = 'solar_sticker';

  /// All Solar attribute keys.
  static const List<String> all = [
    mention,
    highlight,
    spoiler,
    sticker,
  ];
}

/// The `@mention` syntax. The match carries the alias (without `@`) and a
/// resolved type (`accounts` / `realms` / `publishers`) mirroring the
/// renderer's `mention-chip`.
class SolarMentionInlineSyntax extends md.InlineSyntax {
  SolarMentionInlineSyntax()
    : super(r'(^|[^A-Za-z0-9._%+\-/\[])(@[-A-Za-z0-9_./]+)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final prefix = match[1] ?? '';
    final alias = match[2]!;
    if (prefix.isNotEmpty) parser.addNode(md.Text(prefix));

    final parts = alias.substring(1).split('/');
    final type = switch (parts.length == 1 ? 'u' : parts.first) {
      'u' => 'accounts',
      'r' => 'realms',
      'p' => 'publishers',
      _ => '',
    };
    final element = md.Element('solar-mention', [md.Text(alias)])
      ..attributes['alias'] = alias.substring(1)
      ..attributes['type'] = type;
    parser.addNode(element);
    return true;
  }
}

/// The `==highlight==` syntax.
class SolarHighlightInlineSyntax extends md.InlineSyntax {
  SolarHighlightInlineSyntax() : super(r'==([^=]+)==');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element('solar-highlight', [md.Text(match[1]!)]),
    );
    return true;
  }
}

/// The `=!spoiler!=` syntax.
class SolarSpoilerInlineSyntax extends md.InlineSyntax {
  SolarSpoilerInlineSyntax() : super(r'=!([^!]+)!=');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element('solar-spoiler', [md.Text(match[1]!)]));
    return true;
  }
}

/// The `:pack+slug:` sticker syntax.
class SolarStickerInlineSyntax extends md.InlineSyntax {
  SolarStickerInlineSyntax() : super(r':([a-z0-9_]+\+[a-z0-9_\-]+):');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element('solar-sticker', [md.Text(match[0]!)])
      ..attributes['slug'] = match[1]!;
    parser.addNode(element);
    return true;
  }
}

/// All Solar inline syntaxes, in registration order (spoiler before
/// highlight so `=!x!=` is never read as `=` + `!x!`).
List<md.InlineSyntax> solarInlineSyntaxes() => [
      SolarStickerInlineSyntax(),
      SolarSpoilerInlineSyntax(),
      SolarHighlightInlineSyntax(),
      SolarMentionInlineSyntax(),
    ];
