import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/data/content_type.dart';
import 'package:manga_reader/data/models.dart';
import 'package:manga_reader/data/models_cloud.dart';
import 'package:manga_reader/features/library/manga_wrapped_dialog.dart';

void main() {
  group('Manga Wrapped Season Detection & Data Tests', () {
    test('Mid-Year season detection works for late June and July', () {
      // June 15
      expect(
        MangaWrappedData.getCurrentSeason(DateTime(2026, 6, 15)),
        WrappedSeason.midYear,
      );
      // June 30
      expect(
        MangaWrappedData.getCurrentSeason(DateTime(2026, 6, 30)),
        WrappedSeason.midYear,
      );
      // July 15
      expect(
        MangaWrappedData.getCurrentSeason(DateTime(2026, 7, 15)),
        WrappedSeason.midYear,
      );
      // July 31
      expect(
        MangaWrappedData.getCurrentSeason(DateTime(2026, 7, 31)),
        WrappedSeason.midYear,
      );
      expect(
        MangaWrappedData.isWrappedSeasonActive(DateTime(2026, 6, 25)),
        true,
      );
    });

    test('Year-End season detection works for late December and January', () {
      // Dec 15
      expect(
        MangaWrappedData.getCurrentSeason(DateTime(2026, 12, 15)),
        WrappedSeason.yearEnd,
      );
      // Dec 31
      expect(
        MangaWrappedData.getCurrentSeason(DateTime(2026, 12, 31)),
        WrappedSeason.yearEnd,
      );
      // Jan 1
      expect(
        MangaWrappedData.getCurrentSeason(DateTime(2027, 1, 1)),
        WrappedSeason.yearEnd,
      );
      // Jan 20
      expect(
        MangaWrappedData.getCurrentSeason(DateTime(2027, 1, 20)),
        WrappedSeason.yearEnd,
      );
      expect(
        MangaWrappedData.isWrappedSeasonActive(DateTime(2026, 12, 20)),
        true,
      );
    });

    test('Normal off-season months return currentSnapshot and inactive', () {
      // March 10
      expect(
        MangaWrappedData.getCurrentSeason(DateTime(2026, 3, 10)),
        WrappedSeason.currentSnapshot,
      );
      expect(
        MangaWrappedData.isWrappedSeasonActive(DateTime(2026, 3, 10)),
        false,
      );

      // August 29
      expect(
        MangaWrappedData.getCurrentSeason(DateTime(2026, 8, 29)),
        WrappedSeason.currentSnapshot,
      );
      expect(
        MangaWrappedData.isWrappedSeasonActive(DateTime(2026, 8, 29)),
        false,
      );

      // October 10
      expect(
        MangaWrappedData.getCurrentSeason(DateTime(2026, 10, 10)),
        WrappedSeason.currentSnapshot,
      );
      expect(
        MangaWrappedData.isWrappedSeasonActive(DateTime(2026, 10, 10)),
        false,
      );
    });

    test('MangaWrappedData.create generates top mangas and reader persona correctly', () {
      final now = DateTime.now();
      final history = [
        ReadingHistory(
          userId: 'u1',
          mangaId: 'manga_1',
          chapterId: 'c1',
          lastPageIndex: 0,
          totalPages: 20,
          updatedAt: now,
        ),
        ReadingHistory(
          userId: 'u1',
          mangaId: 'manga_1',
          chapterId: 'c2',
          lastPageIndex: 0,
          totalPages: 20,
          updatedAt: now,
        ),
        ReadingHistory(
          userId: 'u1',
          mangaId: 'manga_2',
          chapterId: 'c1',
          lastPageIndex: 0,
          totalPages: 20,
          updatedAt: now,
        ),
      ];

      final cloudMangas = <String, CloudManga>{
        'manga_1': CloudManga(
          id: 'manga_1',
          title: 'One Piece',
          coverFileId: 'cover_1',
          description: '',
          genres: ['Action', 'Adventure'],
          author: 'Oda',
          status: 'Ongoing',
          updatedAt: now,
          contentType: MangaContentType.manga,
        ),
        'manga_2': CloudManga(
          id: 'manga_2',
          title: 'Solo Leveling',
          coverFileId: 'cover_2',
          description: '',
          genres: ['Action', 'Fantasy'],
          author: 'Chugong',
          status: 'Completed',
          updatedAt: now,
          contentType: MangaContentType.manga,
        ),
      };

      final data = MangaWrappedData.create(
        totalChapters: 350,
        totalMangas: 20,
        activeDays: 45,
        currentStreak: 10,
        peakHourPeriod: 'Buổi tối (18h - 24h) 🌆',
        genreCounts: {'Action': 25, 'Adventure': 15},
        history: history,
        cloudMangas: cloudMangas,
      );

      expect(data.totalChapters, 350);
      expect(data.totalMangas, 20);
      expect(data.readerPersona, contains('Chiến Thần Cày Truyện ⚡'));
      expect(data.topMangas.length, 2);
      expect(data.topMangas[0].title, 'One Piece');
      expect(data.topMangas[0].chaptersRead, 2);
      expect(data.topMangas[0].rank, 1);
      expect(data.topMangas[1].title, 'Solo Leveling');
      expect(data.topMangas[1].chaptersRead, 1);
      expect(data.topMangas[1].rank, 2);
    });
  });
}
