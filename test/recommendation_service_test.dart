import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/data/content_type.dart';
import 'package:manga_reader/data/models_cloud.dart';
import 'package:manga_reader/services/recommendation_service.dart';

void main() {
  group('RecommendationService Tests', () {
    final catalog = [
      CloudManga(
        id: 'manga_1',
        title: 'Action Shonen Adventure',
        author: 'Oda Eiichiro',
        description: 'Pirates adventure',
        coverFileId: 'c1',
        updatedAt: DateTime.now(),
        genres: ['Action', 'Adventure', 'Shounen'],
        viewCount: 1000,
        likeCount: 200,
        contentType: MangaContentType.manga,
      ),
      CloudManga(
        id: 'manga_2',
        title: 'Ninja Action Shonen',
        author: 'Kishimoto',
        description: 'Ninja adventure',
        coverFileId: 'c2',
        updatedAt: DateTime.now(),
        genres: ['Action', 'Shounen', 'Martial Arts'],
        viewCount: 800,
        likeCount: 150,
        contentType: MangaContentType.manga,
      ),
      CloudManga(
        id: 'manga_3',
        title: 'Pure Romance Drama',
        author: 'Romance Author',
        description: 'School love story',
        coverFileId: 'c3',
        updatedAt: DateTime.now(),
        genres: ['Romance', 'School Life', 'Drama'],
        viewCount: 500,
        likeCount: 100,
        contentType: MangaContentType.manga,
      ),
      CloudManga(
        id: 'manga_4',
        title: 'Same Author One Shot',
        author: 'Oda Eiichiro',
        description: 'One shot monster story',
        coverFileId: 'c4',
        updatedAt: DateTime.now(),
        genres: ['Action', 'Fantasy'],
        viewCount: 300,
        likeCount: 50,
        contentType: MangaContentType.manga,
      ),
      CloudManga(
        id: 'novel_1',
        title: 'Cultivation Martial Novel',
        author: 'Er Gen',
        description: 'Xianxia story',
        coverFileId: 'c5',
        updatedAt: DateTime.now(),
        genres: ['Action', 'Fantasy', 'Martial Arts'],
        viewCount: 600,
        likeCount: 90,
        contentType: MangaContentType.novel,
      ),
    ];

    test('getRelatedMangas prioritizes shared genres, matching author and same contentType', () {
      final current = catalog[0]; // Action, Adventure, Shounen | Author: Oda Eiichiro
      final related = RecommendationService.instance.getRelatedMangas(
        currentManga: current,
        catalog: catalog,
        limit: 5,
      );

      expect(related, isNotEmpty);
      expect(related.any((m) => m.id == current.id), isFalse);

      // manga_4 has matching author and Action genre -> should rank very high
      // manga_2 has 2 matching genres (Action, Shounen) -> should rank very high
      final topIds = related.take(2).map((m) => m.id).toList();
      expect(topIds.contains('manga_4') || topIds.contains('manga_2'), isTrue);

      // manga_3 is pure romance -> should rank lower than action/adventure mangas
      final romanceIndex = related.indexWhere((m) => m.id == 'manga_3');
      final ninjaIndex = related.indexWhere((m) => m.id == 'manga_2');
      if (romanceIndex != -1 && ninjaIndex != -1) {
        expect(ninjaIndex < romanceIndex, isTrue);
      }
    });

    test('getRelatedMangas respects user genre affinity bonus', () {
      final current = catalog[0];
      final userGenreScores = {'shounen': 100.0, 'action': 50.0};

      final related = RecommendationService.instance.getRelatedMangas(
        currentManga: current,
        catalog: catalog,
        userGenreScores: userGenreScores,
        limit: 5,
      );

      // manga_2 has both Action and Shounen which user loves -> gets huge boost
      expect(related.first.id, equals('manga_2'));
    });

    test('getRelatedMangas handles empty genre gracefully', () {
      final noGenreManga = CloudManga(
        id: 'manga_empty',
        title: 'Empty Genre',
        author: 'Unknown',
        description: '',
        coverFileId: 'c0',
        updatedAt: DateTime.now(),
        genres: [],
        contentType: MangaContentType.manga,
      );

      final related = RecommendationService.instance.getRelatedMangas(
        currentManga: noGenreManga,
        catalog: catalog,
        limit: 3,
      );

      expect(related, isNotEmpty);
      expect(related.length, lessThanOrEqualTo(3));
    });
  });
}
