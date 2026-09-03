import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../data/models.dart';
import '../../data/models_cloud.dart';
import '../shared/drive_image.dart';

enum WrappedSeason {
  midYear,
  yearEnd,
  currentSnapshot,
}

class MangaWrappedData {
  final WrappedSeason season;
  final String seasonTitle;
  final String seasonSubtitle;
  final int totalChapters;
  final int totalMangas;
  final int activeDays;
  final int currentStreak;
  final int estimatedReadingMinutes;
  final double averageChaptersPerDay;
  final String peakHourPeriod;
  final String peakDayName;
  final int peakDayChapters;
  final String readerPersona;
  final String personaDescription;
  final String topTierBadge;
  final List<WrappedTopManga> topMangas;
  final Map<String, int> topGenres;

  const MangaWrappedData({
    required this.season,
    required this.seasonTitle,
    required this.seasonSubtitle,
    required this.totalChapters,
    required this.totalMangas,
    required this.activeDays,
    required this.currentStreak,
    required this.estimatedReadingMinutes,
    required this.averageChaptersPerDay,
    required this.peakHourPeriod,
    required this.peakDayName,
    required this.peakDayChapters,
    required this.readerPersona,
    required this.personaDescription,
    required this.topTierBadge,
    required this.topMangas,
    required this.topGenres,
  });

  static WrappedSeason getCurrentSeason([DateTime? nowTime]) {
    final now = nowTime ?? DateTime.now();
    final month = now.month;
    final day = now.day;

    if ((month == 6 && day >= 15) || month == 7) {
      return WrappedSeason.midYear;
    }
    if ((month == 12 && day >= 15) || month == 1) {
      return WrappedSeason.yearEnd;
    }
    return WrappedSeason.currentSnapshot;
  }

  static bool isWrappedSeasonActive([DateTime? nowTime]) {
    final season = getCurrentSeason(nowTime);
    return season == WrappedSeason.midYear || season == WrappedSeason.yearEnd;
  }

  static MangaWrappedData create({
    required int totalChapters,
    required int totalMangas,
    required int activeDays,
    required int currentStreak,
    required String peakHourPeriod,
    required Map<String, int> genreCounts,
    required List<ReadingHistory> history,
    required Map<String, CloudManga> cloudMangas,
    Map<String, int>? customMangaReadCounts,
  }) {
    final now = DateTime.now();
    final season = getCurrentSeason(now);

    String title;
    String subtitle;
    if (season == WrappedSeason.midYear) {
      title = 'Manga Wrapped • Nửa Năm ${now.year}';
      subtitle = 'Hành trình khám phá 6 tháng đầu năm rực rỡ của bạn';
    } else if (season == WrappedSeason.yearEnd) {
      final year = now.month == 1 ? now.year - 1 : now.year;
      title = 'Manga Wrapped • Tổng Kết $year';
      subtitle = 'Nhìn lại một năm đắm chìm bất tận trong thế giới truyện';
    } else {
      title = 'Manga Wrapped • Báo Cáo ${now.year}';
      subtitle = 'Bản tổng kết hành trình đọc truyện độc bản của bạn';
    }

    // Ước tính thời gian đọc: ~7 phút / chap truyện tranh / chương tiểu thuyết
    final estimatedMinutes = totalChapters * 7;
    final avgPerDay = activeDays > 0 ? (totalChapters / activeDays) : 0.0;

    // Tìm ngày đọc nhiều nhất trong lịch sử
    final dayCounts = <String, int>{};
    for (final item in history) {
      final dateKey = '${item.updatedAt.year}-${item.updatedAt.month.toString().padLeft(2, '0')}-${item.updatedAt.day.toString().padLeft(2, '0')}';
      dayCounts[dateKey] = (dayCounts[dateKey] ?? 0) + 1;
    }

    String peakDayName = 'Một ngày tuyệt đẹp';
    int peakDayChapters = 0;
    if (dayCounts.isNotEmpty) {
      final sortedDays = dayCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topDay = sortedDays.first;
      peakDayChapters = topDay.value;
      try {
        final parts = topDay.key.split('-');
        if (parts.length == 3) {
          peakDayName = 'Ngày ${parts[2]}/${parts[1]}';
        }
      } catch (_) {}
    }

    // Đánh giá cấp bậc độc giả toàn server
    String topTier;
    if (totalChapters >= 500) {
      topTier = '🔥 Top 1% Độc Giả Thần Thoại Toàn Server';
    } else if (totalChapters >= 200) {
      topTier = '💎 Top 5% Độc Giả Chăm Chỉ Toàn Server';
    } else if (totalChapters >= 80) {
      topTier = '🌟 Top 15% Độc Giả Năng Động';
    } else {
      topTier = '✨ Độc Giả Tiềm Năng';
    }

    // 12 Reader Personas đa dạng và hấp dẫn
    String persona;
    String personaDesc;

    if (totalChapters >= 500) {
      persona = 'Đại La Thần Tọa 👑';
      personaDesc = 'Bạn đọc truyện như hít thở không khí, thư viện trong tay bạn không còn bộ nào chưa cày!';
    } else if (totalChapters >= 200) {
      persona = 'Chiến Thần Cày Truyện ⚡';
      personaDesc = 'Tốc độ lướt trang kinh hoàng, không một chương mới nào có thể thoát khỏi tầm mắt bạn.';
    } else if (currentStreak >= 21) {
      persona = 'Hỏa Thần Bất Diệt 🔥';
      personaDesc = 'Ý chí kiên cường phi thường, mỗi ngày mở app đọc truyện đã trở thành một phần linh hồn của bạn.';
    } else if (peakHourPeriod.contains('0h') || peakHourPeriod.contains('Đêm')) {
      persona = 'Chúa Tể Cú Đêm 🌙';
      personaDesc = 'Khi vạn vật chìm vào giấc ngủ, thế giới tu tiên và phiêu lưu kỳ ảo của bạn mới thực sự bắt đầu.';
    } else if (peakHourPeriod.contains('sáng') || peakHourPeriod.contains('6h')) {
      persona = 'Thần Đồng Bình Minh 🌅';
      personaDesc = 'Khởi đầu ngày mới cùng một tách trà và những trang truyện thơm mùi phiêu lưu sảng khoái.';
    } else if (genreCounts.containsKey('Tu Tiên') || genreCounts.containsKey('Huyền Huyễn') || genreCounts.containsKey('Tiên Hiệp')) {
      persona = 'Đại Tông Sư Tu Tiên ⚔️';
      personaDesc = 'Độ kiếp phi thăng, am hiểu mọi cảnh giới công pháp từ Luyện Khí đến Đại Thừa.';
    } else if (genreCounts.containsKey('Isekai') || genreCounts.containsKey('Chuyển Sinh')) {
      persona = 'Kẻ Thống Trị Dị Giới 🌌';
      personaDesc = 'Sẵn sàng bị xe tải đâm bất cứ lúc nào để sang thế giới khác xây dựng hậu cung và cứu thế giới.';
    } else if (genreCounts.containsKey('Romance') || genreCounts.containsKey('Tình Cảm') || genreCounts.containsKey('Ngôn Tình')) {
      persona = 'Trái Tim Mộng Mơ 💕';
      personaDesc = 'Yêu thích những câu chuyện tình cảm ngọt ngào sâu lắng, làm tan chảy mọi tâm hồn khô khan.';
    } else if (genreCounts.containsKey('Action') || genreCounts.containsKey('Hành Động')) {
      persona = 'Bậc Thầy Võ Thuật 🥊';
      personaDesc = 'Mê đắm những pha combat nghẹt thở, những cú đấm uy lực và những màn lật kèo ngoạn mục.';
    } else if (genreCounts.keys.length >= 10) {
      persona = 'Kẻ Săn Đa Vũ Trụ 🌐';
      personaDesc = 'Gu truyện siêu rộng lớn, từ kinh dị, trinh thám đến hài hước không có thể loại nào làm khó được bạn.';
    } else if (avgPerDay >= 10) {
      persona = 'Sát Thủ Tốc Độ 🚀';
      personaDesc = 'Nuốt chửng hàng chục chương truyện mỗi ngày chỉ trong một cái chớp mắt.';
    } else {
      persona = 'Độc Giả Tinh Anh 🌟';
      personaDesc = 'Đọc có chọn lọc, thưởng thức từng khung tranh và cảm nhận trọn vẹn từng câu chữ.';
    }

    // Extract top 3 manga
    final mangaReadCounts = customMangaReadCounts != null
        ? Map<String, int>.from(customMangaReadCounts)
        : <String, int>{};
    if (customMangaReadCounts == null) {
      for (final item in history) {
        mangaReadCounts[item.mangaId] = (mangaReadCounts[item.mangaId] ?? 0) + 1;
      }
    }

    final sortedEntries = mangaReadCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topMangas = <WrappedTopManga>[];
    for (int i = 0; i < min(3, sortedEntries.length); i++) {
      final entry = sortedEntries[i];
      final manga = cloudMangas[entry.key];
      String mangaTitle = manga?.title ?? '';
      if (mangaTitle.isEmpty) {
        if (entry.key.startsWith('LOCAL_NOVEL|')) {
          final rawPath = entry.key.replaceFirst('LOCAL_NOVEL|', '');
          final fileName = rawPath.split(RegExp(r'[/\\]')).last;
          mangaTitle = fileName.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
          if (mangaTitle.isEmpty) mangaTitle = 'Tiểu thuyết';
        } else {
          mangaTitle = 'Truyện tranh';
        }
      }
      topMangas.add(
        WrappedTopManga(
          mangaId: entry.key,
          title: mangaTitle,
          coverFileId: manga?.coverFileId ?? '',
          chaptersRead: max(1, entry.value),
          rank: i + 1,
        ),
      );
    }

    return MangaWrappedData(
      season: season,
      seasonTitle: title,
      seasonSubtitle: subtitle,
      totalChapters: totalChapters,
      totalMangas: totalMangas,
      activeDays: activeDays,
      currentStreak: currentStreak,
      estimatedReadingMinutes: estimatedMinutes,
      averageChaptersPerDay: avgPerDay,
      peakHourPeriod: peakHourPeriod,
      peakDayName: peakDayName,
      peakDayChapters: peakDayChapters,
      readerPersona: persona,
      personaDescription: personaDesc,
      topTierBadge: topTier,
      topMangas: topMangas,
      topGenres: genreCounts,
    );
  }
}

class WrappedTopManga {
  final String mangaId;
  final String title;
  final String coverFileId;
  final int chaptersRead;
  final int rank;

  const WrappedTopManga({
    required this.mangaId,
    required this.title,
    required this.coverFileId,
    required this.chaptersRead,
    required this.rank,
  });
}

class MangaWrappedDialog extends StatefulWidget {
  final MangaWrappedData data;

  const MangaWrappedDialog({super.key, required this.data});

  static void show(BuildContext context, MangaWrappedData data) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (_) => MangaWrappedDialog(data: data),
    );
  }

  @override
  State<MangaWrappedDialog> createState() => _MangaWrappedDialogState();
}

class _MangaWrappedDialogState extends State<MangaWrappedDialog> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  static const int _totalPages = 7;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      HapticFeedback.lightImpact();
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      HapticFeedback.lightImpact();
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _copySummaryToClipboard() {
    HapticFeedback.mediumImpact();
    final d = widget.data;
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? 'Độc giả MangaReader';
    final hours = (d.estimatedReadingMinutes / 60).toStringAsFixed(1);
    final topManga = d.topMangas.isNotEmpty ? d.topMangas.first.title : 'Đa dạng';
    final topGenre = d.topGenres.isNotEmpty ? d.topGenres.keys.first : 'Đa dạng';

    final text = '''
🌟 **${d.seasonTitle}** 🌟
👤 Độc giả: **$name**
🏆 Danh hiệu: **${d.readerPersona}**
🏅 Cấp bậc: ${d.topTierBadge}

📊 **Những Con Số Ấn Tượng:**
📖 Đã cày: **${d.totalChapters} chương** (${d.totalMangas} bộ truyện)
⏱️ Thời gian đọc: **~$hours giờ** (~${d.estimatedReadingMinutes} phút)
🔥 Chuỗi đọc đỉnh nhất: **${d.currentStreak} ngày liên tiếp**
⚡ Tốc độ cày: **${d.averageChaptersPerDay.toStringAsFixed(1)} chap/ngày**
👑 Bộ truyện mê nhất: **$topManga**
🎭 Gu truyện chân ái: **$topGenre**
🕒 Khung giờ vàng: **${d.peakHourPeriod}**

✨ Xem ngay báo cáo Manga Wrapped của bạn trên Manga-Reader App!
'''.trim();

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✨ Đã sao chép tóm tắt Manga Wrapped vào bộ nhớ tạm!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _shareToForum() {
    final d = widget.data;
    final hours = (d.estimatedReadingMinutes / 60).toStringAsFixed(1);
    final topManga = d.topMangas.isNotEmpty ? d.topMangas.first.title : 'Đa dạng';

    final initialContent = '''
Chào cả nhà! Đây là bản tổng kết **${d.seasonTitle}** của mình:

🏆 **Danh hiệu:** ${d.readerPersona}
🏅 **Cấp bậc:** ${d.topTierBadge}
📖 **Tổng số chương đã cày:** ${d.totalChapters} chap (~$hours giờ đọc)
🔥 **Chuỗi ngày đọc:** ${d.currentStreak} ngày liên tục
👑 **Bộ truyện yêu thích nhất:** $topManga

Anh em năm nay cày được bao nhiêu chap rồi? Khoe thành tích bên dưới nhé! 👇
'''.trim();

    Navigator.pop(context);
    context.push('/forum-share', extra: {'initialText': initialContent});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background Gradient Mesh
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _getSlideBgColor(_currentPage),
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),

          // Story Carousel
          PageView(
            controller: _pageController,
            onPageChanged: (idx) => setState(() => _currentPage = idx),
            children: [
              _buildSlide1Overview(),
              _buildSlide2TopMangas(),
              _buildSlide3Genres(),
              _buildSlide4Rhythm(),
              _buildSlide5StyleAndStats(),
              _buildSlide6Persona(),
              _buildSlide7FinalCard(),
            ],
          ),

          // Left/Right Tap Area for Navigation
          Positioned.fill(
            top: 80,
            bottom: 90,
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _prevPage,
                  ),
                ),
                Expanded(
                  flex: 7,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _nextPage,
                  ),
                ),
              ],
            ),
          ),

          // Top Story Progress Indicators & Close Button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: List.generate(_totalPages, (i) {
                      return Expanded(
                        child: Container(
                          height: 3.5,
                          margin: const EdgeInsets.symmetric(horizontal: 2.0),
                          decoration: BoxDecoration(
                            color: i <= _currentPage
                                ? Colors.amberAccent
                                : Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            widget.data.seasonTitle,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getSlideBgColor(int page) {
    switch (page) {
      case 0:
        return const Color(0xFF6B21A8).withValues(alpha: 0.9); // Purple
      case 1:
        return const Color(0xFFB45309).withValues(alpha: 0.9); // Amber Gold
      case 2:
        return const Color(0xFF047857).withValues(alpha: 0.9); // Emerald Green
      case 3:
        return const Color(0xFF1E3A8A).withValues(alpha: 0.9); // Deep Blue
      case 4:
        return const Color(0xFF0F766E).withValues(alpha: 0.9); // Teal
      case 5:
        return const Color(0xFF831843).withValues(alpha: 0.9); // Pink
      case 6:
      default:
        return const Color(0xFF7F1D1D).withValues(alpha: 0.9); // Crimson
    }
  }

  // Slide 1: Welcome & Overview
  Widget _buildSlide1Overview() {
    final d = widget.data;
    final hours = (d.estimatedReadingMinutes / 60).toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 100, 28, 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.amber, Colors.deepOrangeAccent],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.withValues(alpha: 0.4),
                  blurRadius: 28,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: const Icon(Icons.auto_stories_rounded, size: 54, color: Colors.black),
          ),
          const SizedBox(height: 24),
          Text(
            d.seasonTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amberAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.4)),
            ),
            child: Text(
              d.topTierBadge,
              style: const TextStyle(
                color: Colors.amberAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            d.seasonSubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13.5),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricCol('${d.totalChapters}', 'Chương đã cày'),
                Container(width: 1, height: 40, color: Colors.white24),
                _buildMetricCol('~$hours h', 'Thời gian đọc'),
                Container(width: 1, height: 40, color: Colors.white24),
                _buildMetricCol('${d.totalMangas}', 'Bộ truyện'),
              ],
            ),
          ),
          const Spacer(),
          const Text(
            'Chạm để lướt trang tiếp theo 👉',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // Slide 2: Top 3 Manga (Podium style)
  Widget _buildSlide2TopMangas() {
    final top = widget.data.topMangas;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 100, 24, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            '🏆 BẢNG VÀNG CÀY CUỐC',
            style: TextStyle(
              color: Colors.amberAccent,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Top Bộ Truyện Bạn Mê Nhất',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 24),
          if (top.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Chưa có truyện nào được ghi nhận', style: TextStyle(color: Colors.white54)),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: top.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, idx) {
                  final item = top[idx];
                  final medal = idx == 0 ? '🥇' : idx == 1 ? '🥈' : '🥉';
                  final borderColor = idx == 0
                      ? const Color(0xFFFFD700)
                      : idx == 1
                          ? const Color(0xFFCFD8DC)
                          : const Color(0xFFFF8A65);

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderColor.withValues(alpha: 0.5), width: 1.3),
                    ),
                    child: Row(
                      children: [
                        Text(medal, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: item.coverFileId.isNotEmpty
                              ? DriveImage(
                                  fileId: item.coverFileId,
                                  width: 52,
                                  height: 72,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  width: 52,
                                  height: 72,
                                  color: Colors.white12,
                                  child: const Icon(Icons.menu_book, color: Colors.white38),
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item.chaptersRead} chương đã đọc',
                                style: TextStyle(
                                  color: borderColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
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
          const Text(
            'Chạm để xem tiếp 👉',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // Slide 3: Genres Breakdown
  Widget _buildSlide3Genres() {
    final genres = widget.data.topGenres.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topGenres = genres.take(5).toList();
    final totalGenreCount = topGenres.fold<int>(0, (sum, e) => sum + e.value);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 100, 28, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            '🎭 GU THỂ LOẠI CHÂN ÁI',
            style: TextStyle(
              color: Colors.tealAccent,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Thế Giới Bạn Đắm Chìm',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 24),
          if (topGenres.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Chưa có đủ dữ liệu thể loại', style: TextStyle(color: Colors.white54)),
              ),
            )
          else
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: topGenres.map((g) {
                  final pct = totalGenreCount > 0 ? (g.value / totalGenreCount) : 0.0;
                  final pctInt = (pct * 100).round();

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              g.key,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$pctInt%',
                              style: const TextStyle(
                                color: Colors.tealAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 8,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.tealAccent),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          const Text(
            'Chạm để xem tiếp 👉',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // Slide 4: Reading Rhythm & Peak Day
  Widget _buildSlide4Rhythm() {
    final d = widget.data;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 100, 28, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            '⏱️ NHỊP ĐIỆU CỦA BẠN',
            style: TextStyle(
              color: Colors.lightBlueAccent,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Khung Giờ Đọc Bất Tận',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blue.withValues(alpha: 0.2),
                  Colors.purple.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                const Icon(Icons.alarm_on_rounded, size: 44, color: Colors.lightBlueAccent),
                const SizedBox(height: 12),
                const Text(
                  'Khung giờ bạn đọc nhiều nhất',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  d.peakHourPeriod,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (d.peakDayChapters > 0)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: Colors.amberAccent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Ngày bạn bùng nổ nhất', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(
                          '${d.peakDayName} cày ${d.peakDayChapters} chương 🚀',
                          style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_fire_department_rounded, color: Colors.deepOrangeAccent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Chuỗi ngày đọc kỷ lục', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(
                        '${d.currentStreak} ngày liên tục 🔥',
                        style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          const Text(
            'Chạm để xem phong cách cày 👉',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // Slide 5: Reading Style & Stats
  Widget _buildSlide5StyleAndStats() {
    final d = widget.data;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 100, 28, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            '📊 PHONG CÁCH ĐỘC GIẢ',
            style: TextStyle(
              color: Colors.cyanAccent,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Chỉ Số Cày Cuốc Của Bạn',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.speed_rounded, color: Colors.cyanAccent, size: 32),
                      const SizedBox(height: 10),
                      Text(
                        d.averageChaptersPerDay.toStringAsFixed(1),
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      const Text('Chương / ngày hoạt động', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 11)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.calendar_month_rounded, color: Colors.tealAccent, size: 32),
                      const SizedBox(height: 10),
                      Text(
                        '${d.activeDays}',
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      const Text('Ngày cày truyện tích lũy', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                const Icon(Icons.military_tech_rounded, color: Colors.amberAccent, size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cấp Bậc Độc Giả', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(
                        d.topTierBadge,
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 13.5, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          const Text(
            'Chạm để hé lộ Danh Hiệu Độc Bản 👉',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // Slide 6: Persona Reveal
  Widget _buildSlide6Persona() {
    final d = widget.data;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 100, 28, 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            '✨ DANH HIỆU ĐỘC BẢN',
            style: TextStyle(
              color: Colors.amberAccent,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tính Cách Độc Giả Của Bạn',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 36),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.pink.shade900.withValues(alpha: 0.8),
                  Colors.purple.shade900.withValues(alpha: 0.8),
                  Colors.black,
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.pinkAccent.withValues(alpha: 0.6), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.pinkAccent.withValues(alpha: 0.25),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(Icons.workspace_premium_rounded, size: 56, color: Colors.amberAccent),
                const SizedBox(height: 14),
                Text(
                  d.readerPersona,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  d.personaDescription,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          const Text(
            'Chạm để xem Thẻ Tổng Kết & Chia Sẻ 👉',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // Slide 7: Final Card & Social Sharing
  Widget _buildSlide7FinalCard() {
    final d = widget.data;
    final hours = (d.estimatedReadingMinutes / 60).toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 30),
      child: Column(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.amber.shade900.withValues(alpha: 0.85),
                    Colors.purple.shade900.withValues(alpha: 0.85),
                    Colors.black,
                  ],
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.6), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.25),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.military_tech_rounded, size: 48, color: Colors.amberAccent),
                  const SizedBox(height: 6),
                  Text(
                    d.seasonTitle.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    d.readerPersona,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildFinalStat('${d.totalChapters}', 'Chương'),
                      _buildFinalStat('~$hours h', 'Thời gian'),
                      _buildFinalStat('${d.totalMangas}', 'Truyện'),
                      _buildFinalStat('${d.currentStreak}d', 'Streak'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 8),
                  Text(
                    d.topTierBadge,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Manga-Reader App • 2026',
                    style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Action Buttons: Copy Text & Share to Forum
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copySummaryToClipboard,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Sao chép tóm tắt', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _shareToForum,
                  icon: const Icon(Icons.forum_rounded, size: 16),
                  label: const Text('Khoe Diễn Đàn', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amberAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hoàn tất & Đóng', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCol(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.amberAccent,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildFinalStat(String val, String label) {
    return Column(
      children: [
        Text(
          val,
          style: const TextStyle(
            color: Colors.amberAccent,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}
