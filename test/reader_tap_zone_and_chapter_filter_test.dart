import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/data/models.dart';
import 'package:manga_reader/data/models_cloud.dart';
import 'package:manga_reader/features/reader/reader_provider.dart';
import 'package:manga_reader/features/search/search_page.dart';

void main() {
  group('ReaderTapZone & ReaderState Tests', () {
    test('ReaderTapZone enum values exist and defaults to default3Cols in ReaderState', () {
      expect(ReaderTapZone.values, contains(ReaderTapZone.default3Cols));
      expect(ReaderTapZone.values, contains(ReaderTapZone.oneHanded));
      expect(ReaderTapZone.values, contains(ReaderTapZone.leftHanded));
      expect(ReaderTapZone.values, contains(ReaderTapZone.swipeOnly));

      const state = ReaderState();
      expect(state.tapZone, ReaderTapZone.default3Cols);
    });

    test('ReaderState copyWith correctly updates tapZone', () {
      const state = ReaderState();
      final updated1 = state.copyWith(tapZone: ReaderTapZone.oneHanded);
      expect(updated1.tapZone, ReaderTapZone.oneHanded);

      final updated2 = updated1.copyWith(tapZone: ReaderTapZone.leftHanded);
      expect(updated2.tapZone, ReaderTapZone.leftHanded);

      final updated3 = updated2.copyWith(tapZone: ReaderTapZone.swipeOnly);
      expect(updated3.tapZone, ReaderTapZone.swipeOnly);
    });

    test('ReaderState volumePageTurn & invertVolumeKeys default and update correctly', () {
      const state = ReaderState();
      expect(state.volumePageTurn, isTrue);
      expect(state.invertVolumeKeys, isFalse);

      final updated = state.copyWith(
        volumePageTurn: false,
        invertVolumeKeys: true,
      );
      expect(updated.volumePageTurn, isFalse);
      expect(updated.invertVolumeKeys, isTrue);
    });

    test('Volume key navigation mapping logic behaves accurately', () {
      ({bool isNext, bool isPrev}) evaluateVolumeKey({
        required bool isVolDown,
        required bool isVolUp,
        required bool volumePageTurn,
        required bool invertVolumeKeys,
      }) {
        if (!volumePageTurn) return (isNext: false, isPrev: false);
        if (invertVolumeKeys) {
          return (isNext: isVolUp, isPrev: isVolDown);
        } else {
          return (isNext: isVolDown, isPrev: isVolUp);
        }
      }

      // Normal mode: VolDown = Next, VolUp = Prev
      final normDown = evaluateVolumeKey(
        isVolDown: true,
        isVolUp: false,
        volumePageTurn: true,
        invertVolumeKeys: false,
      );
      expect(normDown.isNext, isTrue);
      expect(normDown.isPrev, isFalse);

      final normUp = evaluateVolumeKey(
        isVolDown: false,
        isVolUp: true,
        volumePageTurn: true,
        invertVolumeKeys: false,
      );
      expect(normUp.isNext, isFalse);
      expect(normUp.isPrev, isTrue);

      // Inverted mode: VolUp = Next, VolDown = Prev
      final invDown = evaluateVolumeKey(
        isVolDown: true,
        isVolUp: false,
        volumePageTurn: true,
        invertVolumeKeys: true,
      );
      expect(invDown.isNext, isFalse);
      expect(invDown.isPrev, isTrue);

      final invUp = evaluateVolumeKey(
        isVolDown: false,
        isVolUp: true,
        volumePageTurn: true,
        invertVolumeKeys: true,
      );
      expect(invUp.isNext, isTrue);
      expect(invUp.isPrev, isFalse);

      // Disabled mode: volume keys do nothing
      final disabled = evaluateVolumeKey(
        isVolDown: true,
        isVolUp: false,
        volumePageTurn: false,
        invertVolumeKeys: false,
      );
      expect(disabled.isNext, isFalse);
      expect(disabled.isPrev, isFalse);
    });
  });

  group('ReaderDualPageMode Tests', () {
    test('ReaderDualPageMode enum values exist and defaults to off in ReaderState', () {
      expect(ReaderDualPageMode.values, contains(ReaderDualPageMode.off));
      expect(ReaderDualPageMode.values, contains(ReaderDualPageMode.dual));
      expect(ReaderDualPageMode.values, contains(ReaderDualPageMode.dualCover));

      const state = ReaderState();
      expect(state.dualPageMode, ReaderDualPageMode.off);
    });

    test('ReaderState copyWith correctly updates dualPageMode', () {
      const state = ReaderState();
      final updated1 = state.copyWith(dualPageMode: ReaderDualPageMode.dual);
      expect(updated1.dualPageMode, ReaderDualPageMode.dual);

      final updated2 = updated1.copyWith(dualPageMode: ReaderDualPageMode.dualCover);
      expect(updated2.dualPageMode, ReaderDualPageMode.dualCover);
    });

    List<List<int>> calculateSpreads(int totalPages, ReaderDualPageMode mode) {
      if (totalPages <= 0) return [];
      if (mode == ReaderDualPageMode.off) {
        return List.generate(totalPages, (i) => [i]);
      }
      final spreads = <List<int>>[];
      int startIndex = 0;
      if (mode == ReaderDualPageMode.dualCover) {
        spreads.add([0]);
        startIndex = 1;
      }
      for (int i = startIndex; i < totalPages; i += 2) {
        if (i + 1 < totalPages) {
          spreads.add([i, i + 1]);
        } else {
          spreads.add([i]);
        }
      }
      return spreads;
    }

    test('calculateSpreads works accurately across off, dual, and dualCover', () {
      // 5 pages:
      // Off: [[0], [1], [2], [3], [4]]
      expect(calculateSpreads(5, ReaderDualPageMode.off), [
        [0], [1], [2], [3], [4]
      ]);

      // Dual: [[0, 1], [2, 3], [4]]
      expect(calculateSpreads(5, ReaderDualPageMode.dual), [
        [0, 1], [2, 3], [4]
      ]);

      // DualCover: [[0], [1, 2], [3, 4]]
      expect(calculateSpreads(5, ReaderDualPageMode.dualCover), [
        [0], [1, 2], [3, 4]
      ]);
    });
  });

  group('ChapterFilterStatus Tests', () {
    final sampleChapters = [
      CloudChapter(id: 'c1', title: 'Chương 1', fileId: 'f1', fileType: 'cbz', uploadedAt: DateTime.now(), viewCount: 10),
      CloudChapter(id: 'c2', title: 'Chương 2', fileId: 'f2', fileType: 'cbz', uploadedAt: DateTime.now(), viewCount: 20),
      CloudChapter(id: 'c3', title: 'Chương 3', fileId: 'f3', fileType: 'cbz', uploadedAt: DateTime.now(), viewCount: 30),
      CloudChapter(id: 'c4', title: 'Chương 4', fileId: 'f4', fileType: 'cbz', uploadedAt: DateTime.now(), viewCount: 40),
    ];

    final readIds = {'c1', 'c2'};
    final downloadedIds = {'c2', 'c3'};
    final bookmarkedIds = {'c3', 'c4'};

    test('Filter All returns all chapters', () {
      final filtered = sampleChapters.where((c) => true).toList();
      expect(filtered.length, 4);
    });

    test('Filter Unread returns only unread chapters', () {
      final filtered = sampleChapters.where((c) => !readIds.contains(c.id)).toList();
      expect(filtered.map((c) => c.id).toList(), ['c3', 'c4']);
    });

    test('Filter Downloaded returns only downloaded chapters', () {
      final filtered = sampleChapters.where((c) => downloadedIds.contains(c.id)).toList();
      expect(filtered.map((c) => c.id).toList(), ['c2', 'c3']);
    });

    test('Filter Bookmarked returns only bookmarked chapters', () {
      final filtered = sampleChapters.where((c) => bookmarkedIds.contains(c.id)).toList();
      expect(filtered.map((c) => c.id).toList(), ['c3', 'c4']);
    });
  });

  group('ChapterCountFilter & GenreMatchMode Tests', () {
    test('ChapterCountFilter logic works accurately', () {
      bool matchesCount(int chapterCount, ChapterCountFilter filter) {
        if (filter == ChapterCountFilter.all) return true;
        if (filter == ChapterCountFilter.short) return chapterCount < 20;
        if (filter == ChapterCountFilter.medium) return chapterCount >= 20 && chapterCount <= 100;
        if (filter == ChapterCountFilter.long) return chapterCount > 100;
        return true;
      }

      expect(matchesCount(10, ChapterCountFilter.short), isTrue);
      expect(matchesCount(25, ChapterCountFilter.short), isFalse);

      expect(matchesCount(50, ChapterCountFilter.medium), isTrue);
      expect(matchesCount(15, ChapterCountFilter.medium), isFalse);
      expect(matchesCount(120, ChapterCountFilter.medium), isFalse);

      expect(matchesCount(150, ChapterCountFilter.long), isTrue);
      expect(matchesCount(80, ChapterCountFilter.long), isFalse);
    });

    test('GenreMatchMode AND vs OR works accurately', () {
      final mangaGenres = {'action', 'isekai', 'adventure'};

      bool matchesGenre(Set<String> mangaGenres, List<String> included, GenreMatchMode mode) {
        if (included.isEmpty) return true;
        if (mode == GenreMatchMode.and) {
          return included.every((g) => mangaGenres.contains(g));
        } else {
          return included.any((g) => mangaGenres.contains(g));
        }
      }

      // AND mode requires all
      expect(matchesGenre(mangaGenres, ['action', 'isekai'], GenreMatchMode.and), isTrue);
      expect(matchesGenre(mangaGenres, ['action', 'romance'], GenreMatchMode.and), isFalse);

      // OR mode requires at least one
      expect(matchesGenre(mangaGenres, ['action', 'romance'], GenreMatchMode.or), isTrue);
      expect(matchesGenre(mangaGenres, ['horror', 'romance'], GenreMatchMode.or), isFalse);
    });
  });

  group('ReaderBookmark Note Tests', () {
    test('ReaderBookmark correctly handles personal note in fromMap and toMap', () {
      final now = DateTime.now();
      final bookmark = ReaderBookmark(
        id: 'm1-c1-5',
        mangaId: 'm1',
        chapterId: 'c1',
        pageIndex: 5,
        note: 'Combat đỉnh cao chap 1',
        createdAt: now,
        updatedAt: now,
      );

      final map = bookmark.toMap();
      expect(map['note'], 'Combat đỉnh cao chap 1');

      final reconstructed = ReaderBookmark.fromMap(map);
      expect(reconstructed.note, 'Combat đỉnh cao chap 1');
      expect(reconstructed.pageIndex, 5);
      expect(reconstructed.mangaId, 'm1');
    });
  });
}
