import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../data/database_helper.dart';
import '../../data/models.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../../services/achievement_service.dart';
import '../../services/auth_service.dart';
import '../../services/novel_service.dart';
import '../catalog/catalog_cache_service.dart';
import 'manga_wrapped_dialog.dart';

class ReadingAnalyticsPage extends StatefulWidget {
  const ReadingAnalyticsPage({super.key});

  @override
  State<ReadingAnalyticsPage> createState() => _ReadingAnalyticsPageState();
}

class _ReadingAnalyticsPageState extends State<ReadingAnalyticsPage> {
  bool _isLoading = true;
  bool _isMonthView = false;
  int _totalReadMangas = 0;
  int _activeDays = 0;
  int _chaptersRead = 0;
  int _currentStreak = 0;
  double _avgChaptersPerDay = 0.0;
  String _peakHourPeriod = 'Buổi tối (18h - 24h) 🌆';
  List<int> _weeklyCounts = List.filled(7, 0);
  List<int> _monthlyCounts = List.filled(30, 0);
  Map<String, int> _genreCounts = const {};
  List<_RecentReadItem> _recentReads = const [];
  List<ReadingHistory> _history = const [];
  Map<String, CloudManga> _cloudMangas = const {};
  Map<String, int> _mangaReadCounts = const {}; // Số chapter unique đã đọc mỗi manga (dùng cho Wrapped ranking)

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final safeUid = AuthService.safeUid;
    final userIds = <String>{
      safeUid,
      if (authUid != null) authUid,
    }.toList();

    final historyByManga = <String, ReadingHistory>{};
    final activityByKey = <String, ReadingActivity>{};

    for (final userId in userIds) {
      final history = await DatabaseHelper.instance.getHistory(userId);
      for (final item in history) {
        final current = historyByManga[item.mangaId];
        if (current == null || item.updatedAt.isAfter(current.updatedAt)) {
          historyByManga[item.mangaId] = item;
        }
      }

      final activities = await DatabaseHelper.instance.getReadingActivity(
        userId,
      );
      for (final item in activities) {
        final key = '${item.mangaId}|${item.chapterId}|${item.dateKey}';
        final current = activityByKey[key];
        if (current == null || item.readAt.isAfter(current.readAt)) {
          activityByKey[key] = item;
        }
      }
    }

    final activities = activityByKey.values.toList();
    final history = historyByManga.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final mangaIds = <String>{
      ...history.map((item) => item.mangaId),
      ...activities.map((item) => item.mangaId),
    };

    // Tải danh mục truyện từ cloud để fallback nếu DB cục bộ không có
    Map<String, CloudManga> cloudMangas = {};
    try {
      final cloudMangasList = await DriveService.instance.getMangas();
      cloudMangas = {for (final m in cloudMangasList) m.id: m};
    } catch (_) {
      try {
        final cached = await CatalogCacheService.instance.getCachedCatalog();
        cloudMangas = {for (final m in cached) m.id: m};
      } catch (_) {}
    }

    final mangaInfoById = await _loadMangaInfo(mangaIds, cloudMangas);
    final countableMangaIds = mangaInfoById.entries
        .where((entry) => entry.value.hasCatalogMetadata)
        .map((entry) => entry.key)
        .toSet();

    final now = DateTime.now();
    final weekStart = _startOfWeek(now);
    final monthStart = _dateOnly(now).subtract(const Duration(days: 29));
    final weeklyCounts = List.filled(7, 0);
    final monthlyCounts = List.filled(30, 0);
    final hourBuckets = List.filled(4, 0); // 0: Đêm, 1: Sáng, 2: Chiều, 3: Tối
    final activeDateKeys = <String>{};
    final chapterKeys = <String>{};

    void addReadDate(DateTime readDay, {DateTime? fullTimestamp}) {
      final normalizedDay = _dateOnly(readDay);
      final daysFromWeekStart = normalizedDay.difference(weekStart).inDays;
      if (daysFromWeekStart >= 0 && daysFromWeekStart < 7) {
        weeklyCounts[daysFromWeekStart]++;
      }
      final daysFromMonthStart = normalizedDay.difference(monthStart).inDays;
      if (daysFromMonthStart >= 0 && daysFromMonthStart < 30) {
        monthlyCounts[daysFromMonthStart]++;
      }
      if (fullTimestamp != null) {
        final hour = fullTimestamp.hour;
        if (hour >= 0 && hour < 6) {
          hourBuckets[0]++;
        } else if (hour >= 6 && hour < 12) {
          hourBuckets[1]++;
        } else if (hour >= 12 && hour < 18) {
          hourBuckets[2]++;
        } else {
          hourBuckets[3]++;
        }
      }
    }

    for (final item in activities) {
      if (!countableMangaIds.contains(item.mangaId)) continue;
      activeDateKeys.add(item.dateKey);
      chapterKeys.add('${item.mangaId}|${item.chapterId}');
      addReadDate(_parseDateKey(item.dateKey), fullTimestamp: item.readAt);
    }

    for (final item in history) {
      if (!countableMangaIds.contains(item.mangaId)) continue;
      final chapterKey = '${item.mangaId}|${item.chapterId}';
      if (chapterKeys.contains(chapterKey)) continue;

      final readDay = _dateOnly(item.updatedAt);
      activeDateKeys.add(ReadingActivity.dateKeyFor(readDay));
      chapterKeys.add(chapterKey);
      addReadDate(readDay, fullTimestamp: item.updatedAt);
    }

    final genres = _loadGenreCounts(countableMangaIds, mangaInfoById);
    final recentReads = await _buildRecentReadItems(history, mangaInfoById);

    // Đếm số chapter unique đã đọc mỗi manga (dùng cho Wrapped top-manga ranking)
    final mangaReadCounts = <String, int>{};
    for (final key in chapterKeys) {
      final mangaId = key.split('|').first;
      mangaReadCounts[mangaId] = (mangaReadCounts[mangaId] ?? 0) + 1;
    }

    String peakPeriod = 'Buổi tối (18h - 24h) 🌆';
    int maxHourBucket = hourBuckets[3];
    if (hourBuckets[0] > maxHourBucket) {
      peakPeriod = 'Đêm muộn (0h - 6h) 🌙';
      maxHourBucket = hourBuckets[0];
    }
    if (hourBuckets[1] > maxHourBucket) {
      peakPeriod = 'Buổi sáng (6h - 12h) 🌅';
      maxHourBucket = hourBuckets[1];
    }
    if (hourBuckets[2] > maxHourBucket) {
      peakPeriod = 'Buổi chiều (12h - 18h) ☀️';
      maxHourBucket = hourBuckets[2];
    }
    if (hourBuckets[3] >= maxHourBucket && hourBuckets[3] > 0) {
      peakPeriod = 'Buổi tối (18h - 24h) 🌆';
    }

    final avgChapters = activeDateKeys.isNotEmpty
        ? (chapterKeys.length / activeDateKeys.length)
        : 0.0;

    final streak = _calculateStreak(activeDateKeys);
    unawaited(AchievementService.instance.recordStreak(streak));

    if (!mounted) return;
    setState(() {
      _totalReadMangas = countableMangaIds.length;
      _activeDays = activeDateKeys.length;
      _chaptersRead = chapterKeys.length;
      _currentStreak = streak;
      _weeklyCounts = weeklyCounts;
      _monthlyCounts = monthlyCounts;
      _peakHourPeriod = peakPeriod;
      _avgChaptersPerDay = avgChapters;
      _genreCounts = genres;
      _recentReads = recentReads;
      _history = history;
      _cloudMangas = cloudMangas;
      _mangaReadCounts = mangaReadCounts;
      _isLoading = false;
    });
  }

  Future<Map<String, _MangaInfo>> _loadMangaInfo(
    Set<String> mangaIds,
    Map<String, CloudManga> cloudMangas,
  ) async {
    final result = <String, _MangaInfo>{};
    final localMangas = await DatabaseHelper.instance.getAllLocalMangas();
    final localMangaMap = {for (final m in localMangas) m.id: m};

    for (final mangaId in mangaIds) {
      if (mangaId.startsWith('LOCAL_NOVEL|')) {
        final rawPath = mangaId.replaceFirst('LOCAL_NOVEL|', '');
        final fileName = rawPath.split(RegExp(r'[/\\]')).last;
        final cleanTitle = fileName.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
        result[mangaId] = _MangaInfo(
          title: cleanTitle.isEmpty ? 'Truyện chữ' : cleanTitle,
          genres: ['Truyện chữ'],
          hasCatalogMetadata: true,
        );
        continue;
      }

      final manga = localMangaMap[mangaId];
      if (manga != null) {
        result[mangaId] = _MangaInfo(
          title: manga.title.trim().isEmpty ? null : manga.title.trim(),
          genres: manga.genres,
          hasCatalogMetadata: true,
        );
        continue;
      }

      final cloudManga = cloudMangas[mangaId];
      if (cloudManga != null) {
        result[mangaId] = _MangaInfo(
          title: cloudManga.title.trim().isEmpty
              ? null
              : cloudManga.title.trim(),
          genres: cloudManga.genres,
          hasCatalogMetadata: true,
        );
        continue;
      }
    }

    return result;
  }

  Map<String, int> _loadGenreCounts(
    Set<String> mangaIds,
    Map<String, _MangaInfo> mangaInfoById,
  ) {
    final counts = <String, int>{};
    for (final mangaId in mangaIds) {
      final info = mangaInfoById[mangaId];
      final validGenres = info?.genres
          .where((g) => g.trim().isNotEmpty)
          .toList();

      if (validGenres == null || validGenres.isEmpty) {
        continue;
      }

      for (final genre in validGenres) {
        final normalized = genre.trim();
        counts[normalized] = (counts[normalized] ?? 0) + 1;
      }
    }

    return Map.fromEntries(
      counts.entries.toList()..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      }),
    );
  }

  Future<List<_RecentReadItem>> _buildRecentReadItems(
    List<ReadingHistory> history,
    Map<String, _MangaInfo> mangaInfoById,
  ) async {
    final result = <_RecentReadItem>[];
    var driveFallbackLookups = 0;

    for (final item in history) {
      if (result.length >= 5) break;
      final info = mangaInfoById[item.mangaId];
      var title = info?.title;

      if ((title == null || title.isEmpty) &&
          driveFallbackLookups < 5 &&
          !item.mangaId.startsWith('LOCAL_NOVEL|')) {
        driveFallbackLookups++;
        try {
          final driveFile = await DriveService.instance.getFile(item.mangaId);
          title = driveFile?['name']?.toString().trim();
        } catch (_) {}
      }

      if (title == null || title.isEmpty) continue;

      final progress = item.totalPages <= 1
          ? 0.0
          : (item.lastPageIndex + 1) / item.totalPages;

      result.add(
        _RecentReadItem(
          mangaId: item.mangaId,
          chapterId: item.chapterId,
          pageIndex: item.lastPageIndex,
          title: title,
          chapterTitle: item.chapterTitle ?? item.chapterId,
          progress: progress.clamp(0, 1).toDouble(),
          updatedAt: item.updatedAt,
        ),
      );
    }
    return result;
  }

  int _calculateStreak(Set<String> dateKeys) {
    final today = _dateOnly(DateTime.now());
    var streak = 0;

    // Kiểm tra xem hôm nay có hoạt động không
    if (dateKeys.contains(ReadingActivity.dateKeyFor(today))) {
      var cursor = today;
      while (dateKeys.contains(ReadingActivity.dateKeyFor(cursor))) {
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
      }
    } else {
      // Nếu hôm nay chưa đọc, thử kiểm tra từ hôm qua để giữ streak hiển thị
      var cursor = today.subtract(const Duration(days: 1));
      if (dateKeys.contains(ReadingActivity.dateKeyFor(cursor))) {
        while (dateKeys.contains(ReadingActivity.dateKeyFor(cursor))) {
          streak++;
          cursor = cursor.subtract(const Duration(days: 1));
        }
      }
    }

    return streak;
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _startOfWeek(DateTime value) {
    return _dateOnly(value).subtract(Duration(days: value.weekday - 1));
  }

  DateTime _parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return _dateOnly(DateTime.now());
    return DateTime(
      int.tryParse(parts[0]) ?? DateTime.now().year,
      int.tryParse(parts[1]) ?? 1,
      int.tryParse(parts[2]) ?? 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thống kê đọc'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.card_giftcard_rounded, color: Colors.orangeAccent),
            tooltip: 'Manga Wrapped',
            onPressed: _isLoading ? null : _openMangaWrapped,
          ),
          IconButton(
            icon: const Icon(Icons.military_tech_rounded, color: Colors.amberAccent),
            tooltip: 'Huy hiệu thành tựu',
            onPressed: () => AchievementService.showAchievementShowcase(context),
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Chia sẻ thống kê',
            onPressed: _isLoading ? null : () => _showShareCardDialog(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_totalReadMangas == 0 && _chaptersRead == 0)
          ? RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 80),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.auto_graph_rounded,
                              size: 64,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Chưa có dữ liệu thống kê',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Hãy bắt đầu đọc truyện để theo dõi chuỗi ngày đọc, biểu đồ hoạt động và thể loại yêu thích của bạn!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () => context.go('/'),
                            icon: const Icon(Icons.explore_rounded, size: 18),
                            label: const Text('Bắt đầu đọc ngay'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Theme.of(context).colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWrappedBanner(context),
                    const SizedBox(height: 16),
                    _buildSummary(),
                    const SizedBox(height: 18),
                    _buildStatGrid(),
                    const SizedBox(height: 16),
                    _buildAchievementBanner(context),
                    const SizedBox(height: 24),
                    _buildActivityHeader(),
                    const SizedBox(height: 12),
                    _isMonthView ? _buildMonthlyChart(context) : _buildWeeklyChart(context),
                    const SizedBox(height: 28),
                    _buildSectionTitle('Thể loại đọc nhiều'),
                    const SizedBox(height: 12),
                    _buildGenreRanking(context),
                    const SizedBox(height: 28),
                    _buildSectionTitle('Đọc gần đây'),
                    const SizedBox(height: 12),
                    _buildRecentReads(context),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSummary() {
    final weeklyTotal = _weeklyCounts.fold<int>(0, (sum, value) => sum + value);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            weeklyTotal > 0
                ? 'Tuần này bạn đã đọc $weeklyTotal lượt chương.'
                : 'Tuần này chưa có hoạt động đọc mới.',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            _currentStreak > 0
                ? 'Chuỗi đọc hiện tại: $_currentStreak ngày liên tiếp.'
                : 'Đọc hôm nay để bắt đầu chuỗi mới.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.32,
      children: [
        _buildStatCard(
          'Truyện',
          '$_totalReadMangas',
          Icons.menu_book_rounded,
          Colors.blueAccent,
        ),
        _buildStatCard(
          'Chương đã đọc',
          '$_chaptersRead',
          Icons.auto_stories_rounded,
          Colors.greenAccent,
        ),
        _buildStatCard(
          'Ngày hoạt động',
          '$_activeDays',
          Icons.calendar_month_rounded,
          Colors.orangeAccent,
        ),
        _buildStatCard(
          'Streak',
          '$_currentStreak',
          Icons.local_fire_department_rounded,
          Colors.redAccent,
        ),
        _buildStatCard(
          'Tốc độ đọc',
          '${_avgChaptersPerDay.toStringAsFixed(1)} chap/ngày',
          Icons.bolt_rounded,
          Colors.amberAccent,
        ),
        _buildStatCard(
          'Khung giờ vàng',
          _peakHourPeriod,
          Icons.access_time_filled_rounded,
          Colors.purpleAccent,
        ),
      ],
    );
  }

  void _openMangaWrapped() {
    final wrappedData = MangaWrappedData.create(
      totalChapters: _chaptersRead,
      totalMangas: _totalReadMangas,
      activeDays: _activeDays,
      currentStreak: _currentStreak,
      peakHourPeriod: _peakHourPeriod,
      genreCounts: _genreCounts,
      history: _history,
      cloudMangas: _cloudMangas,
      customMangaReadCounts: _mangaReadCounts,
    );
    MangaWrappedDialog.show(context, wrappedData);
  }

  Widget _buildWrappedBanner(BuildContext context) {
    final isSpecial = MangaWrappedData.isWrappedSeasonActive();
    final season = MangaWrappedData.getCurrentSeason();
    final now = DateTime.now();

    String title;
    String subtitle;
    if (season == WrappedSeason.midYear) {
      title = 'Manga Wrapped • Nửa Năm ${now.year}';
      subtitle = 'Báo cáo tổng kết 6 tháng đầu năm của bạn đã sẵn sàng!';
    } else if (season == WrappedSeason.yearEnd) {
      final year = now.month == 1 ? now.year - 1 : now.year;
      title = 'Manga Wrapped • Tổng Kết $year';
      subtitle = 'Báo cáo tổng kết trọn năm của bạn đã sẵn sàng!';
    } else {
      title = 'Manga Wrapped • Báo Cáo Độc Giả';
      subtitle = 'Khám phá thẻ vinh danh và gu đọc truyện của bạn!';
    }

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _openMangaWrapped,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isSpecial
                ? [
                    const Color(0xFFD97706),
                    const Color(0xFFB45309),
                    const Color(0xFF78350F),
                  ]
                : [
                    const Color(0xFF7C3AED),
                    const Color(0xFF4C1D95),
                    const Color(0xFF1E1B4B),
                  ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSpecial ? Colors.amberAccent : Colors.purpleAccent.withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isSpecial
                  ? Colors.amber.withValues(alpha: 0.3)
                  : Colors.purple.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSpecial ? Icons.auto_awesome : Icons.card_giftcard_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (isSpecial)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amberAccent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'HOT',
                            style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAchievementBanner(BuildContext context) {
    final unlocked = AchievementService.instance.getUnlockedCount();
    final total = AchievementService.instance.getTotalCount();
    final percent = total > 0 ? (unlocked / total) : 0.0;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => AchievementService.showAchievementShowcase(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.amber.withValues(alpha: 0.15),
              Colors.deepOrangeAccent.withValues(alpha: 0.08),
              Theme.of(context).cardColor,
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.amber.withValues(alpha: 0.3),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.military_tech_rounded, color: Colors.amberAccent, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Huy Hiệu Thành Tựu',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$unlocked/$total Đã mở',
                        style: const TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: percent,
                      minHeight: 5,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.amberAccent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
    );
  }

  Widget _buildActivityHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            _isMonthView ? 'Hoạt động 30 ngày qua' : 'Hoạt động tuần này',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChoiceChip(
                label: Text(
                  'Tuần',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: !_isMonthView
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                selected: !_isMonthView,
                selectedColor: Theme.of(context).colorScheme.primary,
                visualDensity: VisualDensity.compact,
                onSelected: (val) {
                  if (val) {
                    HapticFeedback.selectionClick();
                    setState(() => _isMonthView = false);
                  }
                },
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                label: Text(
                  '30 ngày',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _isMonthView
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                selected: _isMonthView,
                selectedColor: Theme.of(context).colorScheme.primary,
                visualDensity: VisualDensity.compact,
                onSelected: (val) {
                  if (val) {
                    HapticFeedback.selectionClick();
                    setState(() => _isMonthView = true);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlyChart(BuildContext context) {
    final maxCount = max(1, _monthlyCounts.reduce(max));
    final today = DateTime.now();

    return Container(
      height: 230,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 30; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: _MonthlyBar(
                        value: _monthlyCounts[i],
                        maxValue: maxCount,
                        isToday: i == 29,
                        dayNumber: today.subtract(Duration(days: 29 - i)).day,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '30 ngày trước',
                style: TextStyle(
                  fontSize: 10.5,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
              Text(
                'Đỉnh điểm: $maxCount chap/ngày',
                style: TextStyle(
                  fontSize: 10.5,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Hôm nay',
                style: TextStyle(
                  fontSize: 10.5,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showShareCardDialog(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? 'Độc giả';
    final topGenre = _genreCounts.keys.firstOrNull ?? 'Đa dạng';

    final summaryText = '''
📚 **Thống Kê Đọc Truyện - $name**
🔥 Chuỗi đọc: $_currentStreak ngày liên tiếp
📖 Tổng số truyện: $_totalReadMangas bộ
📑 Tổng số chương: $_chaptersRead chap
⚡ Tốc độ trung bình: ${_avgChaptersPerDay.toStringAsFixed(1)} chap/ngày
🏆 Thể loại yêu thích: $topGenre
🕒 Khung giờ vàng: $_peakHourPeriod
'''.trim();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.auto_awesome, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Thẻ Độc Giả', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.15),
                Theme.of(ctx).colorScheme.secondary.withValues(alpha: 0.15),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                    child: user?.photoURL == null ? const Icon(Icons.person, size: 18) : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(
                          'Manga-Reader Analytics',
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Divider(color: Theme.of(ctx).dividerColor, height: 20),
              Text('🔥 Streak: $_currentStreak ngày liên tiếp', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('📖 Đã đọc: $_totalReadMangas truyện ($_chaptersRead chap)', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              Text('⚡ Tốc độ: ${_avgChaptersPerDay.toStringAsFixed(1)} chap/ngày', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              Text('🏆 Gu truyện: $topGenre', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              Text('🕒 Giờ đọc: $_peakHourPeriod', style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: summaryText));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Đã sao chép tóm tắt thống kê vào bộ nhớ tạm!'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Sao chép tóm tắt'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.primary,
              foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyChart(BuildContext context) {
    const days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final maxCount = max(1, _weeklyCounts.reduce(max));

    return Container(
      height: 230,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: _WeeklyBar(
                label: days[i],
                value: _weeklyCounts[i],
                maxValue: maxCount,
                isToday: DateTime.now().weekday - 1 == i,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGenreRanking(BuildContext context) {
    final topGenres = _genreCounts.entries.take(6).toList();
    if (topGenres.isEmpty) {
      return _buildEmptyCard('Chưa có dữ liệu thể loại');
    }

    final maxCount = topGenres.first.value;
    const colors = [
      Colors.redAccent,
      Colors.blueAccent,
      Colors.greenAccent,
      Colors.orangeAccent,
      Colors.purpleAccent,
      Colors.cyanAccent,
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < topGenres.length; i++) ...[
            _GenreRow(
              rank: i + 1,
              name: topGenres[i].key,
              value: topGenres[i].value,
              maxValue: maxCount,
              color: colors[i % colors.length],
            ),
            if (i != topGenres.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentReads(BuildContext context) {
    if (_recentReads.isEmpty) {
      return _buildEmptyCard('Chưa có lịch sử đọc');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _recentReads.length; i++) ...[
            _RecentReadRow(item: _recentReads[i], onRefresh: _loadData),
            if (i != _recentReads.length - 1)
              Divider(color: Theme.of(context).dividerColor, height: 22),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.onSurface,
                    height: 1.15,
                  ),
                  maxLines: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _WeeklyBar extends StatelessWidget {
  final String label;
  final int value;
  final int maxValue;
  final bool isToday;

  const _WeeklyBar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue <= 0 ? 0.0 : value / maxValue;
    final colorScheme = Theme.of(context).colorScheme;
    final color = isToday ? colorScheme.primary : colorScheme.primary.withValues(alpha: 0.45);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: value > 0
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 140,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                width: 18,
                height: 140,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                width: 18,
                height: value == 0 ? 0 : max(10, 140 * ratio),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: isToday
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
            fontSize: 12,
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _MonthlyBar extends StatelessWidget {
  final int value;
  final int maxValue;
  final bool isToday;
  final int dayNumber;

  const _MonthlyBar({
    required this.value,
    required this.maxValue,
    required this.isToday,
    required this.dayNumber,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue <= 0 ? 0.0 : value / maxValue;
    final isPeak = value == maxValue && maxValue > 0;
    final color = isToday
        ? Colors.redAccent
        : isPeak
            ? Colors.orangeAccent
            : Colors.blueAccent.withValues(alpha: value > 0 ? 0.85 : 0.25);

    return Tooltip(
      message: 'Ngày $dayNumber: $value chương',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                width: double.infinity,
                height: value == 0 ? 4 : max(8, 140 * ratio),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            (dayNumber == 1 || dayNumber == 10 || dayNumber == 20 || isToday)
                ? '$dayNumber'
                : '',
            style: TextStyle(
              color: isToday
                  ? Colors.redAccent
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
              fontSize: 8.5,
              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _GenreRow extends StatelessWidget {
  final int rank;
  final String name;
  final int value;
  final int maxValue;
  final Color color;

  const _GenreRow({
    required this.rank,
    required this.name,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue <= 0 ? 0.0 : value / maxValue;
    return Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(
            '#$rank',
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '$value truyện',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 7,
                  color: color,
                  backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentReadItem {
  final String mangaId;
  final String chapterId;
  final int pageIndex;
  final String title;
  final String chapterTitle;
  final double progress;
  final DateTime updatedAt;

  const _RecentReadItem({
    required this.mangaId,
    required this.chapterId,
    required this.pageIndex,
    required this.title,
    required this.chapterTitle,
    required this.progress,
    required this.updatedAt,
  });
}

class _MangaInfo {
  final String? title;
  final List<String> genres;
  final bool hasCatalogMetadata;

  const _MangaInfo({
    required this.title,
    required this.genres,
    required this.hasCatalogMetadata,
  });
}

class _RecentReadRow extends StatelessWidget {
  final _RecentReadItem item;
  final VoidCallback? onRefresh;

  const _RecentReadRow({required this.item, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          if (item.mangaId.startsWith('LOCAL_NOVEL|')) {
            final rawPath = item.mangaId.replaceFirst('LOCAL_NOVEL|', '');
            await context.push(
              '/novel-reader',
              extra: LocalNovel(
                path: rawPath,
                title: item.title,
                coverPath: '',
                importedAt: item.updatedAt,
              ),
            );
          } else {
            await context.push(
              '/reader/${item.chapterId}?mangaId=${Uri.encodeComponent(item.mangaId)}&page=${item.pageIndex}',
            );
          }
          if (context.mounted) {
            onRefresh?.call();
          }
        },
        onLongPress: () async {
          if (!item.mangaId.startsWith('LOCAL_NOVEL|')) {
            await context.push('/detail/${item.mangaId}');
            if (context.mounted) {
              onRefresh?.call();
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            children: [
              SizedBox(
                width: 42,
                child: Text(
                  '${(item.progress * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.chapterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatRelativeDate(item.updatedAt),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatRelativeDate(DateTime value) {
    final now = DateTime.now();
    final diff = now.difference(value);
    if (diff.inMinutes < 1) return 'vừa xong';
    if (diff.inHours < 1) return '${diff.inMinutes}p';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays} ngày';
    return '${value.day}/${value.month}';
  }
}
