import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../data/database_helper.dart';
import '../../data/content_type.dart';
import '../../data/models.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../../services/history_service.dart';
import '../../services/novel_service.dart';
import '../catalog/catalog_cache_service.dart';
import '../shared/drive_image.dart';
import 'package:manga_reader/services/auth_service.dart';

enum HistoryProgressFilter {
  all,        // Tất cả
  inProgress, // Đang đọc dở
  completed,  // Đã đọc xong
}

class HistoryGroupedSection {
  final String title;
  final IconData icon;
  final List<ReadingHistory> items;

  HistoryGroupedSection({
    required this.title,
    required this.icon,
    required this.items,
  });
}

// Trang lịch sử đọc truyện — Phân nhóm theo mốc thời gian (Hôm nay, Hôm qua, 7 ngày qua, Tháng này, Cũ hơn),
// hiển thị thời gian đọc tương đối và hỗ trợ xóa hàng loạt theo nhóm / chọn nhiều.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with AutomaticKeepAliveClientMixin {
  List<ReadingHistory> _historyList = [];
  List<CloudManga> _mangas = [];
  Map<String, CloudManga> _fallbackMangaMap = {};
  Map<String, CloudManga> _resolvedMangaMap = {};
  Map<String, ReaderProgress> _progressMap = {};
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  MangaContentType? _selectedTypeFilter;
  HistoryProgressFilter _progressFilter = HistoryProgressFilter.all;
  Timer? _searchDebounce;

  // Multi-selection state
  final Set<String> _selectedMangaIds = {};
  bool _isSelectionMode = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _rebuildResolvedMangaMap() {
    final map = <String, CloudManga>{};
    for (final item in _historyList) {
      map[item.mangaId] = _resolveManga(item);
    }
    _resolvedMangaMap = map;
  }

  Future<void> _initData({bool forceRefresh = false}) async {
    if (!mounted) return;
    if (!forceRefresh && _historyList.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      List<CloudManga> mangas = [];
      try {
        mangas = await DriveService.instance.getMangas(
          forceRefresh: forceRefresh,
        );
      } catch (e) {
        debugPrint('⚠️ Drive getMangas failed in history, falling back to cache: $e');
        mangas = await CatalogCacheService.instance.getCachedCatalog();
      }

      final Map<String, CloudManga> fallbackMap = {for (final m in mangas) m.id: m};
      try {
        final localMangas = await DatabaseHelper.instance.getAllLocalMangas();
        for (final lm in localMangas) {
          if (!fallbackMap.containsKey(lm.id)) {
            fallbackMap[lm.id] = CloudManga(
              id: lm.id,
              title: lm.title,
              coverFileId: lm.coverUrl,
              author: lm.author,
              description: lm.description,
              genres: lm.genres,
              status: 'Offline',
              updatedAt: DateTime.now(),
              chapterOrder: const [],
              contentType: lm.contentType,
            );
          }
        }
      } catch (_) {}

      final hList = await _fetchAndMergeHistory();
      final pMap = await DatabaseHelper.instance.getAllReaderProgressMap();
      if (mounted) {
        setState(() {
          _mangas = mangas;
          _fallbackMangaMap = fallbackMap;
          _historyList = hList;
          _progressMap = pMap;
          _rebuildResolvedMangaMap();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('History Init Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<ReadingHistory>> _fetchAndMergeHistory() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final localId = AuthService.safeUid;
    final localHistory = await DatabaseHelper.instance.getHistory(localId);

    List<ReadingHistory> cloudHistory = [];
    if (userId != null) {
      cloudHistory = await HistoryService.instance.getAllHistory();
    }

    final historyMap = <String, ReadingHistory>{};
    for (var h in localHistory) {
      historyMap[h.mangaId] = h;
    }
    for (var h in cloudHistory) {
      if (h.mangaId.startsWith('LOCAL_NOVEL|') ||
          h.mangaId.startsWith('local_')) {
        continue;
      }
      if (historyMap.containsKey(h.mangaId)) {
        if (h.updatedAt.isAfter(historyMap[h.mangaId]!.updatedAt)) {
          historyMap[h.mangaId] = h;
        }
      } else {
        historyMap[h.mangaId] = h;
      }
    }

    final merged = historyMap.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (userId != null && merged.isNotEmpty) {
      final cloudSavable = merged
          .where(
            (h) =>
                !h.mangaId.startsWith('LOCAL_NOVEL|') &&
                !h.mangaId.startsWith('local_'),
          )
          .map(
            (h) => h.userId == userId
                ? h
                : ReadingHistory(
                    userId: userId,
                    mangaId: h.mangaId,
                    chapterId: h.chapterId,
                    chapterTitle: h.chapterTitle,
                    lastPageIndex: h.lastPageIndex,
                    totalPages: h.totalPages,
                    updatedAt: h.updatedAt,
                  ),
          )
          .toList();
      if (cloudSavable.isNotEmpty) {
        await DatabaseHelper.instance.saveHistoryBatch(cloudSavable, alreadySynced: true);
      }
    }

    return merged;
  }

  Future<void> _handleDeepClear() async {
    if (mounted) setState(() => _isLoading = true);
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final localId = AuthService.safeUid;

    try {
      await DatabaseHelper.instance.clearHistory(localId);
      if (userId != null && userId != localId) {
        await DatabaseHelper.instance.clearHistory(userId);
      }
      if (userId != null) {
        await HistoryService.instance.clearAllHistory();
      }
      if (mounted) {
        setState(() {
          _historyList = [];
          _selectedMangaIds.clear();
          _isSelectionMode = false;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã xoá sạch lịch sử!')));
      }
    } catch (e) {
      debugPrint('Clear Error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi xoá lịch sử: $e')));
      }
    }
  }

  Future<void> _deleteSingleHistory(ReadingHistory item, String mangaTitle) async {
    HapticFeedback.lightImpact();
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final localId = AuthService.safeUid;
    final mangaId = item.mangaId;

    setState(() {
      _historyList.removeWhere((h) => h.mangaId == mangaId);
      _resolvedMangaMap.remove(mangaId);
      _selectedMangaIds.remove(mangaId);
      if (_selectedMangaIds.isEmpty) _isSelectionMode = false;
    });

    try {
      await DatabaseHelper.instance.deleteReaderProgress(mangaId);
      await DatabaseHelper.instance.deleteHistoryForManga(localId, mangaId);
      if (userId != null && userId != localId) {
        await DatabaseHelper.instance.deleteHistoryForManga(userId, mangaId);
      }
      if (userId != null) {
        await HistoryService.instance.deleteHistory(mangaId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã xóa "$mangaTitle" khỏi lịch sử'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting single history: $e');
    }
  }

  Future<void> _deleteGroupHistory(List<ReadingHistory> items, String groupTitle) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        return AlertDialog(
          backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Xóa lịch sử "$groupTitle"?', style: TextStyle(color: onSurface, fontWeight: FontWeight.bold)),
          content: Text('Bạn có chắc muốn xóa ${items.length} truyện trong nhóm $groupTitle?', style: TextStyle(color: onSurface.withValues(alpha: 0.7))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Xóa nhóm', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;
    if (!mounted) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    final localId = AuthService.safeUid;
    final ids = items.map((i) => i.mangaId).toSet();

    setState(() {
      _historyList.removeWhere((h) => ids.contains(h.mangaId));
      for (final id in ids) {
        _resolvedMangaMap.remove(id);
        _selectedMangaIds.remove(id);
      }
      if (_selectedMangaIds.isEmpty) _isSelectionMode = false;
    });

    for (final id in ids) {
      await DatabaseHelper.instance.deleteReaderProgress(id);
      await DatabaseHelper.instance.deleteHistoryForManga(localId, id);
      if (userId != null && userId != localId) {
        await DatabaseHelper.instance.deleteHistoryForManga(userId, id);
      }
      if (userId != null) {
        await HistoryService.instance.deleteHistory(id);
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xóa ${items.length} mục trong "$groupTitle"'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteSelectedBatch() async {
    if (_selectedMangaIds.isEmpty) return;

    final count = _selectedMangaIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        return AlertDialog(
          backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Xóa $count mục đã chọn?', style: TextStyle(color: onSurface, fontWeight: FontWeight.bold)),
          content: Text('Các mục được chọn sẽ bị xóa khỏi lịch sử đọc.', style: TextStyle(color: onSurface.withValues(alpha: 0.7))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Xóa', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;
    if (!mounted) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    final localId = AuthService.safeUid;
    final idsToDelete = Set<String>.from(_selectedMangaIds);

    setState(() {
      _historyList.removeWhere((h) => idsToDelete.contains(h.mangaId));
      for (final id in idsToDelete) {
        _resolvedMangaMap.remove(id);
      }
      _selectedMangaIds.clear();
      _isSelectionMode = false;
    });

    for (final id in idsToDelete) {
      await DatabaseHelper.instance.deleteReaderProgress(id);
      await DatabaseHelper.instance.deleteHistoryForManga(localId, id);
      if (userId != null && userId != localId) {
        await DatabaseHelper.instance.deleteHistoryForManga(userId, id);
      }
      if (userId != null) {
        await HistoryService.instance.deleteHistory(id);
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xóa $count mục khỏi lịch sử'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  CloudManga _resolveManga(ReadingHistory item) {
    if (item.mangaId.startsWith('LOCAL_NOVEL|')) {
      final path = item.mangaId.substring('LOCAL_NOVEL|'.length);
      final filename = path
          .split(RegExp(r'[\\/]'))
          .last
          .replaceAll(RegExp(r'\.epub$', caseSensitive: false), '');
      return CloudManga(
        id: item.mangaId,
        title: item.chapterTitle != null && item.chapterTitle!.isNotEmpty
            ? item.chapterTitle!
            : (filename.isNotEmpty ? filename : 'Truyện chữ'),
        author: 'Local EPUB',
        description: '',
        coverFileId: '',
        genres: const [],
        status: 'Hoàn thành',
        viewCount: 0,
        likeCount: 0,
        updatedAt: item.updatedAt,
        contentType: MangaContentType.novel,
      );
    }
    if (_fallbackMangaMap.containsKey(item.mangaId)) {
      return _fallbackMangaMap[item.mangaId]!;
    }
    return _mangas.firstWhere(
      (c) => c.id == item.mangaId,
      orElse: () {
        // HIST-01 fix: show chapterTitle or a readable fallback, never raw mangaId
        final displayTitle = (item.chapterTitle != null && item.chapterTitle!.isNotEmpty)
            ? item.chapterTitle!
            : 'Truyện không tồn tại';
        return CloudManga(
          id: item.mangaId,
          title: displayTitle,
          author: 'Không rõ tác giả',
          description: '',
          coverFileId: '',
          genres: const [],
          status: '',
          viewCount: 0,
          likeCount: 0,
          updatedAt: DateTime.now(),
        );
      },
    );
  }

  bool _isMangaCompleted(ReadingHistory item) {
    final prog = _progressMap[item.mangaId];
    final manga = _resolvedMangaMap[item.mangaId] ?? _resolveManga(item);

    if (item.mangaId.startsWith('LOCAL_NOVEL|') || manga.contentType == MangaContentType.novel) {
      return prog != null && prog.progressPercent >= 0.95;
    }

    if (manga.chapterOrder.isNotEmpty) {
      final lastChapterId = manga.chapterOrder.last;
      if (item.chapterId == lastChapterId && prog != null && prog.progressPercent >= 0.85) {
        return true;
      }
      return false;
    }

    return prog != null && prog.progressPercent >= 0.95;
  }

  List<ReadingHistory> get _filteredHistoryList {
    final query = CatalogCacheService.instance.normalize(_searchQuery);
    return _historyList.where((item) {
      final manga = _resolvedMangaMap[item.mangaId] ?? _resolveManga(item);
      if (_selectedTypeFilter != null && manga.contentType != _selectedTypeFilter) {
        return false;
      }

      if (_progressFilter == HistoryProgressFilter.inProgress) {
        if (_isMangaCompleted(item)) return false;
      } else if (_progressFilter == HistoryProgressFilter.completed) {
        if (!_isMangaCompleted(item)) return false;
      }

      if (query.isEmpty) return true;
      final normTitle = CatalogCacheService.instance.normalize(manga.title);
      final normAuthor = CatalogCacheService.instance.normalize(manga.author);
      final normChapter =
          CatalogCacheService.instance.normalize(item.chapterTitle ?? '');
      return normTitle.contains(query) ||
          normAuthor.contains(query) ||
          normChapter.contains(query);
    }).toList();
  }

  List<HistoryGroupedSection> _groupHistory(List<ReadingHistory> list) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final last7DaysStart = todayStart.subtract(const Duration(days: 7));
    final thisMonthStart = DateTime(now.year, now.month, 1);

    final today = <ReadingHistory>[];
    final yesterday = <ReadingHistory>[];
    final last7Days = <ReadingHistory>[];
    final thisMonth = <ReadingHistory>[];
    final older = <ReadingHistory>[];

    for (final item in list) {
      if (item.updatedAt.isAfter(todayStart)) {
        today.add(item);
      } else if (item.updatedAt.isAfter(yesterdayStart)) {
        yesterday.add(item);
      } else if (item.updatedAt.isAfter(last7DaysStart)) {
        last7Days.add(item);
      } else if (item.updatedAt.isAfter(thisMonthStart)) {
        thisMonth.add(item);
      } else {
        older.add(item);
      }
    }

    final sections = <HistoryGroupedSection>[];
    if (today.isNotEmpty) {
      sections.add(HistoryGroupedSection(title: 'Hôm nay', icon: Icons.today_rounded, items: today));
    }
    if (yesterday.isNotEmpty) {
      sections.add(HistoryGroupedSection(title: 'Hôm qua', icon: Icons.history_toggle_off_rounded, items: yesterday));
    }
    if (last7Days.isNotEmpty) {
      sections.add(HistoryGroupedSection(title: '7 ngày qua', icon: Icons.calendar_view_week_rounded, items: last7Days));
    }
    if (thisMonth.isNotEmpty) {
      sections.add(HistoryGroupedSection(title: 'Tháng này', icon: Icons.calendar_month_rounded, items: thisMonth));
    }
    if (older.isNotEmpty) {
      sections.add(HistoryGroupedSection(title: 'Cũ hơn', icon: Icons.archive_outlined, items: older));
    }

    return sections;
  }

  String _formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24 && dt.day == now.day) return '${diff.inHours} giờ trước ($timeStr)';
    if (now.day - dt.day == 1 && diff.inHours < 48) return 'Hôm qua lúc $timeStr';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} lúc $timeStr';
  }

  void _showDeleteConfirmDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        return AlertDialog(
          backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Xoá tất cả?', style: TextStyle(color: onSurface, fontWeight: FontWeight.bold)),
          content: Text(
            'Hành động này sẽ xoá vĩnh viễn toàn bộ lịch sử đọc truyện của bạn (Cả trên máy và Cloud).',
            style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Huỷ', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _handleDeepClear();
              },
              child: const Text('Xoá sạch', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openReader(ReadingHistory item, CloudManga manga) async {
    if (item.mangaId.startsWith('LOCAL_NOVEL|')) {
      final novel = LocalNovel(
        path: item.mangaId.substring('LOCAL_NOVEL|'.length),
        title: manga.title,
        coverPath: manga.coverFileId,
        importedAt: item.updatedAt,
      );
      await context.push('/novel-reader', extra: novel);
    } else {
      await context.push(
        '/reader/${item.chapterId}?mangaId=${Uri.encodeComponent(item.mangaId)}&page=${item.lastPageIndex}',
      );
    }
    if (mounted) _initData();
  }

  Widget _buildResumeReadingHeroCard(ReadingHistory item, CloudManga manga) {
    final isNovel = item.mangaId.startsWith('LOCAL_NOVEL|') || manga.contentType == MangaContentType.novel;
    // HIST-02 fix: use progressMap as single source of truth for percent when available.
    // Fall back to page-count math only when no progress entry exists.
    final progEntry = _progressMap[item.mangaId];
    final double percent;
    final int current;
    final int total = item.totalPages > 0 ? item.totalPages : 1;
    if (progEntry != null && progEntry.progressPercent > 0) {
      percent = progEntry.progressPercent.clamp(0.0, 1.0);
      current = (percent * total).round().clamp(1, total);
    } else {
      current = (item.lastPageIndex + 1).clamp(1, total);
      percent = (current / total).clamp(0.0, 1.0);
    }
    final percentText = (percent * 100).toInt();
    final relativeTime = _formatRelativeTime(item.updatedAt);

    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withValues(alpha: 0.18),
            primary.withValues(alpha: 0.06),
            Theme.of(context).cardColor,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primary.withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: Colors.black.withValues(alpha: 0.25),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'TIẾP TỤC ĐỌC GẦN ĐÂY',
                  style: TextStyle(
                    color: primary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                Icon(Icons.access_time_rounded, size: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Text(
                  relativeTime,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => context.push('/detail/${item.mangaId}'),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: manga.coverFileId.isNotEmpty
                            ? (manga.coverFileId.startsWith('/') || manga.coverFileId.contains(':\\')
                                ? Image.file(
                                    File(manga.coverFileId),
                                    width: 76,
                                    height: 106,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 76,
                                      height: 106,
                                      color: Colors.white12,
                                      child: const Icon(Icons.broken_image, color: Colors.white38),
                                    ),
                                  )
                                : DriveImage(
                                    fileId: manga.coverFileId,
                                    width: 76,
                                    height: 106,
                                    fit: BoxFit.cover,
                                  ))
                            : Container(
                                width: 76,
                                height: 106,
                                color: Colors.white12,
                                child: const Icon(Icons.menu_book, color: Colors.white38),
                              ),
                      ),
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isNovel ? 'NOVEL' : 'MANGA',
                            style: TextStyle(
                              color: isNovel ? Colors.amber : primary,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () => context.push('/detail/${item.mangaId}'),
                        child: Text(
                          manga.title,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (item.chapterTitle != null && item.chapterTitle!.isNotEmpty)
                            ? item.chapterTitle!
                            : 'Đang đọc dở',
                        style: TextStyle(
                          color: primary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: percent,
                                minHeight: 6,
                                backgroundColor: Colors.white.withValues(alpha: 0.1),
                                valueColor: AlwaysStoppedAnimation<Color>(primary),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            !isNovel && item.totalPages > 0
                                ? '$current/$total ($percentText%)'
                                : '$percentText%',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _openReader(item, manga),
                              icon: const Icon(Icons.play_arrow_rounded, size: 20),
                              label: const Text(
                                'Đọc tiếp',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primary,
                                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => context.push('/detail/${item.mangaId}'),
                            icon: Icon(
                              Icons.info_outline_rounded,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                              size: 20,
                            ),
                            tooltip: 'Chi tiết truyện',
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_historyList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.history_rounded,
                  size: 54,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Chưa có lịch sử đọc truyện',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Các chương truyện bạn đã đọc sẽ tự động lưu lại ở đây để bạn dễ dàng tiếp tục theo dõi.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white60,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _initData,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Tải lại'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => context.go('/search-global'),
                    icon: const Icon(Icons.explore_rounded, size: 16),
                    label: const Text('Khám phá truyện', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredHistoryList;
    final sections = _groupHistory(filtered);

    final onSurface = Theme.of(context).colorScheme.onSurface;
    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isSelectionMode) {
          setState(() {
            _isSelectionMode = false;
            _selectedMangaIds.clear();
          });
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            _isSelectionMode
                ? 'Đã chọn ${_selectedMangaIds.length}'
                : '${filtered.length} truyện đã lưu',
            style: TextStyle(
              fontWeight: _isSelectionMode ? FontWeight.bold : FontWeight.w500,
              fontSize: _isSelectionMode ? 16 : 13,
              color: _isSelectionMode ? onSurface : onSurface.withValues(alpha: 0.6),
            ),
          ),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: _isSelectionMode
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() {
                    _isSelectionMode = false;
                    _selectedMangaIds.clear();
                  }),
                )
              : null,
          actions: [
            if (_isSelectionMode) ...[
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_selectedMangaIds.length == filtered.length) {
                      _selectedMangaIds.clear();
                    } else {
                      _selectedMangaIds.addAll(filtered.map((e) => e.mangaId));
                    }
                  });
                },
                child: Text(
                  _selectedMangaIds.length == filtered.length ? 'Bỏ chọn' : 'Chọn tất cả',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.redAccent),
                tooltip: 'Xóa các mục đã chọn',
                onPressed: _deleteSelectedBatch,
              ),
            ] else ...[
              IconButton(
                icon: const Icon(Icons.checklist_rounded),
                tooltip: 'Chọn nhiều mục',
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  setState(() => _isSelectionMode = true);
                },
              ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
              tooltip: 'Xóa tất cả lịch sử',
              onPressed: _showDeleteConfirmDialog,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Thanh tìm kiếm
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Tìm theo tên truyện hoặc chương...',
                  hintStyle: const TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 16,
                    color: Colors.white54,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            size: 14,
                            color: Colors.white54,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onChanged: (val) {
                  if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
                  _searchDebounce = Timer(const Duration(milliseconds: 200), () {
                    if (mounted) setState(() => _searchQuery = val);
                  });
                },
              ),
            ),
          ),

          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  Text(
                    '${filtered.length} mục',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 1,
                    height: 16,
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: 10),
                  _buildFilterChip(
                    label: 'Tất cả',
                    isSelected: _progressFilter == HistoryProgressFilter.all,
                    onTap: () => setState(() => _progressFilter = HistoryProgressFilter.all),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    label: '⚡ Đang đọc dở',
                    isSelected: _progressFilter == HistoryProgressFilter.inProgress,
                    onTap: () => setState(() => _progressFilter = HistoryProgressFilter.inProgress),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    label: '✓ Đã đọc xong',
                    isSelected: _progressFilter == HistoryProgressFilter.completed,
                    onTap: () => setState(() => _progressFilter = HistoryProgressFilter.completed),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 1,
                    height: 16,
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: 10),
                  _buildFilterChip(
                    label: 'Tất cả định dạng',
                    isSelected: _selectedTypeFilter == null,
                    onTap: () => setState(() => _selectedTypeFilter = null),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    label: 'Truyện tranh',
                    isSelected: _selectedTypeFilter == MangaContentType.manga,
                    onTap: () => setState(() => _selectedTypeFilter = MangaContentType.manga),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    label: 'Tiểu thuyết',
                    isSelected: _selectedTypeFilter == MangaContentType.novel,
                    onTap: () => setState(() => _selectedTypeFilter = MangaContentType.novel),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _initData(forceRefresh: true),
              child: filtered.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Text(
                            'Không tìm thấy truyện phù hợp',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: sections.length,
                      itemBuilder: (context, sectionIndex) {
                        final section = sections[sectionIndex];
                        final showHero = sectionIndex == 0 &&
                            _searchQuery.isEmpty &&
                            !_isSelectionMode &&
                            _progressFilter == HistoryProgressFilter.all &&
                            _selectedTypeFilter == null &&
                            _historyList.isNotEmpty;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showHero)
                              _buildResumeReadingHeroCard(
                                _historyList.first,
                                _resolvedMangaMap[_historyList.first.mangaId] ?? _resolveManga(_historyList.first),
                              ),

                            // Section Header
                            Padding(
                              padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
                              child: Row(
                                children: [
                                  Icon(
                                    section.icon,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    section.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${section.items.length}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (!_isSelectionMode)
                                    InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () => _deleteGroupHistory(section.items, section.title),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        child: Text(
                                          'Xóa nhóm',
                                          style: TextStyle(
                                            color: Colors.redAccent.withValues(alpha: 0.8),
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            // Items in this section
                            ...section.items.map((item) {
                              final manga = _resolvedMangaMap[item.mangaId] ?? _resolveManga(item);
                              final isSelected = _selectedMangaIds.contains(item.mangaId);
                              final relativeTime = _formatRelativeTime(item.updatedAt);

                              return Dismissible(
                                key: ValueKey(item.mangaId),
                                direction: _isSelectionMode
                                    ? DismissDirection.none
                                    : DismissDirection.endToStart,
                                background: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                  padding: const EdgeInsets.only(right: 20),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  alignment: Alignment.centerRight,
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Xóa',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.delete_sweep, color: Colors.white, size: 24),
                                    ],
                                  ),
                                ),
                                onDismissed: (_) => _deleteSingleHistory(item, manga.title),
                                child: Container(
                                // HIST-03 fix: use minHeight constraint instead of fixed height
                                  constraints: const BoxConstraints(minHeight: 110),
                                  margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                                        : Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(16),
                                    border: isSelected
                                        ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5)
                                        : Border.all(color: Colors.white.withValues(alpha: 0.05)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () async {
                                      if (_isSelectionMode) {
                                        HapticFeedback.selectionClick();
                                        setState(() {
                                          if (isSelected) {
                                            _selectedMangaIds.remove(item.mangaId);
                                          } else {
                                            _selectedMangaIds.add(item.mangaId);
                                          }
                                        });
                                        return;
                                      }

                                      await _openReader(item, manga);
                                    },
                                    onLongPress: () {
                                      HapticFeedback.heavyImpact();
                                      setState(() {
                                        _isSelectionMode = true;
                                        if (isSelected) {
                                          _selectedMangaIds.remove(item.mangaId);
                                        } else {
                                          _selectedMangaIds.add(item.mangaId);
                                        }
                                      });
                                    },
                                    child: Row(
                                      children: [
                                        if (_isSelectionMode)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 10),
                                            child: Icon(
                                              isSelected
                                                  ? Icons.check_circle_rounded
                                                  : Icons.radio_button_unchecked_rounded,
                                              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white38,
                                              size: 22,
                                            ),
                                          ),

                                        // HIST-05 fix: handle local file paths like the hero card does
                                        manga.coverFileId.isNotEmpty
                                            ? (manga.coverFileId.startsWith('/') || manga.coverFileId.contains(':\\')
                                                ? ClipRRect(
                                                    borderRadius: const BorderRadius.only(
                                                      topLeft: Radius.circular(16),
                                                      bottomLeft: Radius.circular(16),
                                                    ),
                                                    child: Image.file(
                                                      File(manga.coverFileId),
                                                      width: 85,
                                                      height: 120,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, __, ___) => Container(
                                                        width: 85,
                                                        height: 120,
                                                        color: Colors.blueGrey.withValues(alpha: 0.2),
                                                        child: const Icon(Icons.menu_book_rounded, size: 36, color: Colors.white38),
                                                      ),
                                                    ),
                                                  )
                                                : DriveImage(
                                                    fileId: manga.coverFileId,
                                                    width: 85,
                                                    height: 120,
                                                    fit: BoxFit.cover,
                                                  ))
                                            : Container(
                                                width: 85,
                                                height: 120,
                                                decoration: BoxDecoration(
                                                  color: Colors.blueGrey.withValues(alpha: 0.2),
                                                  borderRadius: const BorderRadius.only(
                                                    topLeft: Radius.circular(16),
                                                    bottomLeft: Radius.circular(16),
                                                  ),
                                                ),
                                                child: const Center(
                                                  child: Icon(
                                                    Icons.menu_book_rounded,
                                                    size: 36,
                                                    color: Colors.white38,
                                                  ),
                                                ),
                                              ),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        manga.title,
                                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 15,
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    if (!_isSelectionMode)
                                                      IconButton(
                                                        visualDensity: VisualDensity.compact,
                                                        padding: EdgeInsets.zero,
                                                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                        icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                                                        tooltip: 'Xóa khỏi lịch sử',
                                                        onPressed: () => _deleteSingleHistory(item, manga.title),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Icon(Icons.menu_book_rounded, size: 13, color: Theme.of(context).colorScheme.primary),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        '${(item.chapterTitle != null && item.chapterTitle!.isNotEmpty) ? item.chapterTitle : 'Chương ${item.chapterId}'} • Trang ${item.lastPageIndex + 1}',
                                                        style: TextStyle(
                                                          color: Theme.of(context).colorScheme.primary,
                                                          fontSize: 12.5,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (_progressMap.containsKey(item.mangaId) &&
                                                     _progressMap[item.mangaId]!.progressPercent > 0) ...[
                                                  const SizedBox(height: 5),
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(2),
                                                    child: LinearProgressIndicator(
                                                      value: _progressMap[item.mangaId]!.progressPercent.clamp(0.0, 1.0),
                                                      minHeight: 3,
                                                      backgroundColor: Colors.white10,
                                                      valueColor: AlwaysStoppedAnimation<Color>(
                                                        _isMangaCompleted(item) ? Colors.greenAccent : Theme.of(context).colorScheme.primary,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                                const Spacer(),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.access_time_rounded, size: 13, color: Colors.white54),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          relativeTime,
                                                          style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                                                        ),
                                                      ],
                                                    ),
                                                    Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                          margin: const EdgeInsets.only(right: 6),
                                                          decoration: BoxDecoration(
                                                            color: _isMangaCompleted(item)
                                                                ? Colors.green.withValues(alpha: 0.15)
                                                                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(4),
                                                            border: Border.all(
                                                              color: _isMangaCompleted(item)
                                                                  ? Colors.greenAccent.withValues(alpha: 0.4)
                                                                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                                                            ),
                                                          ),
                                                          child: Text(
                                                            _isMangaCompleted(item)
                                                                ? 'Xong'
                                                                // HIST-04 fix: show 'Đang đọc' even when progressPercent==0
                                                                : 'Đang đọc',
                                                            style: TextStyle(
                                                              color: _isMangaCompleted(item) ? Colors.greenAccent : Theme.of(context).colorScheme.primary,
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ),
                                                        _ContentTypeBadge(type: manga.contentType),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor.withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContentTypeBadge extends StatelessWidget {
  final MangaContentType type;
  const _ContentTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        type.label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10.5),
      ),
    );
  }
}
