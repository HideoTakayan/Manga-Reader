import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/features/reader/epub/epub_models.dart';
import 'package:manga_reader/features/reader/epub/epub_paginator.dart';
import 'dart:typed_data';

void main() {
  group('EpubPaginator Tests', () {
    const viewportSize = Size(300, 400);
    const baseStyle = TextStyle(fontSize: 16, height: 1.5);
    const blockSpacing = 24.0;

    test('Long paragraph at start splits into multiple pages', () {
      final longText = 'A ' * 1000;
      final chapter = EpubChapter(
        title: 'Ch 1',
        blocks: [
          EpubBlock.plainText(type: EpubBlockType.paragraph, text: longText),
        ],
      );

      final pages = EpubPaginator.paginate(
        chapter: chapter,
        viewportSize: viewportSize,
        baseTextStyle: baseStyle,
        blockSpacing: blockSpacing,
      );

      expect(pages.length, greaterThan(1));

      // Join text back and verify no data loss
      final fullReconstructed = pages.map((p) => p.text).join(' ');
      // because we trim() during split, exact spaces might differ slightly, but words should remain
      expect(
        fullReconstructed.replaceAll(RegExp(r'\s+'), ' ').trim(),
        longText.replaceAll(RegExp(r'\s+'), ' ').trim(),
      );
    });

    test('Each page fragment fits within viewport height with margin', () {
      final longText = 'Word ' * 500;
      final chapter = EpubChapter(
        title: 'Ch 2',
        blocks: [
          EpubBlock.plainText(type: EpubBlockType.paragraph, text: longText),
        ],
      );

      final pages = EpubPaginator.paginate(
        chapter: chapter,
        viewportSize: viewportSize,
        baseTextStyle: baseStyle,
        blockSpacing: blockSpacing,
      );

      for (var page in pages) {
        double currentHeight = 0;
        for (var block in page.blocks) {
          final tp = TextPainter(
            text: EpubPaginator.buildTextSpan(block, baseStyle),
            textDirection: TextDirection.ltr,
          );
          tp.layout(maxWidth: viewportSize.width);
          currentHeight += tp.height + blockSpacing;
        }

        // Since we split the last block, its margin was considered.
        // We only allow it to be slightly over if it's forced (a single word on a tiny viewport),
        // but for 300x400 it should fit exactly.
        // We allow some delta for float inaccuracies.
        expect(currentHeight, lessThanOrEqualTo(viewportSize.height));
      }
    });

    test('Paragraph -> Image -> Paragraph keeps correct order', () {
      final imgBytes = Uint8List.fromList([0]);
      final chapter = EpubChapter(
        title: 'Ch 3',
        blocks: [
          EpubBlock.plainText(
            type: EpubBlockType.paragraph,
            text: 'Before image',
          ),
          EpubBlock(type: EpubBlockType.image, image: imgBytes),
          EpubBlock.plainText(
            type: EpubBlockType.paragraph,
            text: 'After image',
          ),
        ],
      );

      final pages = EpubPaginator.paginate(
        chapter: chapter,
        viewportSize: viewportSize,
        baseTextStyle: baseStyle,
        blockSpacing: blockSpacing,
      );

      // Should be 3 pages minimum because image forces a break.
      expect(pages.length, 3);
      expect(pages[0].blocks.first.text, 'Before image');
      expect(pages[1].blocks.first.type, EpubBlockType.image);
      expect(pages[2].blocks.first.text, 'After image');
    });

    test('Divider and heading do not overflow or lose data', () {
      final chapter = EpubChapter(
        title: 'Ch 4',
        blocks: [
          EpubBlock.plainText(type: EpubBlockType.heading, text: 'Heading'),
          const EpubBlock(type: EpubBlockType.divider),
          EpubBlock.plainText(type: EpubBlockType.paragraph, text: 'Content'),
        ],
      );

      final pages = EpubPaginator.paginate(
        chapter: chapter,
        viewportSize: viewportSize,
        baseTextStyle: baseStyle,
        blockSpacing: blockSpacing,
      );

      expect(pages.isNotEmpty, true);
      final blocks = pages.expand((p) => p.blocks).toList();

      expect(blocks[0].type, EpubBlockType.heading);
      expect(blocks[1].type, EpubBlockType.divider);
      expect(blocks[2].type, EpubBlockType.paragraph);
    });

    test('Extremely small viewport does not cause infinite loop', () {
      final chapter = EpubChapter(
        title: 'Ch 5',
        blocks: [
          EpubBlock.plainText(
            type: EpubBlockType.paragraph,
            text: 'This is a long sentence to test tiny viewport loop.',
          ),
        ],
      );

      // Viewport height smaller than one line, width smaller than one word
      final pages = EpubPaginator.paginate(
        chapter: chapter,
        viewportSize: const Size(10, 10),
        baseTextStyle: baseStyle,
        blockSpacing: blockSpacing,
      );

      // Should force paginate each word
      expect(pages.length, greaterThan(5));
      expect(pages.first.blocks.first.text, isNotEmpty);
    });

    test('Inline bold and italic spans are preserved across page splits', () {
      // A mix of bold and plain text
      final spans = [
        const EpubSpan(
          text: 'Normal text. ',
          bold: false,
          italic: false,
          underline: false,
        ),
        const EpubSpan(
          text: 'Bold text. ',
          bold: true,
          italic: false,
          underline: false,
        ),
        const EpubSpan(
          text: 'Italic text. ',
          bold: false,
          italic: true,
          underline: false,
        ),
        const EpubSpan(
          text: 'Underlined text. ',
          bold: false,
          italic: false,
          underline: true,
        ),
      ];
      // Repeat to force pagination
      final allSpans = List.generate(
        50,
        (_) => spans,
      ).expand((s) => s).toList();
      final chapter = EpubChapter(
        title: 'Rich',
        blocks: [EpubBlock(type: EpubBlockType.paragraph, spans: allSpans)],
      );

      final pages = EpubPaginator.paginate(
        chapter: chapter,
        viewportSize: viewportSize,
        baseTextStyle: baseStyle,
        blockSpacing: blockSpacing,
      );

      expect(pages.length, greaterThan(1));

      final paginatedSpans = pages
          .expand((page) => page.blocks)
          .expand((block) => block.spans ?? const <EpubSpan>[])
          .toList();
      final reconstructed = paginatedSpans.map((span) => span.text).join(' ');
      final expectedText = allSpans.map((span) => span.text).join();
      expect(
        reconstructed.replaceAll(RegExp(r'\s+'), ' ').trim(),
        expectedText.replaceAll(RegExp(r'\s+'), ' ').trim(),
      );
      expect(paginatedSpans.any((span) => span.bold), true);
      expect(paginatedSpans.any((span) => span.italic), true);
      expect(paginatedSpans.any((span) => span.underline), true);
      expect(_styledCharacters(paginatedSpans), _styledCharacters(allSpans));
    });

    for (final lineHeight in [1.2, 1.65, 2.5]) {
      test('Rich text pages fit viewport at line height $lineHeight', () {
        final style = TextStyle(fontSize: 16, height: lineHeight);
        final spacing = style.fontSize! * lineHeight;
        final chapter = EpubChapter(
          title: 'Rich fit',
          blocks: [
            EpubBlock(
              type: EpubBlockType.paragraph,
              spans: List.generate(
                80,
                (index) => EpubSpan(
                  text: index.isEven ? 'Wide bold words ' : 'normal words ',
                  bold: index.isEven,
                ),
              ),
            ),
          ],
        );

        final pages = EpubPaginator.paginate(
          chapter: chapter,
          viewportSize: viewportSize,
          baseTextStyle: style,
          blockSpacing: spacing,
        );

        for (final page in pages) {
          var height = 0.0;
          for (final block in page.blocks) {
            final painter = TextPainter(
              text: EpubPaginator.buildTextSpan(block, style),
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: viewportSize.width);
            height += painter.height + spacing;
          }
          expect(height, lessThanOrEqualTo(viewportSize.height));
        }
      });
    }
  });
}

List<(String, bool, bool, bool)> _styledCharacters(List<EpubSpan> spans) {
  return [
    for (final span in spans)
      for (final character in span.text.split(''))
        if (character.trim().isNotEmpty)
          (character, span.bold, span.italic, span.underline),
  ];
}
