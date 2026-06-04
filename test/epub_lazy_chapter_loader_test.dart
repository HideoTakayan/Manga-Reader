import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/features/reader/epub/epub_lazy_chapter_loader.dart';
import 'package:manga_reader/features/reader/epub/epub_models.dart';

void main() {
  group('EpubLazyChapterLoader', () {
    late ParsedEpubIndex index;
    late Map<String, int> parseCounts;

    setUp(() {
      index = ParsedEpubIndex(
        title: 'Lazy Book',
        chapters: [
          for (var chapter = 0; chapter < 6; chapter++)
            EpubChapterReference(
              title: 'Chapter $chapter',
              href: 'chapter-$chapter.xhtml',
            ),
        ],
      );
      parseCounts = {};
    });

    EpubLazyChapterLoader createLoader({int maxCachedChapters = 3}) {
      return EpubLazyChapterLoader(
        index: index,
        bytes: Uint8List.fromList([80, 75, 5, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        maxCachedChapters: maxCachedChapters,
        parser: (reference) async {
          parseCounts.update(
            reference.href,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
          return EpubChapter(
            title: reference.title,
            blocks: [
              EpubBlock.plainText(
                type: EpubBlockType.paragraph,
                text: reference.href,
              ),
            ],
          );
        },
      );
    }

    test('loads chapter once while it remains cached', () async {
      final loader = createLoader();

      final first = await loader.load(2);
      final second = await loader.load(2);

      expect(first, same(second));
      expect(parseCounts['chapter-2.xhtml'], 1);
      expect(loader.cachedChapterIndexes, [2]);
    });

    test('evicts least recently used chapter over cache limit', () async {
      final loader = createLoader(maxCachedChapters: 2);

      await loader.load(0);
      await loader.load(1);
      await loader.load(0);
      await loader.load(2);

      expect(loader.cachedChapterIndexes, [0, 2]);
      expect(loader.peek(1), isNull);
    });

    test('preloads nearby chapters and can retain a smaller window', () async {
      final loader = createLoader(maxCachedChapters: 5);

      await loader.preloadAround(3, radius: 2);
      expect(loader.cachedChapterIndexes, [1, 2, 3, 4, 5]);

      loader.retainAround(3, radius: 1);
      expect(loader.cachedChapterIndexes, [2, 3, 4]);
    });

    test('rejects chapter index outside spine', () async {
      final loader = createLoader();

      expect(() => loader.load(-1), throwsRangeError);
      expect(() => loader.load(6), throwsRangeError);
    });
  });
}
