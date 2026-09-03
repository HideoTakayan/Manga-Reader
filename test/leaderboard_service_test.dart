import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/features/forum/services/leaderboard_service.dart';
import 'package:manga_reader/services/level_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LeaderboardUser Model Tests', () {
    test('LeaderboardUser holds correct values and calculates fallback title/level', () {
      final user = LeaderboardUser(
        uid: 'user_123',
        name: 'Độc Giả Bá Đạo',
        avatarUrl: 'https://example.com/avatar.png',
        exp: 750,
        level: 4,
        title: 'Cao Cấp Học Sĩ',
        claimedChaptersCount: 75,
        rank: 1,
      );

      expect(user.uid, 'user_123');
      expect(user.name, 'Độc Giả Bá Đạo');
      expect(user.exp, 750);
      expect(user.level, 4);
      expect(user.title, 'Cao Cấp Học Sĩ');
      expect(user.claimedChaptersCount, 75);
      expect(user.rank, 1);
    });

    test('Level calculation matches LevelService exponential progression', () {
      const exp1 = 0;
      expect(LevelService.getLevelInfo(exp1).level, 1);

      const exp2 = 100;
      expect(LevelService.getLevelInfo(exp2).level, 2);

      const exp3 = 300;
      expect(LevelService.getLevelInfo(exp3).level, 3);

      const exp4 = 700;
      expect(LevelService.getLevelInfo(exp4).level, 4);

      const exp10 = 51100;
      expect(LevelService.getLevelInfo(exp10).level, 10);
      expect(LevelService.getLevelInfo(exp10).isMaxLevel, isTrue);
    });
  });
}
