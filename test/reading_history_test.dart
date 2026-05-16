import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/data/models.dart';

void main() {
  group('ReadingHistory.fromMap', () {
    test('reads current mangaId schema', () {
      final history = ReadingHistory.fromMap({
        'userId': 'user-1',
        'mangaId': 'manga-1',
        'chapterId': 'chapter-1',
        'chapterTitle': 'Chapter 1',
        'lastPageIndex': 4,
        'updatedAt': 1000,
      });

      expect(history.userId, 'user-1');
      expect(history.mangaId, 'manga-1');
      expect(history.chapterId, 'chapter-1');
      expect(history.lastPageIndex, 4);
      expect(history.updatedAt.millisecondsSinceEpoch, 1000);
    });

    test('keeps backward compatibility with comicId schema', () {
      final history = ReadingHistory.fromMap({
        'userId': 'user-1',
        'comicId': 'old-manga-1',
        'chapterId': 'chapter-1',
        'lastPageIndex': '7',
        'updatedAt': '2000',
      });

      expect(history.mangaId, 'old-manga-1');
      expect(history.lastPageIndex, 7);
      expect(history.updatedAt.millisecondsSinceEpoch, 2000);
    });

    test('does not throw on partial data', () {
      final history = ReadingHistory.fromMap({});

      expect(history.userId, 'guest');
      expect(history.mangaId, '');
      expect(history.chapterId, '');
      expect(history.lastPageIndex, 0);
      expect(history.updatedAt.millisecondsSinceEpoch, 0);
    });
  });

  group('ReaderProgress.fromMap', () {
    test('parses numeric fields safely', () {
      final progress = ReaderProgress.fromMap({
        'mangaId': 'manga-1',
        'chapterId': 'chapter-2',
        'pageIndex': '12',
        'scrollOffset': '345.5',
        'progressPercent': 0.75,
        'updatedAt': '3000',
      });

      expect(progress.mangaId, 'manga-1');
      expect(progress.chapterId, 'chapter-2');
      expect(progress.pageIndex, 12);
      expect(progress.scrollOffset, 345.5);
      expect(progress.progressPercent, 0.75);
      expect(progress.updatedAt.millisecondsSinceEpoch, 3000);
    });
  });

  group('ReaderBookmark.fromMap', () {
    test('round-trips bookmark data', () {
      final bookmark = ReaderBookmark(
        id: 'bookmark-1',
        mangaId: 'manga-1',
        chapterId: 'chapter-1',
        pageIndex: 3,
        scrollOffset: 120,
        note: 'good page',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      final parsed = ReaderBookmark.fromMap(bookmark.toMap());

      expect(parsed.id, 'bookmark-1');
      expect(parsed.mangaId, 'manga-1');
      expect(parsed.chapterId, 'chapter-1');
      expect(parsed.pageIndex, 3);
      expect(parsed.scrollOffset, 120);
      expect(parsed.note, 'good page');
      expect(parsed.createdAt.millisecondsSinceEpoch, 1000);
      expect(parsed.updatedAt.millisecondsSinceEpoch, 2000);
    });
  });
}
