import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AchievementCategory {
  all,
  reading,
  streak,
  diversity,
  special,
  community,
}

extension AchievementCategoryExt on AchievementCategory {
  String get label {
    switch (this) {
      case AchievementCategory.all:
        return 'Tất cả';
      case AchievementCategory.reading:
        return 'Đọc truyện';
      case AchievementCategory.streak:
        return 'Chuỗi ngày';
      case AchievementCategory.diversity:
        return 'Thể loại';
      case AchievementCategory.special:
        return 'Đặc biệt';
      case AchievementCategory.community:
        return 'Cộng đồng';
    }
  }
}

class AchievementBadge {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final AchievementCategory category;
  final int maxProgress;
  final int progress;
  final bool isUnlocked;
  final DateTime? unlockedAt;

  const AchievementBadge({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.category,
    required this.maxProgress,
    this.progress = 0,
    this.isUnlocked = false,
    this.unlockedAt,
  });

  AchievementBadge copyWith({
    int? progress,
    bool? isUnlocked,
    DateTime? unlockedAt,
  }) {
    return AchievementBadge(
      id: id,
      title: title,
      description: description,
      icon: icon,
      color: color,
      category: category,
      maxProgress: maxProgress,
      progress: progress ?? this.progress,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      unlockedAt: unlockedAt ?? this.unlockedAt,
    );
  }
}

class AchievementService {
  static final AchievementService instance = AchievementService._internal();
  AchievementService._internal();

  static const String _prefUnlockedKey = 'achievements_unlocked_data';
  static const String _prefChaptersCountKey = 'achievements_chapters_read_count';
  static const String _prefGenresKey = 'achievements_unique_genres';
  static const String _prefCommunityCountKey = 'achievements_community_count';

  // 18 Thành tựu phong cách Steam Gaming
  static final List<AchievementBadge> _predefinedBadges = [
    // 1. NHÓM ĐỌC TRUYỆN (READING PROGRESS)
    const AchievementBadge(
      id: 'first_step',
      title: 'Bước Đầu Tiên',
      description: 'Đọc chương truyện tranh hoặc tiểu thuyết đầu tiên',
      icon: Icons.flag_rounded,
      color: Colors.greenAccent,
      category: AchievementCategory.reading,
      maxProgress: 1,
    ),
    const AchievementBadge(
      id: 'novice_reader_10',
      title: 'Độc Giả Tập Sự',
      description: 'Tích lũy đọc xong 10 chương truyện',
      icon: Icons.auto_stories_rounded,
      color: Colors.lightBlueAccent,
      category: AchievementCategory.reading,
      maxProgress: 10,
    ),
    const AchievementBadge(
      id: 'bookworm_50',
      title: 'Mọt Sách Cần Cù',
      description: 'Tích lũy đọc xong 50 chương truyện',
      icon: Icons.menu_book_rounded,
      color: Colors.blueAccent,
      category: AchievementCategory.reading,
      maxProgress: 50,
    ),
    const AchievementBadge(
      id: 'diligent_reader_100',
      title: 'Độc Giả Chuyên Cần',
      description: 'Tích lũy đọc xong 100 chương truyện',
      icon: Icons.import_contacts_rounded,
      color: Colors.cyanAccent,
      category: AchievementCategory.reading,
      maxProgress: 100,
    ),
    const AchievementBadge(
      id: 'grand_scholar_300',
      title: 'Đại Học Giả',
      description: 'Tích lũy đọc xong 300 chương truyện',
      icon: Icons.school_rounded,
      color: Colors.amberAccent,
      category: AchievementCategory.reading,
      maxProgress: 300,
    ),
    const AchievementBadge(
      id: 'library_legend_1000',
      title: 'Huyền Thoại Tàng Thư',
      description: 'Chinh phục mốc tối thượng 1.000 chương truyện',
      icon: Icons.workspace_premium_rounded,
      color: Color(0xFFFFD700),
      category: AchievementCategory.reading,
      maxProgress: 1000,
    ),

    // 2. NHÓM CHUỖI ĐỌC (STREAK)
    const AchievementBadge(
      id: 'streak_spark_3',
      title: 'Đốm Lửa Khởi Đầu',
      description: 'Duy trì chuỗi đọc truyện liên tục 3 ngày',
      icon: Icons.whatshot_rounded,
      color: Colors.orangeAccent,
      category: AchievementCategory.streak,
      maxProgress: 3,
    ),
    const AchievementBadge(
      id: 'streak_master_7',
      title: 'Ngọn Lửa Bền Bỉ',
      description: 'Duy trì chuỗi đọc truyện liên tục 7 ngày',
      icon: Icons.local_fire_department_rounded,
      color: Colors.deepOrangeAccent,
      category: AchievementCategory.streak,
      maxProgress: 7,
    ),
    const AchievementBadge(
      id: 'streak_inferno_14',
      title: 'Cuồng Nhiệt Hừng Hực',
      description: 'Duy trì chuỗi đọc truyện liên tục 14 ngày',
      icon: Icons.fireplace_rounded,
      color: Colors.redAccent,
      category: AchievementCategory.streak,
      maxProgress: 14,
    ),
    const AchievementBadge(
      id: 'streak_eternal_30',
      title: 'Hỏa Thần Bất Diệt',
      description: 'Duy trì chuỗi đọc truyện huyền thoại 30 ngày',
      icon: Icons.electric_bolt_rounded,
      color: Colors.purpleAccent,
      category: AchievementCategory.streak,
      maxProgress: 30,
    ),

    // 3. NHÓM ĐA DẠNG THỂ LOẠI (DIVERSITY)
    const AchievementBadge(
      id: 'genre_dabbler_3',
      title: 'Kẻ Thử Thách',
      description: 'Khám phá và đọc ít nhất 3 thể loại truyện khác nhau',
      icon: Icons.category_rounded,
      color: Colors.tealAccent,
      category: AchievementCategory.diversity,
      maxProgress: 3,
    ),
    const AchievementBadge(
      id: 'genre_explorer_8',
      title: 'Nhà Thám Hiểm',
      description: 'Khám phá và đọc ít nhất 8 thể loại truyện khác nhau',
      icon: Icons.explore_rounded,
      color: Colors.lightGreenAccent,
      category: AchievementCategory.diversity,
      maxProgress: 8,
    ),
    const AchievementBadge(
      id: 'genre_polymath_15',
      title: 'Bách Khoa Toàn Thư',
      description: 'Chinh phục hơn 15 thể loại truyện đa dạng',
      icon: Icons.public_rounded,
      color: Colors.indigoAccent,
      category: AchievementCategory.diversity,
      maxProgress: 15,
    ),

    // 4. NHÓM ĐẶC BIỆT & THỜI GIAN (SPECIAL)
    const AchievementBadge(
      id: 'night_owl',
      title: 'Cú Đêm Chăm Chỉ',
      description: 'Đọc truyện trong khoảng thời gian từ 0:00 đến 5:00 sáng',
      icon: Icons.nightlight_round,
      color: Color(0xFFBA68C8),
      category: AchievementCategory.special,
      maxProgress: 1,
    ),
    const AchievementBadge(
      id: 'early_bird',
      title: 'Đón Ánh Bình Minh',
      description: 'Đọc truyện vào sáng sớm trong khung giờ 5:00 đến 7:00',
      icon: Icons.wb_sunny_rounded,
      color: Colors.amber,
      category: AchievementCategory.special,
      maxProgress: 1,
    ),
    const AchievementBadge(
      id: 'midnight_crawler',
      title: 'Thợ Cày Đêm Khuya',
      description: 'Đắm chìm vào truyện trong khung giờ vàng 22:00 - 24:00',
      icon: Icons.bedtime_rounded,
      color: Colors.deepPurpleAccent,
      category: AchievementCategory.special,
      maxProgress: 1,
    ),

    // 5. NHÓM CỘNG ĐỒNG & DIỄN ĐÀN (COMMUNITY)
    const AchievementBadge(
      id: 'community_voice',
      title: 'Tiếng Nói Cộng Đồng',
      description: 'Tham gia bình luận, chia sẻ hoặc đăng bài trong Diễn đàn',
      icon: Icons.forum_rounded,
      color: Colors.pinkAccent,
      category: AchievementCategory.community,
      maxProgress: 1,
    ),
    const AchievementBadge(
      id: 'community_contributor',
      title: 'Chuyên Gia Đóng Góp',
      description: 'Đóng góp 3 lần thuật ngữ từ điển dịch thuật hoặc bài viết',
      icon: Icons.handshake_rounded,
      color: Colors.limeAccent,
      category: AchievementCategory.community,
      maxProgress: 3,
    ),
  ];

  Map<String, DateTime> _unlockedMap = {};
  int _totalChaptersRead = 0;
  Set<String> _genresRead = {};
  int _currentStreak = 0;
  int _communityActionsCount = 0;
  bool _isLoaded = false;
  Future<void>? _initFuture;

  Future<void> init() async {
    if (_isLoaded) return;
    _initFuture ??= _doInit();
    await _initFuture;
  }

  /// Nạp lại dữ liệu từ SharedPreferences
  Future<void> reload() async {
    _isLoaded = false;
    _initFuture = null;
    await init();
  }

  Future<void> _doInit() async {
    final prefs = await SharedPreferences.getInstance();

    _totalChaptersRead = prefs.getInt(_prefChaptersCountKey) ?? 0;
    _communityActionsCount = prefs.getInt(_prefCommunityCountKey) ?? 0;
    _genresRead = (prefs.getStringList(_prefGenresKey) ?? <String>[]).toSet();

    final rawJson = prefs.getString(_prefUnlockedKey);
    if (rawJson != null) {
      try {
        final map = jsonDecode(rawJson) as Map<String, dynamic>;
        _unlockedMap = map.map(
          (k, v) => MapEntry(k, DateTime.fromMillisecondsSinceEpoch(v as int)),
        );
      } catch (_) {}
    }
    _isLoaded = true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefChaptersCountKey, _totalChaptersRead);
    await prefs.setInt(_prefCommunityCountKey, _communityActionsCount);
    await prefs.setStringList(_prefGenresKey, _genresRead.toList());

    final map = _unlockedMap.map(
      (k, v) => MapEntry(k, v.millisecondsSinceEpoch),
    );
    await prefs.setString(_prefUnlockedKey, jsonEncode(map));
  }

  /// Ghi nhận 1 chương vừa đọc xong
  Future<void> recordChapterRead({
    required String mangaId,
    List<String>? genres,
  }) async {
    await init();
    _totalChaptersRead++;

    if (genres != null && genres.isNotEmpty) {
      for (final g in genres) {
        if (g.trim().isNotEmpty) _genresRead.add(g.trim().toLowerCase());
      }
    }

    // Kiểm tra thời gian đọc đặc biệt
    final hour = DateTime.now().hour;
    if (hour >= 0 && hour < 5) {
      _unlock('night_owl');
    } else if (hour >= 5 && hour < 7) {
      _unlock('early_bird');
    } else if (hour >= 22 && hour < 24) {
      _unlock('midnight_crawler');
    }

    // Mốc số lượng chương
    if (_totalChaptersRead >= 1) _unlock('first_step');
    if (_totalChaptersRead >= 10) _unlock('novice_reader_10');
    if (_totalChaptersRead >= 50) _unlock('bookworm_50');
    if (_totalChaptersRead >= 100) _unlock('diligent_reader_100');
    if (_totalChaptersRead >= 300) _unlock('grand_scholar_300');
    if (_totalChaptersRead >= 1000) _unlock('library_legend_1000');

    // Mốc thể loại
    if (_genresRead.length >= 3) _unlock('genre_dabbler_3');
    if (_genresRead.length >= 8) _unlock('genre_explorer_8');
    if (_genresRead.length >= 15) _unlock('genre_polymath_15');

    await _save();
  }

  /// Ghi nhận chuỗi ngày đọc streak
  Future<void> recordStreak(int streak) async {
    await init();
    _currentStreak = streak;
    if (streak >= 3) _unlock('streak_spark_3');
    if (streak >= 7) _unlock('streak_master_7');
    if (streak >= 14) _unlock('streak_inferno_14');
    if (streak >= 30) _unlock('streak_eternal_30');
    await _save();
  }

  /// Ghi nhận tương tác cộng đồng
  Future<void> recordCommunityAction() async {
    await init();
    _communityActionsCount++;
    _unlock('community_voice');
    if (_communityActionsCount >= 3) {
      _unlock('community_contributor');
    }
    await _save();
  }

  void _unlock(String id) {
    if (!_unlockedMap.containsKey(id)) {
      _unlockedMap[id] = DateTime.now();
    }
  }

  /// Lấy danh sách đầy đủ 18 huy hiệu cùng tiến trình hiện tại
  List<AchievementBadge> getBadges({AchievementCategory category = AchievementCategory.all}) {
    final list = _predefinedBadges.map((badge) {
      final isUnlocked = _unlockedMap.containsKey(badge.id);
      final unlockedAt = _unlockedMap[badge.id];
      int progress = 0;

      switch (badge.id) {
        case 'first_step':
          progress = _totalChaptersRead.clamp(0, 1);
          break;
        case 'novice_reader_10':
          progress = _totalChaptersRead.clamp(0, 10);
          break;
        case 'bookworm_50':
          progress = _totalChaptersRead.clamp(0, 50);
          break;
        case 'diligent_reader_100':
          progress = _totalChaptersRead.clamp(0, 100);
          break;
        case 'grand_scholar_300':
          progress = _totalChaptersRead.clamp(0, 300);
          break;
        case 'library_legend_1000':
          progress = _totalChaptersRead.clamp(0, 1000);
          break;

        case 'streak_spark_3':
          progress = _currentStreak.clamp(0, 3);
          break;
        case 'streak_master_7':
          progress = _currentStreak.clamp(0, 7);
          break;
        case 'streak_inferno_14':
          progress = _currentStreak.clamp(0, 14);
          break;
        case 'streak_eternal_30':
          progress = _currentStreak.clamp(0, 30);
          break;

        case 'genre_dabbler_3':
          progress = _genresRead.length.clamp(0, 3);
          break;
        case 'genre_explorer_8':
          progress = _genresRead.length.clamp(0, 8);
          break;
        case 'genre_polymath_15':
          progress = _genresRead.length.clamp(0, 15);
          break;

        case 'night_owl':
        case 'early_bird':
        case 'midnight_crawler':
          progress = isUnlocked ? 1 : 0;
          break;

        case 'community_voice':
          progress = _communityActionsCount.clamp(0, 1);
          break;
        case 'community_contributor':
          progress = _communityActionsCount.clamp(0, 3);
          break;
      }

      return badge.copyWith(
        progress: progress,
        isUnlocked: isUnlocked,
        unlockedAt: unlockedAt,
      );
    }).toList();

    if (category == AchievementCategory.all) return list;
    return list.where((b) => b.category == category).toList();
  }

  int getUnlockedCount() => _unlockedMap.length;
  int getTotalCount() => _predefinedBadges.length;

  /// Hiển thị Bảng Vinh Danh Thành Tựu Phong Cách Steam
  static void showAchievementShowcase(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const _AchievementShowcaseSheet(),
    );
  }
}

class _AchievementShowcaseSheet extends StatefulWidget {
  const _AchievementShowcaseSheet();

  @override
  State<_AchievementShowcaseSheet> createState() => _AchievementShowcaseSheetState();
}

class _AchievementShowcaseSheetState extends State<_AchievementShowcaseSheet> {
  AchievementCategory _selectedCategory = AchievementCategory.all;

  @override
  Widget build(BuildContext context) {
    final service = AchievementService.instance;
    final badges = service.getBadges(category: _selectedCategory);
    final unlockedCount = service.getUnlockedCount();
    final totalCount = service.getTotalCount();
    final percent = totalCount > 0 ? (unlockedCount / totalCount) : 0.0;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Title Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.amber, Colors.deepOrangeAccent],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.military_tech_rounded,
                            color: Colors.black,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Thành Tựu Độc Giả',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Đã mở khóa $unlockedCount / $totalCount thành tựu (${(percent * 100).toStringAsFixed(0)}%)',
                              style: const TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 6,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.amberAccent),
                  ),
                ),
                const SizedBox(height: 14),

                // Category Chips (Steam style)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: AchievementCategory.values.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(cat.label, style: const TextStyle(fontSize: 11.5)),
                          selected: isSelected,
                          selectedColor: Colors.amberAccent,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          visualDensity: VisualDensity.compact,
                          onSelected: (val) {
                            if (val) setState(() => _selectedCategory = cat);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),

                // Grid of Badges
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: badges.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, index) {
                      final badge = badges[index];
                      final isUnlocked = badge.isUnlocked;

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isUnlocked
                              ? badge.color.withValues(alpha: 0.08)
                              : Colors.white.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isUnlocked
                                ? badge.color.withValues(alpha: 0.45)
                                : Colors.white10,
                            width: isUnlocked ? 1.3 : 1.0,
                          ),
                          boxShadow: isUnlocked
                              ? [
                                  BoxShadow(
                                    color: badge.color.withValues(alpha: 0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          children: [
                            // Badge Icon with Glowing Frame
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isUnlocked
                                    ? badge.color.withValues(alpha: 0.22)
                                    : Colors.white.withValues(alpha: 0.05),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isUnlocked ? badge.color : Colors.white24,
                                  width: isUnlocked ? 1.5 : 1.0,
                                ),
                              ),
                              child: Icon(
                                badge.icon,
                                color: isUnlocked ? badge.color : Colors.white24,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Badge Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          badge.title,
                                          style: TextStyle(
                                            color: isUnlocked ? Colors.white : Colors.white54,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isUnlocked)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: Colors.greenAccent.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 12),
                                              SizedBox(width: 3),
                                              Text(
                                                'ĐÃ MỞ',
                                                style: TextStyle(
                                                  color: Colors.greenAccent,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    badge.description,
                                    style: TextStyle(
                                      color: isUnlocked ? Colors.white70 : Colors.white38,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  // Progress indicator
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(3),
                                          child: LinearProgressIndicator(
                                            value: badge.maxProgress > 0
                                                ? (badge.progress / badge.maxProgress).clamp(0.0, 1.0)
                                                : 0.0,
                                            minHeight: 4,
                                            backgroundColor: Colors.white10,
                                            valueColor: AlwaysStoppedAnimation<Color>(
                                              isUnlocked ? badge.color : Colors.white30,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${badge.progress}/${badge.maxProgress}',
                                        style: TextStyle(
                                          color: isUnlocked ? badge.color : Colors.white38,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
