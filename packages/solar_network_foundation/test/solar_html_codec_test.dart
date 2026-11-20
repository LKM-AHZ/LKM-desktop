import 'package:flutter_test/flutter_test.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart';

/// Mail bodies arrive from other people's clients, so these are the shapes a
/// composer actually has to survive — not round-trips of our own output.
List<String> _types(Document document) =>
    document.root.children.map((node) => node.type).toList();

List<String> _texts(Node node) => [
  if (node.delta != null) node.delta!.toPlainText(),
  for (final child in node.children) ..._texts(child),
];

void main() {
  group('mail HTML decoding', () {
    test('a <br> inside a paragraph stays a line break', () {
      // Quoted replies are one paragraph full of `<br>`; the fork's decoder
      // dropped the element and glued the lines into one run.
      final document = solarHTMLToDocument('<p>line one<br>line two</p>');
      expect(_texts(document.root.children.single).single, 'line one\nline two');
      expect(solarDocumentToHTML(document), '<p>line one<br>line two</p>');
    });

    test('a <br> inside a quote stays a line break', () {
      final document = solarHTMLToDocument(
        '<blockquote><p>quoted<br>reply</p></blockquote>',
      );
      expect(_types(document), ['quote']);
      expect(_texts(document.root.children.single), contains('quoted\nreply'));
    });

    test('<pre> content is kept instead of decoding to nothing', () {
      final document = solarHTMLToDocument(
        '<pre><code>final x = 1;\nfinal y = 2;</code></pre>',
      );
      expect(document.root.children, isNotEmpty);
      final text = document.root.children
          .map((node) => node.delta?.toPlainText() ?? '')
          .join('\n');
      expect(text, contains('final x = 1;'));
      expect(text, contains('final y = 2;'));
    });

    test('mail-style lists keep their items', () {
      // Mail clients wrap each item in a <p>; the decoder wants the text on
      // the <li> or it emits a paragraph beside a text-less item.
      final document = solarHTMLToDocument(
        '<ul><li><p>one</p></li><li><p>two</p></li></ul>'
        '<ol><li><p>first</p></li></ol>',
      );
      expect(_types(document), ['bulleted_list', 'bulleted_list', 'numbered_list']);
      expect(_texts(document.root.children.first), contains('one'));
      expect(_texts(document.root.children.last), contains('first'));
    });

    test('a wrapper around one inline run is not swallowed', () {
      final document = solarHTMLToDocument(
        '<html><body><div>Hello there</div></body></html>',
      );
      expect(_types(document), ['paragraph']);
      expect(_texts(document.root.children.single), contains('Hello there'));
    });

    test('empty and plain input', () {
      expect(solarDocumentToHTML(solarHTMLToDocument('')), isEmpty);
      expect(solarDocumentToHTML(solarHTMLToDocument('Hello')), '<p>Hello</p>');
    });

    test('trailing blank paragraphs are dropped', () {
      final document = solarHTMLToDocument('<p>Hello</p><p></p>');
      expect(solarDocumentToHTML(document), '<p>Hello</p>');
    });
  });

  group('mail HTML encoding', () {
    test('inline code and links survive the trip', () {
      final document = solarHTMLToDocument(
        '<p><code>x</code> and <a href="https://example.com">link</a></p>',
      );
      final html = solarDocumentToHTML(document);
      expect(html, contains('<code>x</code>'));
      expect(html, contains('<a href="https://example.com">link</a>'));
    });

    test('Solar inline attributes do not emit <null> tags', () {
      // `DeltaHTMLEncoder` turns an attribute it does not know into a
      // `<null>` element; every Solar marker is one of those.
      final document = solarMarkdownToDocument('hi ==highlighted== there');
      final html = solarDocumentToHTML(document);
      expect(html, isNot(contains('<null>')));
      expect(html, contains('highlighted'));
    });

    test('headings keep their level', () {
      final document = solarHTMLToDocument('<h2>Heading</h2>');
      expect(solarDocumentToHTML(document), '<h2>Heading</h2>');
    });

    test('images are encoded as blocks', () {
      final document = solarHTMLToDocument(
        '<p><img src="https://example.com/pic.png"></p>',
      );
      expect(_types(document), contains('image'));
      expect(
        solarDocumentToHTML(document),
        contains('src="https://example.com/pic.png"'),
      );
    });
  });
}
