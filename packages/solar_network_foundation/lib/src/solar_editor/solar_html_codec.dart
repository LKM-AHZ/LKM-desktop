/// HTML at the editor boundary, for mail-shaped documents.
///
/// Solian posts are markdown; mail goes to the service as `text/html` and
/// comes back as whatever the sender's client produced. This module is the
/// only place that translates between [Document] and that HTML, so every
/// client accepts and sends the same subset.
///
/// The fork's own HTML codecs are close but not round-trip clean for mail:
///
/// - `<br>` inside a paragraph, quote or list item is dropped, gluing lines
///   together — a quoted reply, which is one `<p>` full of `<br>`, lost every
///   line break on re-send.
/// - `<pre>`/`<pre><code>` decodes to nothing at all, so a code block in an
///   incoming message disappeared.
/// - Lists only read text directly under `<li>`; mail writes
///   `<ul><li><p>…</p></li></ul>`, leaving paragraphs beside text-less items.
/// - Encoding has no inline-code tag, and `DeltaHTMLEncoder` emits `<null>`
///   elements for attributes it does not know — every Solar marker among them.
///
/// A soft line break inside a block is stored as `\n` in the delta (the
/// editor paints it as a break and the markdown codec writes it back
/// verbatim) and encoded as `<br>` again.
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:island_editor/island_editor.dart';

/// Decodes mail HTML into an editor [Document].
///
/// Accepts the wrappers senders emit (`<html>`, `<body>`, a bare `<div>`
/// around one inline run), keeps `<br>` as a line break, and turns `<pre>`
/// content into paragraphs — the editor has no code block.
Document solarHTMLToDocument(String html) {
  if (html.trim().isEmpty) return Document.blank(withInitialText: true);
  return _liftedImages(IslandEditorHTMLCodec().decode(_normalizeIncoming(html)));
}

/// Makes every image a root child.
///
/// The decoder hangs an `<img>` off the paragraph that held it, and neither
/// the paragraph nor the quote block paints its children, so a quoted image
/// rendered as nothing. Payloads and quotes read top-to-bottom, so the image
/// blocks go directly above the block that carried them, in order.
Document _liftedImages(Document document) {
  final root = document.root;
  final imagesByHost = <int, List<Node>>{};
  for (var index = 0; index < root.children.length; index++) {
    final host = root.children[index];
    final images = host.children.where((child) => child.type == 'image');
    if (images.isNotEmpty) {
      imagesByHost[index] = images.toList(growable: false);
    }
  }
  if (imagesByHost.isEmpty) return document;

  for (final images in imagesByHost.values) {
    for (final image in images) {
      image.unlink();
    }
  }
  // Bottom-up: each insertion shifts the hosts below it.
  for (final index in imagesByHost.keys.toList()..sort((a, b) => b - a)) {
    for (final image in imagesByHost[index]!.reversed) {
      document.insert([index + 1], [image]);
    }
  }
  return document;
}

/// Encodes an editor [Document] as the HTML a mail body is sent as.
///
/// Inline code is written as `<code>`; lists, headings, quotes, images,
/// dividers and tables take the same tags the decoder above reads back, so an
/// outgoing message reopens in the composer looking like it left it.
String solarDocumentToHTML(Document document) {
  final nodes = _trimEmptyEdges(document.root.children);
  final buffer = StringBuffer();
  for (final node in nodes) {
    final parser = _mailHTMLNodeParsers.where((p) => p.id == node.type);
    if (parser.isEmpty) continue;
    buffer.write(
      parser.first.transformNodeToHTMLString(
        node,
        encodeParsers: _mailHTMLNodeParsers,
      ),
    );
  }
  return buffer.toString();
}

/// Rewrites the markup the fork's decoder mishandles into the subset it
/// handles, then serializes back.
String _normalizeIncoming(String html) {
  final body = html_parser.parse(html).body;
  if (body == null) return html;

  _unwrapSingleChildWrappers(body);
  _liftParagraphsInsideLists(body);
  _renamePreToParagraphs(body);
  // The decoder ignores `<br>`; a text node's newline survives inside a run,
  // so the break is carried as the text it stands for.
  for (final br in body.querySelectorAll('br')) {
    br.replaceWith(dom.Text('\n'));
  }
  return body.innerHtml;
}

/// `<html><body><div>text</div></body></html>` and single-child wrappers add
/// nesting levels the decoder does not descend through when there is no block
/// tag inside.
void _unwrapSingleChildWrappers(dom.Element body) {
  var changed = true;
  while (changed) {
    changed = false;
    final children = body.nodes;
    if (children.length != 1) continue;
    final only = children.single;
    if (only is! dom.Element) continue;
    if (!const {'div', 'section', 'font'}.contains(only.localName)) continue;
    body.nodes
      ..clear()
      ..addAll(only.nodes);
    changed = true;
  }
}

/// Mail wraps each item in `<p>`; the decoder wants the item's text on the
/// `<li>` itself, or it emits a paragraph beside a text-less list item.
void _liftParagraphsInsideLists(dom.Element body) {
  for (final li in body.querySelectorAll('li')) {
    if (li.children.length != 1) continue;
    final only = li.children.single;
    if (only.localName != 'p') continue;
    li.nodes
      ..clear()
      ..addAll(only.nodes);
  }
}

/// The editor has no code block: `<pre>` content is kept as a paragraph of
/// inline code (its newlines become soft breaks) rather than decoding to
/// nothing.
void _renamePreToParagraphs(dom.Element body) {
  for (final pre in body.querySelectorAll('pre')) {
    final parent = pre.parent;
    if (parent == null) continue;
    final replacement = dom.Element.tag('div');
    for (final node in pre.nodes.toList(growable: false)) {
      if (node is dom.Element && node.localName == 'code') {
        replacement.append(node);
      } else if (node is dom.Text) {
        replacement.append(node);
      }
    }
    if (replacement.nodes.isEmpty) replacement.text = pre.text;
    parent.nodes.insert(parent.nodes.indexOf(pre), replacement);
    pre.remove();
  }
}

/// Drops leading and trailing blank paragraphs the decoder emits around
/// content so a saved message does not grow empty lines on every save.
List<Node> _trimEmptyEdges(Iterable<Node> children) {
  final nodes = children.toList(growable: false);
  var start = 0;
  var end = nodes.length;
  // Only an empty paragraph is a blank line. An image or divider block also
  // carries no text, and dropping those would delete the payload.
  bool isBlank(Node node) =>
      node.type == ParagraphBlockKeys.type &&
      (node.delta?.isEmpty ?? true) &&
      node.children.isEmpty;
  while (start < end && isBlank(nodes[start])) {
    start++;
  }
  while (end > start && isBlank(nodes[end - 1])) {
    end--;
  }
  return nodes.sublist(start, end);
}

const List<HTMLNodeParser> _mailHTMLNodeParsers = [
  _MailTextNodeParser(),
  _MailBulletedListNodeParser(),
  _MailNumberedListNodeParser(),
  _MailTodoListNodeParser(),
  _MailQuoteNodeParser(),
  _MailHeadingNodeParser(),
  _MailImageNodeParser(),
  HtmlTableNodeParser(),
  _MailDividerNodeParser(),
];

/// The stock parser writes inline runs through `DeltaHTMLEncoder`, which has
/// no inline-code tag and emits `<null>` for attributes it does not know
/// (Solar's mention/highlight markers among them). This one owns the inline
/// tags and leaves unknown attributes unwrapped.
class _MailTextNodeParser extends HTMLNodeParser {
  const _MailTextNodeParser();

  @override
  String get id => ParagraphBlockKeys.type;

  @override
  String transformNodeToHTMLString(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    return toHTMLString(
      transformNodeToDomNodes(node, encodeParsers: encodeParsers),
    );
  }

  @override
  List<dom.Node> transformNodeToDomNodes(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    final delta = node.delta ?? Delta();
    final domNodes = encodeSolarInlineDelta(delta);
    domNodes.addAll(
      processChildrenNodes(node.children, encodeParsers: encodeParsers),
    );
    if (domNodes.isEmpty) {
      return [dom.Element.tag(HTMLTags.paragraph)];
    }
    return [
      wrapChildrenNodesWithTagName(HTMLTags.paragraph, childNodes: domNodes),
    ];
  }
}

/// Inline runs to DOM nodes, nesting the tags the decoder reads back and
/// writing soft breaks as `<br>`.
///
/// Public so hosts that encode their own block types can share the inline
/// rules instead of re-deriving them.
List<dom.Node> encodeSolarInlineDelta(Delta delta) {
  final nodes = <dom.Node>[];
  for (final op in delta.toList()) {
    final data = op.data;
    if (data is! String) continue;
    final attributes = op.attributes;
    final chunks = data.split('\n');
    for (var index = 0; index < chunks.length; index++) {
      if (index > 0) nodes.add(dom.Element.tag(HTMLTags.br));
      if (chunks[index].isEmpty) continue;
      nodes.addAll(_wrapRun(chunks[index], attributes));
    }
  }
  return nodes;
}

/// One styled run. Returns a list because an unknown-attribute run may still
/// carry inline tags, and because [dom.Text] is not an [dom.Element] that can
/// be extended in place.
List<dom.Node> _wrapRun(String text, Map<String, dynamic>? attributes) {
  final run = dom.Text(text);
  if (attributes == null || attributes.isEmpty) return [run];

  final href = attributes[IslandRichTextKeys.href];
  final code = attributes[IslandRichTextKeys.code] == true;
  final bold = attributes[IslandRichTextKeys.bold] == true;
  final italic = attributes[IslandRichTextKeys.italic] == true;
  final underline = attributes[IslandRichTextKeys.underline] == true;
  final strike = attributes[IslandRichTextKeys.strikethrough] == true;
  final textColor = attributes[IslandRichTextKeys.textColor];
  final background = attributes[IslandRichTextKeys.backgroundColor];

  dom.Node styled = run;
  if (code) styled = _tag(HTMLTags.code, styled);
  if (strike) styled = _tag(HTMLTags.strikethrough, styled);
  if (underline) styled = _tag(HTMLTags.underline, styled);
  if (italic) styled = _tag(HTMLTags.italic, styled);
  if (bold) styled = _tag(HTMLTags.bold, styled);

  final css = <String>[
    if (textColor is String) 'color: ${_hexToCss(textColor)}',
    if (background is String) 'background-color: ${_hexToCss(background)}',
  ].join('; ');
  if (css.isNotEmpty) {
    styled = dom.Element.tag(HTMLTags.span)..attributes['style'] = css;
    styled.append(run);
  }

  if (href is String) {
    final anchor = dom.Element.tag(HTMLTags.anchor)..attributes['href'] = href;
    anchor.append(styled);
    return [anchor];
  }
  return [styled];
}

/// Island Editor stores colours as `0x`/`#` hex strings; mail readers want CSS.
String _hexToCss(String raw) {
  var hex = raw.trim();
  if (hex.startsWith('0x')) hex = hex.substring(2);
  if (hex.startsWith('#')) return hex;
  if (hex.length == 8) return '#${hex.substring(2)}';
  return '#$hex';
}

dom.Node _tag(String name, dom.Node child) =>
    dom.Element.tag(name)..append(child);

List<dom.Node> _encodeListItem(
  Node node,
  List<HTMLNodeParser> encodeParsers, {
  String tag = HTMLTags.list,
  dom.Node? prefix,
}) {
  final item = dom.Element.tag(tag);
  if (prefix != null) item.append(prefix);
  item.nodes.addAll(encodeSolarInlineDelta(node.delta ?? Delta()));
  for (final child in node.children) {
    final parser = encodeParsers.where((p) => p.id == child.type);
    if (parser.isEmpty) continue;
    item.nodes.addAll(
      parser.first.transformNodeToDomNodes(
        child,
        encodeParsers: encodeParsers,
      ),
    );
  }
  return [item];
}

class _MailBulletedListNodeParser extends HTMLNodeParser {
  const _MailBulletedListNodeParser();

  @override
  String get id => BulletedListBlockKeys.type;

  @override
  String transformNodeToHTMLString(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    return toHTMLString(
      transformNodeToDomNodes(node, encodeParsers: encodeParsers),
    );
  }

  @override
  List<dom.Node> transformNodeToDomNodes(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    return [
      dom.Element.tag(HTMLTags.unorderedList)
        ..nodes.addAll(_encodeListItem(node, encodeParsers)),
    ];
  }
}

class _MailNumberedListNodeParser extends HTMLNodeParser {
  const _MailNumberedListNodeParser();

  @override
  String get id => NumberedListBlockKeys.type;

  @override
  String transformNodeToHTMLString(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    return toHTMLString(
      transformNodeToDomNodes(node, encodeParsers: encodeParsers),
    );
  }

  @override
  List<dom.Node> transformNodeToDomNodes(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    return [
      dom.Element.tag(HTMLTags.orderedList)
        ..nodes.addAll(_encodeListItem(node, encodeParsers)),
    ];
  }
}

class _MailTodoListNodeParser extends HTMLNodeParser {
  const _MailTodoListNodeParser();

  @override
  String get id => TodoListBlockKeys.type;

  @override
  String transformNodeToHTMLString(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    return toHTMLString(
      transformNodeToDomNodes(node, encodeParsers: encodeParsers),
    );
  }

  @override
  List<dom.Node> transformNodeToDomNodes(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    final checkbox = dom.Element.tag(HTMLTags.checkbox)
      ..attributes['type'] = 'checkbox';
    if (node.attributes[TodoListBlockKeys.checked] == true) {
      checkbox.attributes['checked'] = '';
    }
    return [
      dom.Element.tag(HTMLTags.unorderedList)
        ..nodes.addAll(_encodeListItem(node, encodeParsers, prefix: checkbox)),
    ];
  }
}

class _MailQuoteNodeParser extends HTMLNodeParser {
  const _MailQuoteNodeParser();

  @override
  String get id => QuoteBlockKeys.type;

  @override
  String transformNodeToHTMLString(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    return toHTMLString(
      transformNodeToDomNodes(node, encodeParsers: encodeParsers),
    );
  }

  @override
  List<dom.Node> transformNodeToDomNodes(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    final quote = dom.Element.tag(HTMLTags.blockQuote)
      ..nodes.addAll(encodeSolarInlineDelta(node.delta ?? Delta()));
    quote.nodes.addAll(
      processChildrenNodes(node.children, encodeParsers: encodeParsers),
    );
    return [quote];
  }
}

class _MailHeadingNodeParser extends HTMLNodeParser {
  const _MailHeadingNodeParser();

  @override
  String get id => HeadingBlockKeys.type;

  @override
  String transformNodeToHTMLString(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    return toHTMLString(
      transformNodeToDomNodes(node, encodeParsers: encodeParsers),
    );
  }

  @override
  List<dom.Node> transformNodeToDomNodes(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    final level = (node.attributes[HeadingBlockKeys.level] as int? ?? 1)
        .clamp(1, 6);
    final heading = dom.Element.tag('h$level')
      ..nodes.addAll(encodeSolarInlineDelta(node.delta ?? Delta()));
    heading.nodes.addAll(
      processChildrenNodes(node.children, encodeParsers: encodeParsers),
    );
    return [heading];
  }
}

class _MailImageNodeParser extends HTMLNodeParser {
  const _MailImageNodeParser();

  @override
  String get id => ImageBlockKeys.type;

  @override
  String transformNodeToHTMLString(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    return toHTMLString(
      transformNodeToDomNodes(node, encodeParsers: encodeParsers),
    );
  }

  @override
  List<dom.Node> transformNodeToDomNodes(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    final src = node.attributes[ImageBlockKeys.url];
    if (src is! String || src.isEmpty) return const [];
    return [dom.Element.tag(HTMLTags.image)..attributes['src'] = src];
  }
}

class _MailDividerNodeParser extends HTMLNodeParser {
  const _MailDividerNodeParser();

  @override
  String get id => DividerBlockKeys.type;

  @override
  String transformNodeToHTMLString(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    return toHTMLString(
      transformNodeToDomNodes(node, encodeParsers: encodeParsers),
    );
  }

  @override
  List<dom.Node> transformNodeToDomNodes(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    return [dom.Element.tag(HTMLTags.divider)];
  }
}
