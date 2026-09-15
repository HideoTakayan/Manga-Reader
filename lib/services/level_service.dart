import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'achievement_service.dart';

/// Thông tin chi tiết về Cấp Độ & Tiến Trình EXP
class LevelInfo {
  final int level;
  final String title;
  final int totalExp;
  final int expInCurrentLevel;
  final int expRequiredForNextLevel;
  final double progress;
  final bool isMaxLevel;
  final Color badgeColor;
  final List<Color> gradientColors;

  const LevelInfo({
    required this.level,
    required this.title,
    required this.totalExp,
    required this.expInCurrentLevel,
    required this.expRequiredForNextLevel,
    required this.progress,
    required this.isMaxLevel,
    required this.badgeColor,
    required this.gradientColors,
  });
}

/// Kết quả khi nhận EXP đọc xong chương
class ClaimExpResult {
  final int awardedExp;
  final int newTotalExp;
  final int oldLevel;
  final int newLevel;
  final bool didLevelUp;
  final String chapterId;

  const ClaimExpResult({
    required this.awardedExp,
    required this.newTotalExp,
    required this.oldLevel,
    required this.newLevel,
    required this.didLevelUp,
    required this.chapterId,
  });
}

/// Dịch vụ quản lý Hệ Thống Cấp Độ & EXP Độc Giả (Levels 1 - 10)
class LevelService extends ChangeNotifier {
  static final LevelService instance = LevelService._internal();
  LevelService._internal();

  static const int expPerChapter = 10;
  static const int maxLevel = 10;

  /// Mốc tổng EXP tích lũy tối thiểu của từng cấp [1 -> 10]
  static const List<int> levelThresholds = [
    0, // Lv 1
    100, // Lv 2 (100)
    300, // Lv 3 (+200)
    700, // Lv 4 (+400)
    1500, // Lv 5 (+800)
    3100, // Lv 6 (+1600)
    6300, // Lv 7 (+3200)
    12700, // Lv 8 (+6400)
    25500, // Lv 9 (+12800)
    51100, // Lv 10 (+25600)
  ];

  /// EXP cần nạp để từ Lv N lên Lv N+1 (Mỗi tầng gấp đôi tầng trước)
  static const List<int> expRequiredPerLevel = [
    100, // 1 -> 2
    200, // 2 -> 3
    400, // 3 -> 4
    800, // 4 -> 5
    1600, // 5 -> 6
    3200, // 6 -> 7
    6400, // 7 -> 8
    12800, // 8 -> 9
    25600, // 9 -> 10
    0, // Lv 10 MAX
  ];

  /// Danh hiệu theo từng cấp độ
  static const List<String> levelTitles = [
    'Tân Thủ Độc Giả', // Lv 1
    'Sơ Cấp Thư Đồng', // Lv 2
    'Trung Cấp Thư Sinh', // Lv 3
    'Cao Cấp Học Sĩ', // Lv 4
    'Uyên Bác Mọt Sách', // Lv 5
    'Tàng Thư Lão Giả', // Lv 6
    'Đại Tông Sư Luận Truyện', // Lv 7
    'Thông Thiên Giáo Chủ', // Lv 8
    'Chí Tôn Độc Giả', // Lv 9
    'Đại La Thần Tọa', // Lv 10 (MAX)
  ];

  static String _getClaimedChaptersKey(String? uid) =>
      'exp_claimed_chapters_${uid ?? "unknown"}';
  static String _getLocalExpKey(String? uid) =>
      'user_local_exp_${uid ?? "unknown"}';

  final Set<String> _claimedChapterKeys = {};
  int _currentExp = 0;
  String? _activeUid;
  bool _isInitialized = false;

  final _levelUpStreamController = StreamController<ClaimExpResult>.broadcast();
  Stream<ClaimExpResult> get onLevelUp => _levelUpStreamController.stream;
  StreamSubscription? _authSubscription;

  int get currentExp => _currentExp;
  LevelInfo get currentLevelInfo => getLevelInfo(_currentExp);

  /// Khởi tạo trạng thái EXP và danh sách chapter đã nhận
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Tự động reload khi người dùng đăng nhập hoặc đăng xuất
    try {
      await _authSubscription?.cancel();
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
        reloadForUser(uid: user?.uid);
      });
    } catch (_) {}

    String? initialUid;
    try {
      initialUid = FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {}

    await reloadForUser(uid: initialUid);
  }

  /// Nạp dữ liệu EXP và chương đã nhận cho tài khoản chỉ định
  Future<void> reloadForUser({String? uid}) async {
    _claimedChapterKeys.clear();
    _currentExp = 0;

    String? effectiveUid = uid;
    if (effectiveUid == null) {
      try {
        effectiveUid = FirebaseAuth.instance.currentUser?.uid;
      } catch (_) {}
    }
    _activeUid = effectiveUid;

    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_getClaimedChaptersKey(effectiveUid)) ?? [];
      _claimedChapterKeys.addAll(list);
      _currentExp = prefs.getInt(_getLocalExpKey(effectiveUid)) ?? 0;

      // Đồng bộ từ Firestore nếu đã đăng nhập
      if (effectiveUid != null) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(effectiveUid)
              .get();
          if (doc.exists && doc.data() != null) {
            final data = doc.data()!;
            final cloudExp = (data['exp'] as num?)?.toInt() ?? 0;

            // Migration: nếu user cũ chưa có các field leaderboard → patch 0
            final needsLeaderboardPatch =
                !data.containsKey('exp') ||
                !data.containsKey('level') ||
                !data.containsKey('claimedChaptersCount');
            if (needsLeaderboardPatch) {
              // Cap local EXP to prevent inflated SharedPreferences values
              // being promoted to cloud. Max legitimate EXP = Lv10 threshold +
              // one full level's worth (51100 + 25600).
              const maxLocalMigrationExp = 76700;
              final safeExp = _currentExp.clamp(0, maxLocalMigrationExp);
              final info = getLevelInfo(safeExp);
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(effectiveUid)
                  .set({
                'exp': safeExp,
                'level': info.level,
                'title': info.title,
                'claimedChaptersCount':
                    _claimedChapterKeys.length.clamp(0, 10000),
              }, SetOptions(merge: true));
            }

            if (cloudExp > _currentExp) {
              _currentExp = cloudExp;
              await prefs.setInt(_getLocalExpKey(effectiveUid), _currentExp);
            } else if (_currentExp > cloudExp) {
              // Only push local EXP to cloud if the delta is within a safe
              // bound. The Firestore rule also enforces <=1000, but we guard
              // client-side as well to avoid unnecessary permission-denied
              // errors on first sync after extended offline sessions.
              const maxSyncDelta = 1000; // = expPerChapter * 100 chapters
              if (_currentExp - cloudExp <= maxSyncDelta) {
                final info = getLevelInfo(_currentExp);
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(effectiveUid)
                    .set({
                  'exp': _currentExp,
                  'level': info.level,
                  'title': info.title,
                }, SetOptions(merge: true));
              } else {
                // Delta too large: trust cloud to avoid cheating.
                _currentExp = cloudExp;
                await prefs.setInt(
                    _getLocalExpKey(effectiveUid), _currentExp);
              }
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Tính toán thông tin cấp độ từ tổng EXP
  static LevelInfo getLevelInfo(int exp) {
    final safeExp = exp < 0 ? 0 : exp;
    int level = 1;

    for (int i = levelThresholds.length - 1; i >= 0; i--) {
      if (safeExp >= levelThresholds[i]) {
        level = i + 1;
        break;
      }
    }

    final isMax = level >= maxLevel;
    final title = levelTitles[(level - 1).clamp(0, levelTitles.length - 1)];

    int expInCurrentLevel = 0;
    int expRequired = 0;
    double progress = 1.0;

    if (!isMax) {
      final currentThreshold = levelThresholds[level - 1];
      expRequired = expRequiredPerLevel[level - 1];
      expInCurrentLevel = safeExp - currentThreshold;
      progress = expRequired > 0
          ? (expInCurrentLevel / expRequired).clamp(0.0, 1.0)
          : 1.0;
    } else {
      expInCurrentLevel = safeExp - levelThresholds[maxLevel - 1];
      expRequired = 0;
      progress = 1.0;
    }

    final colors = _getColorsForLevel(level);

    return LevelInfo(
      level: level,
      title: title,
      totalExp: safeExp,
      expInCurrentLevel: expInCurrentLevel,
      expRequiredForNextLevel: expRequired,
      progress: progress,
      isMaxLevel: isMax,
      badgeColor: colors.first,
      gradientColors: colors,
    );
  }

  static List<Color> _getColorsForLevel(int level) {
    switch (level) {
      case 1:
        return const [Color(0xFF8D6E63), Color(0xFF6D4C41)]; // Bronze
      case 2:
        return const [Color(0xFF78909C), Color(0xFF455A64)]; // Silver
      case 3:
        return const [Color(0xFF4CAF50), Color(0xFF2E7D32)]; // Emerald
      case 4:
        return const [Color(0xFF29B6F6), Color(0xFF0288D1)]; // Sky Blue
      case 5:
        return const [Color(0xFFAB47BC), Color(0xFF7B1FA2)]; // Royal Purple
      case 6:
        return const [Color(0xFFFFB300), Color(0xFFFF8F00)]; // Amber Gold
      case 7:
        return const [Color(0xFFFF7043), Color(0xFFD84315)]; // Flame Red
      case 8:
        return const [Color(0xFFEC407A), Color(0xFFC2185B)]; // Ruby Pink
      case 9:
        return const [Color(0xFFFFD700), Color(0xFFFFA000)]; // Radiant Gold
      case 10:
      default:
        return const [
          Color(0xFFFF5252),
          Color(0xFFFFD700),
          Color(0xFF7C4DFF),
          Color(0xFF00E5FF)
        ]; // Cosmic Prismatic
    }
  }

  /// Kiểm tra xem chapter đã nhận EXP chưa
  bool isChapterClaimed(String mangaId, String chapterId) {
    final key = '${mangaId}_$chapterId';
    return _claimedChapterKeys.contains(key);
  }

  /// Nhận 10 EXP khi đọc xong 1 chapter truyện (chống spam)
  Future<ClaimExpResult?> claimChapterExp(
    String mangaId,
    String chapterId, {
    String? chapterTitle,
    List<String>? genres,
  }) async {
    final key = '${mangaId}_$chapterId';
    if (_claimedChapterKeys.contains(key)) {
      return null; // Đã nhận trước đó
    }

    _claimedChapterKeys.add(key);

    final oldLevel = getLevelInfo(_currentExp).level;
    _currentExp += expPerChapter;
    final newLevelInfo = getLevelInfo(_currentExp);
    final newLevel = newLevelInfo.level;
    final didLevelUp = newLevel > oldLevel;
    unawaited(AchievementService.instance.recordChapterRead(mangaId: mangaId, genres: genres));

    // Lưu vào SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      // Cap at 2000 entries to prevent unbounded SharedPreferences XML growth.
      // EXP integrity is maintained server-side via claimedChaptersCount.
      const maxKeys = 2000;
      List<String> keysToSave = _claimedChapterKeys.toList();
      if (keysToSave.length > maxKeys) {
        keysToSave = keysToSave.sublist(keysToSave.length - maxKeys);
        _claimedChapterKeys
          ..clear()
          ..addAll(keysToSave);
      }
      await prefs.setStringList(
        _getClaimedChaptersKey(_activeUid),
        keysToSave,
      );
      await prefs.setInt(_getLocalExpKey(_activeUid), _currentExp);
    } catch (_) {}

    // Lưu lên Firestore
    try {
      final uid = _activeUid;
      if (uid != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({
          'exp': FieldValue.increment(expPerChapter),
          'claimedChaptersCount': FieldValue.increment(1),
          'level': newLevel,
          'title': newLevelInfo.title,
        }, SetOptions(merge: true));
      }
    } catch (_) {}

    final result = ClaimExpResult(
      awardedExp: expPerChapter,
      newTotalExp: _currentExp,
      oldLevel: oldLevel,
      newLevel: newLevel,
      didLevelUp: didLevelUp,
      chapterId: chapterId,
    );

    if (didLevelUp) {
      _levelUpStreamController.add(result);
    }

    notifyListeners();
    return result;
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _levelUpStreamController.close();
    super.dispose();
  }
}
