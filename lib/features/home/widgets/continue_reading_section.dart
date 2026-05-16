import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../../data/database_helper.dart';
import '../../../data/models.dart';
import '../../../data/drive_service.dart';
import '../../shared/drive_image.dart';

class ContinueReadingSection extends StatefulWidget {
  const ContinueReadingSection({super.key});

  @override
  State<ContinueReadingSection> createState() => _ContinueReadingSectionState();
}

class _ContinueReadingSectionState extends State<ContinueReadingSection> {
  List<ReadingHistory> _recentHistory = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    final all = await DatabaseHelper.instance.getHistory(uid);
    if (mounted) {
      setState(() {
        _recentHistory = all
            .where((h) => h.chapterId.isNotEmpty && h.chapterTitle != null)
            .take(3)
            .toList();
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _recentHistory.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final topItem = _recentHistory.first;
    final coverId = _extractCoverFileId(topItem.mangaId);

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // NETFLIX STYLE HERO BANNER
          GestureDetector(
            onTap: () => context.push('/reader/${topItem.chapterId}'),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Blurred Background
                    DriveImage(fileId: coverId, fit: BoxFit.cover),
                    BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                    ),

                    // Content
                    Row(
                      children: [
                        // Cover Image
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 110,
                              height: 160,
                              child: DriveImage(
                                fileId: coverId,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        // Details
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 20,
                              horizontal: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FutureBuilder<String>(
                                  future: _getMangaTitle(topItem.mangaId),
                                  builder: (context, snapshot) => Text(
                                    snapshot.data ?? '...',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  topItem.chapterTitle ?? 'Đang đọc...',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
                                ),
                                const Spacer(),

                                // Progress Bar
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Tiến độ',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.white54,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: const LinearProgressIndicator(
                                        value: 0.5, // Giả lập tiến độ 50%
                                        backgroundColor: Colors.white24,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.redAccent,
                                            ),
                                        minHeight: 6,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Button
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.play_arrow,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Đọc Tiếp',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Các truyện khác đang đọc
          if (_recentHistory.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 5),
              child: Text(
                'Lịch sử đọc',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: Colors.white54),
              ),
            ),
          if (_recentHistory.length > 1)
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _recentHistory.length - 1,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return _SmallHistoryCard(history: _recentHistory[index + 1]);
                },
              ),
            ),
        ],
      ),
    );
  }

  String _extractCoverFileId(String mangaId) {
    final cached = DriveService.instance.cachedMangas;
    if (cached == null || cached.isEmpty) return mangaId;
    for (final manga in cached) {
      if (manga.id == mangaId) return manga.coverFileId;
    }
    return mangaId;
  }

  Future<String> _getMangaTitle(String mangaId) async {
    final cached = DriveService.instance.cachedMangas;
    for (final manga in cached ?? const []) {
      if (manga.id == mangaId) return manga.title;
    }
    return 'Truyện';
  }
}

class _SmallHistoryCard extends StatelessWidget {
  final ReadingHistory history;
  const _SmallHistoryCard({required this.history});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/reader/${history.chapterId}'),
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(8),
              ),
              child: SizedBox(
                width: 60,
                height: 100,
                child: DriveImage(
                  fileId: _extractCoverFileId(history.mangaId),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FutureBuilder<String>(
                      future: _getMangaTitle(history.mangaId),
                      builder: (context, snapshot) => Text(
                        snapshot.data ?? '...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      history.chapterTitle ?? '...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _extractCoverFileId(String mangaId) {
    final cached = DriveService.instance.cachedMangas;
    if (cached == null || cached.isEmpty) return mangaId;
    for (final manga in cached) {
      if (manga.id == mangaId) return manga.coverFileId;
    }
    return mangaId;
  }

  Future<String> _getMangaTitle(String mangaId) async {
    final cached = DriveService.instance.cachedMangas;
    for (final manga in cached ?? const []) {
      if (manga.id == mangaId) return manga.title;
    }
    return 'Truyện';
  }
}
