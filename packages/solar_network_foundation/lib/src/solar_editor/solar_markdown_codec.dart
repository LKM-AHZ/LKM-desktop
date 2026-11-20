/// The markdown ⇄ Island Editor [Document] bridge with Solar inline syntaxes.
///
/// `solarMarkdownToDocument` and `solarDocumentToMarkdown` are the two
/// functions every Solar client uses to enter/exit the editor world.
///
/// Solar's own inline syntaxes (`@mention`, `==highlight==`, `=!spoiler!=`,
/// `:sticker:`) are kept intact by a text-level pass: after the standard
/// Island Editor markdown decode, every plain text insert is re-scanned with the
/// Solar regexes and split into attributed runs ([SolarInlineKeys]); before
/// encode, attributed runs are re-written to their markdown markers. This
/// works on the delta level, so it survives every block type the standard
/// pipeline supports and needs no upstream hooks.
library;

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:island_editor/island_editor.dart';

import 'blocks/solar_highlight_spoiler_syntaxes.dart';

const _deepEquality = DeepCollectionEquality();

/// Decodes Solar markdown into an editor [Document].
Document solarMarkdownToDocument(String markdown) {
  final document = markdownToDocument(markdown);
  _applySolarInlineSyntaxToDocument(document);
  return document;
}

/// Encodes an editor [Document] back to Solar markdown.
///
/// [customParsers] lets a host register encoders for its own custom blocks;
/// Solar inline attributes are always handled.
///
/// Blocks are joined here rather than by the Island Editor codec, whose parsers
/// are inconsistent about trailing newlines (paragraphs, quotes and lists
/// emit one, headings, images and tables only when another node follows, and
/// a divider always emits `---\n`). Concatenating those puts a divider
/// directly under the previous line, where `---` is a setext underline and
/// turns the paragraph above it into a heading. Joining with a blank line
/// keeps every block distinct, while consecutive list items stay tight.
String solarDocumentToMarkdown(
  Document document, {
  List<NodeParser> customParsers = const [],
}) {
  final rewritten = _applySolarAttributesToMarkers(document);
  final encoder = DocumentMarkdownEncoder(
    parsers: [
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
  );

  final nodes = rewritten.root.children.toList(growable: false);
  final buffer = StringBuffer();
  for (var i = 0; i < nodes.length; i++) {
    final block = encoder
        .convertNodes([nodes[i]])
        .replaceAll(RegExp(r'\n+$'), '');
    if (i > 0) {
      buffer.write(_isTightListPair(nodes[i - 1], nodes[i]) ? '\n' : '\n\n');
    }
    buffer.write(block);
  }
  return buffer.toString();
}

/// Two neighbouring list items of the same kind render as one tight list;
/// a blank line between them would split it into separate lists.
bool _isTightListPair(Node previous, Node next) {
  if (previous.type != next.type) return false;
  return next.type == BulletedListBlockKeys.type ||
      next.type == NumberedListBlockKeys.type ||
      next.type == TodoListBlockKeys.type;
}

/// Returns a copy of [document] whose deltas carry the Solar markers
/// (`==…==`, `=!…!=`, `:…:`) as plain text, so the standard markdown
/// encoder writes them out verbatim. Mentions already store the `@alias`
/// as the run text and need no rewriting.
Document _applySolarAttributesToMarkers(Document document) {
  if (!_hasSolarAttributes(document.root)) {
    return document;
  }
  final copy = Document.fromJson({
    'document': document.root.toJson(),
  });
  _rewriteSubtree(copy.root);
  return copy;
}

bool _hasSolarAttributes(Node node) {
  if (node.type != 'code') {
    final delta = node.delta;
    if (delta != null) {
      for (final op in delta) {
        final attrs = op.attributes;
        if (attrs != null &&
            (attrs[SolarInlineKeys.mention] is String ||
                attrs[SolarInlineKeys.sticker] is String ||
                attrs[SolarInlineKeys.highlight] == true ||
                attrs[SolarInlineKeys.spoiler] == true)) {
          return true;
        }
      }
    }
  }
  for (final child in node.children) {
    if (_hasSolarAttributes(child)) return true;
  }
  return false;
}

void _rewriteSubtree(Node node) {
  if (node.type != 'code') {
    final delta = node.delta;
    if (delta != null) {
      final rewritten = _markersFromAttributes(delta);
      if (rewritten != delta) {
        node.updateAttributes({'delta': rewritten.toJson()});
      }
    }
  }
  for (final child in node.children.toList(growable: false)) {
    _rewriteSubtree(child);
  }
}

Delta _markersFromAttributes(Delta delta) {
  final result = Delta();
  for (final op in delta.toList()) {
    final data = op.data;
    final attributes = op.attributes;
    if (data is! String || attributes == null) {
      result.add(op);
      continue;
    }
    final mention = attributes[SolarInlineKeys.mention];
    final sticker = attributes[SolarInlineKeys.sticker];
    final highlight = attributes[SolarInlineKeys.highlight] == true;
    final spoiler = attributes[SolarInlineKeys.spoiler] == true;

    if (mention is String) {
      // The run text is the `@alias` itself; nothing to wrap.
      result.insert(data);
      continue;
    }
    if (sticker is String) {
      result.insert(':$sticker:', attributes: _withoutSolar(attributes));
      continue;
    }
    if (spoiler) {
      result.insert('=!$data!=', attributes: _withoutSolar(attributes));
      continue;
    }
    if (highlight) {
      result.insert('==$data==', attributes: _withoutSolar(attributes));
      continue;
    }
    result.add(op);
  }
  return result;
}

Attributes _withoutSolar(Attributes attributes) {
  final copy = {...attributes};
  for (final key in SolarInlineKeys.all) {
    copy.remove(key);
  }
  return copy;
}

// --- Decode pass ---------------------------------------------------------

/// Re-scans every text-bearing node's delta and splits plain runs into
/// Solar-attributed inserts. Runs once per document decode; block deltas
/// (code fences) are skipped — the code block stores raw text.
void _applySolarInlineSyntaxToDocument(Document document) {
  for (final node in document.root.children.toList(growable: false)) {
    _applyToSubtree(node);
  }
}

void _applyToSubtree(Node node) {
  if (node.type == 'code') return;
  final delta = node.delta;
  if (delta != null) {
    node.updateAttributes({
      'delta': _splitDelta(delta).toJson(),
    });
  }
  for (final child in node.children.toList(growable: false)) {
    _applyToSubtree(child);
  }
}

Delta _splitDelta(Delta delta) {
  final result = Delta();
  for (final op in delta.toList()) {
    final data = op.data;
    if (data is! String) {
      result.add(op);
      continue;
    }
    result.addAll(_splitText(data, op.attributes ?? const {}));
  }
  return result;
}

/// Normalizes one node in place: splits any plain run containing a Solar
/// marker into attributed runs. Exposed for the live typing rule, which
/// re-applies it after every transaction so `@mention`, `:pack+slug:`,
/// `==highlight==` and `=!spoiler!=` render as they are typed or inserted
/// instead of only after a document reload.
///
/// No-op for code blocks, which keep raw text, and for nodes already
/// annotated (their attributes survive because [_splitText] preserves the
/// base attributes without duplicating Solar keys).
///
/// Returns whether the node's text changed. Callers that run this while the
/// platform IME is attached must re-sync the IME when it did: the markers are
/// removed from the document, so the IME's own copy of the text is longer and
/// every later delta it sends would land at the wrong offset.
bool solarNormalizeNode(Node node) {
  if (node.type == 'code') return false;
  final delta = node.delta;
  if (delta == null) return false;
  final split = _splitDelta(delta);
  final splitJson = split.toJson();
  final deltaJson = delta.toJson();
  if (_deepEquality.equals(splitJson, deltaJson)) return false;
  node.updateAttributes({'delta': splitJson});
  return true;
}

/// Splits [text] into plain and Solar-attributed inserts, preserving the
/// surrounding [base] attributes (bold, code, …) on every piece.
Iterable<TextOperation> _splitText(String text, Attributes base) sync* {
  var index = 0;
  while (index < text.length) {
    final match = _startMatch(text, index);
    if (match == null) {
      yield TextInsert(
        text.substring(index),
        attributes: base.isEmpty ? null : base,
      );
      return;
    }

    if (match.start > index) {
      final plain = text.substring(index, match.start);
      yield TextInsert(plain, attributes: base.isEmpty ? null : base);
    }

    switch (match.kind) {
      case SolarRunKind.sticker:
        yield TextInsert(
          match.text,
          attributes: {...base, SolarInlineKeys.sticker: match.text.substring(1, match.text.length - 1)},
        );
      case SolarRunKind.spoiler:
        yield TextInsert(
          match.inner!,
          attributes: {...base, SolarInlineKeys.spoiler: true},
        );
      case SolarRunKind.highlight:
        yield TextInsert(
          match.inner!,
          attributes: {...base, SolarInlineKeys.highlight: true},
        );
      case SolarRunKind.mention:
        final alias = match.text;
        final parts = alias.substring(1).split('/');
        final type = switch (parts.length == 1 ? 'u' : parts.first) {
          'u' => 'accounts',
          'r' => 'realms',
          'p' => 'publishers',
          _ => '',
        };
        yield TextInsert(
          alias,
          attributes: {
            ...base,
            SolarInlineKeys.mention: jsonEncode({'alias': alias, 'type': type}),
          },
        );
    }
    index = match.end;
  }
}

enum SolarRunKind { sticker, spoiler, highlight, mention }

/// One matched Solar inline run inside a text insert.
class _SolarRunMatch {
  const _SolarRunMatch({
    required this.kind,
    required this.start,
    required this.end,
    required this.text,
    this.inner,
  });

  final SolarRunKind kind;
  final int start;
  final int end;

  /// The full matched source text (written back verbatim on export).
  final String text;

  /// The content between the markers for spoiler/highlight.
  final String? inner;

}

const _mentionBoundary = r'[^A-Za-z0-9._%+\-/\[]';

/// Finds the first Solar run at or after [start] in [text].
_SolarRunMatch? _startMatch(String text, int start) {
  final scanners = <SolarRunKind, RegExp>{
    SolarRunKind.sticker: RegExp(r':[a-z0-9_]+\+[a-z0-9_\-]+:'),
    SolarRunKind.spoiler: RegExp(r'=![^!]+!'),
    SolarRunKind.highlight: RegExp(r'==[^=]+=='),
    SolarRunKind.mention: RegExp(r'@[A-Za-z0-9_./\-]+'),
  };

  _SolarRunMatch? best;
  for (final entry in scanners.entries) {
    for (var i = start; i < text.length; i++) {
      final match = entry.value.matchAsPrefix(text, i);
      if (match == null) continue;
      if (entry.key == SolarRunKind.mention && i > 0) {
        // Mentions need a non-word boundary before the '@'.
        if (!RegExp(_mentionBoundary).hasMatch(text[i - 1])) continue;
      }
      final candidate = _SolarRunMatch(
        kind: entry.key,
        start: i,
        end: match.end,
        text: match.group(0)!,
      );
      if (best == null || candidate.start < best.start) {
        best = candidate;
      }
      break;
    }
  }
  if (best == null) return null;
  return switch (best.kind) {
    SolarRunKind.spoiler => _SolarRunMatch(
        kind: best.kind,
        start: best.start,
        end: best.end,
        text: best.text,
        inner: best.text.substring(2, best.text.length - 1),
      ),
    SolarRunKind.highlight => _SolarRunMatch(
        kind: best.kind,
        start: best.start,
        end: best.end,
        text: best.text,
        inner: best.text.substring(2, best.text.length - 2),
      ),
    _ => best,
  };
}
