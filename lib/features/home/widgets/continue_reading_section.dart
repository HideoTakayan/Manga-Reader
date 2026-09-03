import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../../data/content_type.dart';
import '../../../data/database_helper.dart';
import '../../../data/models.dart';
import '../../../data/drive_service.dart';
import '../../../services/folder_service.dart';
import '../../catalog/catalog_cache_service.dart';
import '../../shared/drive_image.dart';

class ContinueReadingSection extends StatefulWidget {
  const ContinueReadingSection({super.key});

  @override
  State<ContinueReadingSection> createState() => _ContinueReadingSectionState();
}

class _ContinueReadingSectionState extends State<ContinueReadingSection> {
  List<ReadingHistory> _recentHistory = [];
  Map<String, String> _coverMap = {};
  Map<String, String> _titleMap = {};
  Map<String, MangaContentType> _typeMap = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final all = await DatabaseHelper.instance.getHistory(uid);
    if (!mounted) return;

    final historyItems = all
        .where(
          (h) =>
              h.chapterId.isNotEmpty &&
              h.chapterTitle != null &&
              !h.mangaId.startsWith('LOCAL_NOVEL|') &&
              !h.mangaId.startsWith('local_'),
        )
        .take(3)
        .toList();

    final coverMap = <String, String>{};
    final titleMap = <String, String>{};
    final typeMap = <String, MangaContentType>{};

    for (final item in historyItems) {
      // 1. Kiểm tra cache DriveService nếu có
      final cachedManga = DriveService.instance.cachedMangas
          ?.where((m) => m.id == item.mangaId)
          .firstOrNull;
      if (cachedManga != null) {
        coverMap[item.mangaId] = cachedManga.coverFileId;
        titleMap[item.mangaId] = cachedManga.title;
        typeMap[item.mangaId] = cachedManga.contentType;
        continue;
      }

      // 2. Kiểm tra SQLite local database
      final local = await DatabaseHelper.instance.getLocalManga(item.mangaId);
      if (local != null) {
        String cover = local.coverUrl;
        if (!cover.startsWith('/') && !cover.contains('\\')) {
          if (await FolderService.hasCover(local.title)) {
            cover = await FolderService.getCoverPath(local.title);
          }
        }
        coverMap[item.mangaId] = cover;
        titleMap[item.mangaId] = local.title;
        typeMap[item.mangaId] = local.contentType;
        continue;
      }

      // 3. Kiểm tra Catalog Cache Service
      try {
        final catalog = await CatalogCacheService.instance.getCachedCatalog();
        final match = catalog.where((m) => m.id == item.mangaId).firstOrNull;
        if (match != null) {
          coverMap[item.mangaId] = match.coverFileId;
          titleMap[item.mangaId] = match.title;
          typeMap[item.mangaId] = match.contentType;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _recentHistory = historyItems;
        _coverMap = coverMap;
        _titleMap = titleMap;
        _typeMap = typeMap;
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
    final coverId = _coverMap[topItem.mangaId] ?? _extractCoverFileId(topItem.mangaId);
    final mangaTitle = _titleMap[topItem.mangaId] ?? 'Đang đọc';
    final contentType = _typeMap[topItem.mangaId];

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // NETFLIX STYLE HERO BANNER
          GestureDetector(
            onTap: () async {
              HapticFeedback.selectionClick();
              await context.push(
                '/reader/${topItem.chapterId}?mangaId=${Uri.encodeComponent(topItem.mangaId)}&page=${topItem.lastPageIndex}',
              );
              if (mounted) {
                _load();
              }
            },
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
                            padding: const EdgeInsets.fromLTRB(4, 12, 14, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mangaTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (contentType != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: _ContentTypeBadge(type: contentType),
                                  ),
                                Text(
                                  topItem.chapterTitle ?? 'Đang đọc...',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
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
                                        value: (topItem.totalPages <= 1
                                                ? 1.0
                                                : topItem.lastPageIndex /
                                                    (topItem.totalPages - 1))
                                            .clamp(0.0, 1.0),
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
