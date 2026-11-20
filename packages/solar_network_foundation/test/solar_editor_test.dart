import 'package:flutter_test/flutter_test.dart';
import 'package:solar_network_foundation/src/solar_editor/blocks/solar_highlight_spoiler_syntaxes.dart';
import 'package:solar_network_foundation/src/solar_editor/solar_markdown_codec.dart';

void main() {
  group('solar markdown codec', () {
    test('plain markdown round-trips through the editor document', () {
      const src = '# Title\n\nhello **world** and `code`\n\n> quoted';
      final document = solarMarkdownToDocument(src);
      expect(document.root.children, isNotEmpty);

      final out = solarDocumentToMarkdown(document);
      expect(out, contains('# Title'));
      expect(out, contains('**world**'));
      expect(out, contains('> quoted'));
    });

    test('mention becomes an attributed insert and round-trips', () {
      const src = 'hello @alice how are you';
      final document = solarMarkdownToDocument(src);
      final paragraph = document.root.children.first;
      final delta = paragraph.delta!;

      final mentionRun = delta.toList().firstWhere(
            (op) => op.attributes?.containsKey(SolarInlineKeys.mention) == true,
          );
      expect(mentionRun.data, '@alice');

      final out = solarDocumentToMarkdown(document);
      expect(out, contains('@alice'));
    });

    test('highlight and spoiler round-trip', () {
      const src = 'a ==marked== and =!hidden!= end';
      final document = solarMarkdownToDocument(src);
      final delta = document.root.children.first.delta!;

      expect(
        delta.toList().any(
              (op) => op.attributes?[SolarInlineKeys.highlight] == true &&
                  op.data == 'marked',
            ),
        isTrue,
      );
      expect(
        delta.toList().any(
              (op) => op.attributes?[SolarInlineKeys.spoiler] == true &&
                  op.data == 'hidden',
            ),
        isTrue,
      );

      final out = solarDocumentToMarkdown(document);
      expect(out, contains('==marked=='));
      expect(out, contains('=!hidden!='));
    });

    test('sticker round-trips with its slug', () {
      const src = 'nice :fire+red: sticker';
      final document = solarMarkdownToDocument(src);
      final delta = document.root.children.first.delta!;

      final stickerRun = delta.toList().firstWhere(
            (op) => op.attributes?.containsKey(SolarInlineKeys.sticker) == true,
          );
      expect(stickerRun.data, ':fire+red:');
      expect(stickerRun.attributes![SolarInlineKeys.sticker], 'fire+red');

      final out = solarDocumentToMarkdown(document);
      expect(out, contains(':fire+red:'));
    });

    test('solarNormalizeNode annotates text inserted after decode', () {
      // Typing (or a toolbar insert) puts the marker in as plain text; the
      // rule re-annotates it so the editor renders it without a reload.
      final document = solarMarkdownToDocument('hello ');
      final node = document.root.children.first;
      // Plain text lands in the delta exactly like a keystroke or toolbar
      // insert does; the normalizer then annotates it.
      final delta = node.delta!
        ..insert('ping @alice :fire+red: now');
      node.updateAttributes({'delta': delta.toJson()});
      solarNormalizeNode(node);

      final normalized = node.delta!;
      final mention = normalized.toList().firstWhere(
        (op) => op.attributes?.containsKey(SolarInlineKeys.mention) == true,
      );
      expect(mention.data, '@alice');
      final sticker = normalized.toList().firstWhere(
        (op) => op.attributes?.containsKey(SolarInlineKeys.sticker) == true,
      );
      expect(sticker.attributes![SolarInlineKeys.sticker], 'fire+red');

      final out = solarDocumentToMarkdown(document);
      expect(out, contains('@alice'));
      expect(out, contains(':fire+red:'));
    });

    test('solarNormalizeNode leaves already-annotated runs stable', () {
      // Re-normalizing is idempotent: markup in, same delta out, so the
      // per-transaction hook can run on every keystroke without churn.
      final document = solarMarkdownToDocument('hi @alice :fire+red:');
      final node = document.root.children.first;
      final before = node.delta!.toJson();
      solarNormalizeNode(node);
      expect(node.delta!.toJson(), before);
    });

    test('solar syntaxes inside bold keep both attributes', () {
      const src = '**bold ==inner==**';
      final document = solarMarkdownToDocument(src);
      final delta = document.root.children.first.delta!;

      final run = delta.toList().firstWhere(
            (op) => op.attributes?[SolarInlineKeys.highlight] == true,
          );
      expect(run.attributes![SolarInlineKeys.highlight], isTrue);
    });

    test('mentions inside lists and quotes survive', () {
      const src = '- item @bob here\n\n> quote @carol';
      final document = solarMarkdownToDocument(src);

      final out = solarDocumentToMarkdown(document);
      expect(out, contains('@bob'));
      expect(out, contains('@carol'));
    });

    test('blocks are separated by a blank line', () {
      // `---` directly under a paragraph is a setext heading underline, so a
      // missing blank line silently turns the block above into a heading.
      const src = 'paragraph\n\n---\n\nafter';
      final out = solarDocumentToMarkdown(solarMarkdownToDocument(src));
      expect(out, src);
      expect(out.contains('paragraph\n---'), isFalse);
    });

    test('a divider after a heading does not swallow it', () {
      const src = '# Title\n\n---\n\nbody';
      expect(solarDocumentToMarkdown(solarMarkdownToDocument(src)), src);
    });

    test('consecutive list items stay one tight list', () {
      final out = solarDocumentToMarkdown(
        solarMarkdownToDocument('- a\n- b\n- c'),
      );
      // Tight: no blank lines between items, so markdown reads them as one
      // list instead of three separate ones.
      expect(out.split('\n').where((l) => l.trim().isEmpty), isEmpty);
      expect(out, contains('* a'));
      expect(out, contains('* b'));
    });

    test('a list after a paragraph keeps its blank line', () {
      final out = solarDocumentToMarkdown(
        solarMarkdownToDocument('intro\n\n- a\n- b'),
      );
      expect(out, startsWith('intro\n\n'));
    });

    test('quote and image blocks stay separated', () {
      const src = '> quoted\n\n![alt](solian://files/1)';
      final out = solarDocumentToMarkdown(solarMarkdownToDocument(src));
      expect(out, contains('> quoted\n\n![]'));
    });
  });
}
