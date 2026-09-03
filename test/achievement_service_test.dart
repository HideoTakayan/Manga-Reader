import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manga_reader/services/achievement_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AchievementService & Badges Tests', () {
    test('Initialization returns 18 standard badges in locked state', () async {
      final service = AchievementService.instance;
      await service.init();

      final badges = service.getBadges();
      expect(badges.length, 18);
      expect(service.getUnlockedCount(), 0);
      expect(service.getTotalCount(), 18);

      for (final badge in badges) {
        expect(badge.isUnlocked, false);
      }
    });

    test('Reading first chapter unlocks First Step badge', () async {
      final service = AchievementService.instance;
      await service.recordChapterRead(mangaId: 'comic_1', genres: ['Action', 'Fantasy']);

      final badges = service.getBadges();
      final firstStep = badges.firstWhere((b) => b.id == 'first_step');
      expect(firstStep.isUnlocked, true);
      expect(firstStep.progress, 1);
      expect(service.getUnlockedCount(), greaterThanOrEqualTo(1));
    });

    test('Reading 50 chapters unlocks Bookworm badge and increments progress', () async {
      final service = AchievementService.instance;
      for (int i = 0; i < 50; i++) {
        await service.recordChapterRead(mangaId: 'manga_$i');
      }

      final badges = service.getBadges();
      final bookworm = badges.firstWhere((b) => b.id == 'bookworm_50');
      expect(bookworm.isUnlocked, true);
      expect(bookworm.progress, 50);
    });

    test('Reading 8 unique genres unlocks Genre Explorer badge', () async {
      final service = AchievementService.instance;
      final genresList = [
        ['Action'],
        ['Romance'],
        ['Comedy'],
        ['Drama'],
        ['Fantasy'],
        ['Isekai'],
        ['Sci-Fi'],
        ['Mystery'],
      ];

      for (int i = 0; i < genresList.length; i++) {
        await service.recordChapterRead(mangaId: 'genre_manga_$i', genres: genresList[i]);
      }

      final badges = service.getBadges();
      final explorer = badges.firstWhere((b) => b.id == 'genre_explorer_8');
      expect(explorer.isUnlocked, true);
      expect(explorer.progress, 8);
    });

    test('Recording 7-day streak unlocks Streak Master badge', () async {
      final service = AchievementService.instance;
      await service.recordStreak(7);

      final badges = service.getBadges();
      final streak = badges.firstWhere((b) => b.id == 'streak_master_7');
      expect(streak.isUnlocked, true);
      expect(streak.progress, 7);
    });

    test('Recording community interaction unlocks Community Voice badge', () async {
      final service = AchievementService.instance;
      await service.recordCommunityAction();

      final badges = service.getBadges();
      final voice = badges.firstWhere((b) => b.id == 'community_voice');
      expect(voice.isUnlocked, true);
      expect(voice.progress, 1);
    });
  });
}
