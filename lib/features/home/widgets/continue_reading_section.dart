import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../../data/content_type.dart';
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
            onTap: () => context.push(
              '/reader/${topItem.chapterId}?mangaId=${Uri.encodeComponent(topItem.mangaId)}',
            ),
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
                                FutureBuilder<MangaContentType?>(
                                  future: _getMangaContentType(topItem.mangaId),
                                  builder: (context, snapshot) {
                                    final type = snapshot.data;
                                    if (type == null) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _ContentTypeBadge(type: type),
                                    );
                                  },
                                ),
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
                                      child: LinearProgressIndicator(
                                        value: topItem.totalPages <= 1
                                            ? 1.0
                                            : topItem.lastPageIndex /
                                                  (topItem.totalPages - 1),
                                        backgroundColor: Colors.white24,
                                        valueColor:
                                            const AlwaysStoppedAnimation<Color>(
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

  Future<MangaContentType?> _getMangaContentType(String mangaId) async {
    final cached = DriveService.instance.cachedMangas;
    for (final manga in cached ?? const []) {
      if (manga.id == mangaId) return manga.contentType;
    }
    final local = await DatabaseHelper.instance.getLocalManga(mangaId);
    return local?.contentType;
  }
}

class _ContentTypeBadge extends StatelessWidget {
  final MangaContentType type;
  const _ContentTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        type.label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
