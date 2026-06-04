import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/database_helper.dart';
import '../../data/models.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';

class ReadingAnalyticsPage extends StatefulWidget {
  const ReadingAnalyticsPage({super.key});

  @override
  State<ReadingAnalyticsPage> createState() => _ReadingAnalyticsPageState();
}

class _ReadingAnalyticsPageState extends State<ReadingAnalyticsPage> {
  bool _isLoading = true;
  int _totalReadMangas = 0;
  int _activeDays = 0;
  int _chaptersRead = 0;
  int _currentStreak = 0;
  List<int> _weeklyCounts = List.filled(7, 0);
  Map<String, int> _genreCounts = const {};
  List<_RecentReadItem> _recentReads = const [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final userIds = authUid == null ? ['guest'] : ['guest', authUid];

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
    } catch (_) {}

    final mangaInfoById = await _loadMangaInfo(mangaIds, cloudMangas);
    final countableMangaIds = mangaInfoById.entries
        .where((entry) => entry.value.hasCatalogMetadata)
        .map((entry) => entry.key)
        .toSet();

    final weekStart = _startOfWeek(DateTime.now());
    final weeklyCounts = List.filled(7, 0);
    final activeDateKeys = <String>{};
    final chapterKeys = <String>{};

    void addReadDate(DateTime readDay) {
      final daysFromWeekStart = readDay.difference(weekStart).inDays;
      if (daysFromWeekStart >= 0 && daysFromWeekStart < 7) {
        weeklyCounts[daysFromWeekStart]++;
      }
    }

    for (final item in activities) {
      if (!countableMangaIds.contains(item.mangaId)) continue;
      activeDateKeys.add(item.dateKey);
      chapterKeys.add('${item.mangaId}|${item.chapterId}');
      addReadDate(_parseDateKey(item.dateKey));
    }

    for (final item in history) {
      if (!countableMangaIds.contains(item.mangaId)) continue;
      final chapterKey = '${item.mangaId}|${item.chapterId}';
      if (chapterKeys.contains(chapterKey)) continue;

      final readDay = _dateOnly(item.updatedAt);
      activeDateKeys.add(ReadingActivity.dateKeyFor(readDay));
      chapterKeys.add(chapterKey);
      addReadDate(readDay);
    }

    final genres = _loadGenreCounts(countableMangaIds, mangaInfoById);
    final recentReads = await _buildRecentReadItems(history, mangaInfoById);

    if (!mounted) return;
    setState(() {
      _totalReadMangas = countableMangaIds.length;
      _activeDays = activeDateKeys.length;
      _chaptersRead = chapterKeys.length;
      _currentStreak = _calculateStreak(activeDateKeys);
      _weeklyCounts = weeklyCounts;
      _genreCounts = genres;
      _recentReads = recentReads;
      _isLoading = false;
    });
  }

  Future<Map<String, _MangaInfo>> _loadMangaInfo(
    Set<String> mangaIds,
    Map<String, CloudManga> cloudMangas,
  ) async {
    final result = <String, _MangaInfo>{};

    for (final mangaId in mangaIds) {
      final manga = await DatabaseHelper.instance.getLocalManga(mangaId);
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

      if (mangaId.startsWith('epub_')) {
        result[mangaId] = const _MangaInfo(
          title: 'EPUB',
          genres: ['EPUB'],
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

      if ((title == null || title.isEmpty) && driveFallbackLookups < 5) {
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSummary(),
                    const SizedBox(height: 18),
                    _buildStatGrid(),
                    const SizedBox(height: 28),
                    _buildSectionTitle('Hoạt động tuần này'),
                    const SizedBox(height: 12),
                    _buildWeeklyChart(context),
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
        border: Border.all(color: Colors.white10),
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
            style: const TextStyle(color: Colors.white60, fontSize: 13),
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
      childAspectRatio: 1.55,
      children: [
        _buildStatCard(
          'Truyện',
          '$_totalReadMangas',
          Icons.menu_book,
          Colors.blue,
        ),
        _buildStatCard(
          'Chương đã đọc',
          '$_chaptersRead',
          Icons.auto_stories,
          Colors.greenAccent,
        ),
        _buildStatCard(
          'Ngày hoạt động',
          '$_activeDays',
          Icons.calendar_month,
          Colors.orange,
        ),
        _buildStatCard(
          'Streak',
          '$_currentStreak',
          Icons.local_fire_department,
          Colors.redAccent,
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
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
        border: Border.all(color: Colors.white10),
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
        border: Border.all(color: Colors.white10),
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
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _recentReads.length; i++) ...[
            _RecentReadRow(item: _recentReads[i]),
            if (i != _recentReads.length - 1)
              const Divider(color: Colors.white10, height: 22),
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
        border: Border.all(color: Colors.white10),
      ),
      child: Text(message, style: const TextStyle(color: Colors.white54)),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.white60),
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
    final color = isToday ? Colors.redAccent : Colors.blueAccent;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: value > 0 ? Colors.white : Colors.white30,
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
                  color: Colors.white10,
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
            color: isToday ? Colors.white : Colors.white60,
            fontSize: 12,
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ],
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
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
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
                  backgroundColor: Colors.white10,
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
  final String title;
  final String chapterTitle;
  final double progress;
  final DateTime updatedAt;

  const _RecentReadItem({
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

  const _RecentReadRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
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
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _formatRelativeDate(item.updatedAt),
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
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
