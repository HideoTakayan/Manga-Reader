import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/services/level_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LevelService Formula & Level Calculation Tests', () {
    test('Calculates Level 1 for 0 - 99 EXP', () {
      final info0 = LevelService.getLevelInfo(0);
      expect(info0.level, 1);
      expect(info0.title, 'Tân Thủ Độc Giả');
      expect(info0.expInCurrentLevel, 0);
      expect(info0.expRequiredForNextLevel, 100);
      expect(info0.progress, 0.0);
      expect(info0.isMaxLevel, isFalse);

      final info50 = LevelService.getLevelInfo(50);
      expect(info50.level, 1);
      expect(info50.expInCurrentLevel, 50);
      expect(info50.progress, 0.5);
    });

    test('Calculates Level 2 for 100 - 299 EXP (Requires 200 EXP)', () {
      final info100 = LevelService.getLevelInfo(100);
      expect(info100.level, 2);
      expect(info100.title, 'Sơ Cấp Thư Đồng');
      expect(info100.expInCurrentLevel, 0);
      expect(info100.expRequiredForNextLevel, 200);
      expect(info100.progress, 0.0);

      final info200 = LevelService.getLevelInfo(200);
      expect(info200.level, 2);
      expect(info200.expInCurrentLevel, 100);
      expect(info200.progress, 0.5);
    });

    test('Calculates Level 3 for 300 - 699 EXP (Requires 400 EXP)', () {
      final info300 = LevelService.getLevelInfo(300);
      expect(info300.level, 3);
      expect(info300.title, 'Trung Cấp Thư Sinh');
      expect(info300.expRequiredForNextLevel, 400);

      final info500 = LevelService.getLevelInfo(500);
      expect(info500.level, 3);
      expect(info500.expInCurrentLevel, 200);
      expect(info500.progress, 0.5);
    });

    test('Calculates Level 4 for 700 - 1499 EXP (Requires 800 EXP)', () {
      final info700 = LevelService.getLevelInfo(700);
      expect(info700.level, 4);
      expect(info700.title, 'Cao Cấp Học Sĩ');
      expect(info700.expRequiredForNextLevel, 800);
    });

    test('Calculates Level 5 for 1500 - 3099 EXP (Requires 1600 EXP)', () {
      final info1500 = LevelService.getLevelInfo(1500);
      expect(info1500.level, 5);
      expect(info1500.title, 'Uyên Bác Mọt Sách');
      expect(info1500.expRequiredForNextLevel, 1600);
    });

    test('Calculates Level 6 for 3100 - 6299 EXP (Requires 3200 EXP)', () {
      final info3100 = LevelService.getLevelInfo(3100);
      expect(info3100.level, 6);
      expect(info3100.title, 'Tàng Thư Lão Giả');
      expect(info3100.expRequiredForNextLevel, 3200);
    });

    test('Calculates Level 7 for 6300 - 12699 EXP (Requires 6400 EXP)', () {
      final info6300 = LevelService.getLevelInfo(6300);
      expect(info6300.level, 7);
      expect(info6300.title, 'Đại Tông Sư Luận Truyện');
      expect(info6300.expRequiredForNextLevel, 6400);
    });

    test('Calculates Level 8 for 12700 - 25499 EXP (Requires 12800 EXP)', () {
      final info12700 = LevelService.getLevelInfo(12700);
      expect(info12700.level, 8);
      expect(info12700.title, 'Thông Thiên Giáo Chủ');
      expect(info12700.expRequiredForNextLevel, 12800);
    });

    test('Calculates Level 9 for 25500 - 51099 EXP (Requires 25600 EXP)', () {
      final info25500 = LevelService.getLevelInfo(25500);
      expect(info25500.level, 9);
      expect(info25500.title, 'Chí Tôn Độc Giả');
      expect(info25500.expRequiredForNextLevel, 25600);
    });

    test('Calculates Level 10 (MAX) for 51100+ EXP', () {
      final info51100 = LevelService.getLevelInfo(51100);
      expect(info51100.level, 10);
      expect(info51100.title, 'Đại La Thần Tọa');
      expect(info51100.isMaxLevel, isTrue);
      expect(info51100.progress, 1.0);

      final infoHigh = LevelService.getLevelInfo(100000);
      expect(infoHigh.level, 10);
      expect(infoHigh.isMaxLevel, isTrue);
    });

    test('Claiming chapter EXP awards +10 EXP and prevents duplicate claims', () async {
      final service = LevelService.instance;
      await service.init();

      final initialExp = service.currentExp;
      final result1 = await service.claimChapterExp('manga_1', 'ch_1');
      expect(result1, isNotNull);
      expect(result1!.awardedExp, 10);
      expect(result1.newTotalExp, initialExp + 10);
      expect(service.isChapterClaimed('manga_1', 'ch_1'), isTrue);

      // Duplicate claim must return null and not grant extra EXP
      final resultDuplicate = await service.claimChapterExp('manga_1', 'ch_1');
      expect(resultDuplicate, isNull);
      expect(service.currentExp, initialExp + 10);

      // Another chapter must succeed
      final result2 = await service.claimChapterExp('manga_1', 'ch_2');
      expect(result2, isNotNull);
      expect(result2!.awardedExp, 10);
      expect(result2.newTotalExp, initialExp + 20);
    });

    test('Level up detection triggers correctly when passing 100 EXP threshold', () async {
      final service = LevelService.instance;

      ClaimExpResult? lastResult;
      // Claim 10 chapters (10 * 10 = 100 EXP)
      for (int i = 10; i <= 19; i++) {
        lastResult = await service.claimChapterExp('manga_test_level_up', 'ch_$i');
      }

      expect(lastResult, isNotNull);
      expect(service.currentLevelInfo.level, 2);
      expect(service.currentLevelInfo.title, 'Sơ Cấp Thư Đồng');
    });

    test('reloadForUser switches user state and maintains isolated EXP', () async {
      final service = LevelService.instance;
      await service.reloadForUser(uid: 'user_A');
      await service.claimChapterExp('manga_isolated', 'ch_1');
      expect(service.currentExp, 10);
      expect(service.isChapterClaimed('manga_isolated', 'ch_1'), isTrue);

      // Switch to user B
      await service.reloadForUser(uid: 'user_B');
      expect(service.currentExp, 0);
      expect(service.isChapterClaimed('manga_isolated', 'ch_1'), isFalse);

      // Switch back to user A
      await service.reloadForUser(uid: 'user_A');
      expect(service.currentExp, 10);
      expect(service.isChapterClaimed('manga_isolated', 'ch_1'), isTrue);
    });
  });
}
