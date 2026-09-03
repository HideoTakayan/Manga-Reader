import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/follow_service.dart';
import '../../data/content_type.dart';
import '../../data/models_cloud.dart';
import '../../data/models.dart';
import '../../data/drive_service.dart';
import '../../data/database_helper.dart';
import '../../services/history_service.dart';
import '../../services/interaction_service.dart';
import '../../services/library_service.dart';
import '../../services/library_status_service.dart';
import '../../services/download_service.dart';
import '../../services/folder_service.dart';
import '../../core/utils/chapter_sort_helper.dart';
import '../../core/utils/chapter_utils.dart';
import '../../core/utils/archive_image_extractor.dart';
import '../shared/library_dialogs.dart';
import '../shared/drive_image.dart';
import '../catalog/catalog_cache_service.dart';
import 'widgets/chapter_list_sliver.dart';
import 'widgets/manga_header_section.dart';
import 'widgets/manga_description_section.dart';
import 'widgets/bulk_download_sheet.dart';
import '../forum/widgets/quick_share_sheet.dart';
import '../shared/custom_tag_widgets.dart';
import '../../services/recommendation_service.dart';

enum ChapterFilterStatus {
  all,
  unread,
  downloaded,
  bookmarked,
}

class MangaDetailPage extends StatefulWidget {
  final String mangaId;
  const MangaDetailPage({super.key, required this.mangaId});

  @override
  State<MangaDetailPage> createState() => _MangaDetailPageState();
}

class _MangaDetailPageState extends State<MangaDetailPage> {
  ReadingHistory? _history;
  ReaderProgress? _readerProgress;
  List<ReaderBookmark> _bookmarks = [];
  LibraryStatusEntry? _libraryStatus;
  CloudManga? _manga;
  Future<List<CloudManga>>? _recommendationsFuture;
  List<CloudChapter> _chapters = [];
  bool _isLoading = true;
  bool _isSearchingChapters = false;
  String _chapterSearchQuery = '';
  final TextEditingController _chapterSearchController = TextEditingController();
  Timer? _chapterSearchDebounce;
  bool _isSortReversed = false;
  Set<String> _readChapterIds = {};
  Set<String> _downloadedChapterIds = {};
  ChapterFilterStatus _selectedChapterFilter = ChapterFilterStatus.all;

  // Cached Firestore streams — must not be created inside build()
  late Stream<bool> _followStream;
  late Stream<bool> _notificationStream;
  late Stream<Map<String, int>> _chapterViewsStream;
  late Stream<List<String>> _mangaCategoriesStream;

  // Helper chuyển đổi CloudManga -> Local Manga
  Manga _cloudToLocal(CloudManga cm) {
    return Manga(
      id: cm.id,
      title: cm.title,
      coverUrl: cm.coverFileId,
      author: cm.author,
      description: cm.description,
      genres: cm.genres,
      contentType: cm.contentType,
    );
  }

  @override
  void initState() {
    super.initState();
    LibraryStatusService.instance.addListener(_fetchLocalReaderData);
    _loadSortPref();
    _fetchData();
    _followStream = FollowService.instance.isFollowing(widget.mangaId);
    _notificationStream = FollowService.instance.isNotificationEnabled(widget.mangaId);
    _chapterViewsStream = InteractionService.instance.streamChapterViews(widget.mangaId);
    _mangaCategoriesStream = LibraryService.instance.streamMangaCategories(widget.mangaId);
  }

  @override
  void didUpdateWidget(covariant MangaDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mangaId != widget.mangaId) {
      _manga = null;
      _chapters = [];
      _recommendationsFuture = null;
      _history = null;
      _readerProgress = null;
      _bookmarks = [];
      _libraryStatus = null;
      _readChapterIds = {};
      _downloadedChapterIds = {};
      _selectedChapterFilter = ChapterFilterStatus.all;
      _loadSortPref();
      _fetchData();
      _followStream = FollowService.instance.isFollowing(widget.mangaId);
      _notificationStream = FollowService.instance.isNotificationEnabled(widget.mangaId);
      _chapterViewsStream = InteractionService.instance.streamChapterViews(widget.mangaId);
      _mangaCategoriesStream = LibraryService.instance.streamMangaCategories(widget.mangaId);
    }
  }

  Future<void> _loadSortPref() async {
    final prefs = await SharedPreferences.getInstance();
    final reversed =
        prefs.getBool('manga_sort_reversed_${widget.mangaId}') ?? false;
    if (mounted) {
      setState(() => _isSortReversed = reversed);
    }
  }

  @override
  void dispose() {
    LibraryStatusService.instance.removeListener(_fetchLocalReaderData);
    _chapterSearchDebounce?.cancel();
    _chapterSearchController.dispose();
    super.dispose();
  }

  /// Tải dữ liệu tổng hợp cho trang chi tiết (Chiến lược ưu tiên ngoại tuyến & tức thì)
  Future<void> _fetchData() async {
    if (_manga == null) {
      if (mounted) setState(() => _isLoading = true);
    }

    try {
      // --- 1. ƯU TIÊN NGOẠI TUYẾN: Thử Tải Dữ Liệu Cục Bộ ---
      CloudManga? localData;
      List<CloudChapter> localChaptersList = [];

      // A. Thử thông tin trong SQLite CSDL cục bộ
      Manga? dbManga = await DatabaseHelper.instance.getLocalManga(
        widget.mangaId,
      );

      // B. Nếu chưa có trong local_mangas, tìm trong Catalog Cache
      if (dbManga == null) {
        try {
          final cachedCatalog = await CatalogCacheService.instance.getCachedCatalog();
          final match = cachedCatalog.where((m) => m.id == widget.mangaId).firstOrNull;
          if (match != null) {
            dbManga = _cloudToLocal(match);
          }
        } catch (_) {}
      }

      // C. Nếu vẫn chưa có thông tin CSDL, khôi phục metadata từ các Chương đã Tải
      if (dbManga == null) {
        final downloads = await DatabaseHelper.instance.getDownloadsByManga(
          widget.mangaId,
        );
        if (downloads.isNotEmpty) {
          final first = downloads.first;
          final String title = first['mangaTitle'] ?? 'Manga Offline';

          String coverPath = '';
          try {
            if (await FolderService.hasCover(title)) {
              coverPath = await FolderService.getCoverPath(title);
            }
          } catch (_) {}

          dbManga = Manga(
            id: widget.mangaId,
            title: title,
            coverUrl: coverPath,
            author: 'Chế độ Ngoại tuyến',
            description:
                'Truyện đã tải về máy. Bạn có thể đọc ngoại tuyến bất cứ lúc nào mà không cần kết nối mạng.',
            genres: const [],
            contentType: MangaContentType.manga,
          );
        }
      }

      if (dbManga != null) {
        // Tối ưu ảnh bìa: Nếu có file cover cục bộ trên máy, ưu tiên dùng đường dẫn file
        String coverPath = dbManga.coverUrl;
        try {
          if (!coverPath.startsWith('/') && !coverPath.contains('\\')) {
            if (await FolderService.hasCover(dbManga.title)) {
              coverPath = await FolderService.getCoverPath(dbManga.title);
            }
          }
        } catch (_) {}

        // Tạo wrapper CloudManga cho Giao diện
        localData = CloudManga(
          id: dbManga.id,
          title: dbManga.title,
          coverFileId: coverPath,
          author: dbManga.author,
          status: 'Offline',
          description: dbManga.description,
          updatedAt: DateTime.now(),
          genres: dbManga.genres,
          chapterOrder: [],
          contentType: dbManga.contentType,
        );

        final downloadedMaps = await DatabaseHelper.instance
            .getDownloadsByManga(widget.mangaId);

        // Loại bỏ các chương tải xuống bị trùng lặp
        final Map<String, Map<String, dynamic>> uniqueDownloads = {};
        for (final d in downloadedMaps) {
          final chapterId = _readString(d, 'chapterId');
          if (chapterId.isEmpty) continue;
          if (!uniqueDownloads.containsKey(chapterId) ||
              _readInt(d, 'downloadDate') >
                  _readInt(uniqueDownloads[chapterId]!, 'downloadDate')) {
            uniqueDownloads[chapterId] = d;
          }
        }

        localChaptersList = uniqueDownloads.values.map((d) {
          final chapterId = _readString(d, 'chapterId');
          final chapterTitle = _readString(d, 'chapterTitle');
          final localPath = _readString(d, 'localPath');
          final ext = localPath.toLowerCase();
          final fileType = ext.endsWith('.pdf')
              ? 'pdf'
              : ext.endsWith('.epub')
                  ? 'epub'
                  : ext.endsWith('.cbt') || ext.endsWith('.tar')
                      ? 'cbt'
                      : ext.endsWith('.cbr')
                          ? 'cbr'
                          : ext.endsWith('.zip')
                              ? 'zip'
                              : 'cbz';
          
          return CloudChapter(
            id: chapterId,
            title: chapterTitle.isEmpty ? chapterId : chapterTitle,
            fileId: chapterId,
            fileType: fileType,
            uploadedAt: DateTime.fromMillisecondsSinceEpoch(
              _readInt(d, 'downloadDate'),
            ),
            viewCount: 0,
          );
        }).toList();

        // Sắp xếp số tăng dần
        localChaptersList = ChapterSortHelper.sort(localChaptersList);
      }

      await _fetchLocalReaderData();

      // Hiển thị dữ liệu cục bộ NGAY LẬP TỨC (Không để màn hình chờ quay tròn khi offline)
      if (localData != null && mounted) {
        final processedLocal = await ChapterUtils.mergeChapters(
          [],
          localChaptersList,
          widget.mangaId,
        );

        if (mounted) {
          setState(() {
            _manga = localData;
            _chapters = processedLocal;
            _isLoading = false; // HIỂN THỊ TỨC THÌ!
            _initRecommendations();
          });
          _preloadTargetChapter();
        }
      }

      // --- 2. ĐỒNG BỘ MẠNG TRỰC TUYẾN (Chạy ngầm, timeout nhanh 4s để không làm nghẽn máy) ---
      try {
        final mangasFuture = DriveService.instance.getMangas().timeout(const Duration(seconds: 4));
        final chaptersFuture = DriveService.instance.getChapters(widget.mangaId).timeout(const Duration(seconds: 4));

        final results = await Future.wait([mangasFuture, chaptersFuture]);
        final mangas = results[0] as List<CloudManga>;
        final chapters = results[1] as List<CloudChapter>;

        final finalManga = mangas.where((c) => c.id == widget.mangaId).firstOrNull ?? _manga;

        if (finalManga != null) {
          // Lưu thông tin mới vào CSDL cục bộ
          await DatabaseHelper.instance.saveLocalManga(_cloudToLocal(finalManga));

          final merged = await ChapterUtils.mergeChapters(
            chapters,
            localChaptersList,
            widget.mangaId,
          );

          if (mounted) {
            setState(() {
              _manga = finalManga;
              _chapters = merged;
              _isLoading = false;
              _initRecommendations();
            });
            _preloadTargetChapter();
          }
        }
      } catch (e) {
        debugPrint('⚠️ Network sync skipped (Offline Mode): $e');
        if (mounted && _manga != null) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error in detail _fetchData: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Tự động tải trước chương đầu hoặc chương đang đọc dở vào RAM/Temp để khi bấm Đọc sẽ mở trong 0.05s
  void _preloadTargetChapter() {
    if (_chapters.isEmpty) return;
    Future.microtask(() async {
      try {
        final targetChapterId = _readerProgress?.chapterId ??
            _history?.chapterId ??
            _getNextUnreadChapterId() ??
            _getFirstChapterId();
        if (targetChapterId == null) return;
        final targetChapter =
            _chapters.firstWhereOrNull((c) => c.id == targetChapterId);
        if (targetChapter == null) return;

        final isDownloaded =
            await DatabaseHelper.instance.isChapterDownloaded(targetChapterId);
        if (isDownloaded) return;

        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/temp_online_$targetChapterId');
        if (await tempFile.exists() && await tempFile.length() > 0) return;

        debugPrint('🚀 Smart preloading target chapter: ${targetChapter.title}');
        final success = await DriveService.instance.downloadFileToFile(
          targetChapterId,
          tempFile,
        );
        if (success &&
            targetChapter.fileType != 'pdf' &&
            targetChapter.fileType != 'epub') {
          await ArchiveImageExtractor.extract(tempFile.path, targetChapterId);
          debugPrint(
            '✅ Preloaded & extracted target chapter: ${targetChapter.title}',
          );
        }
      } catch (_) {}
    });
  }

  void _initRecommendations() {
    if (_recommendationsFuture == null && _manga != null) {
      _recommendationsFuture = CatalogCacheService.instance
          .getCachedCatalog()
          .then((catalog) async {
        final prefs = await RecommendationService.instance
            .calculateUserPreferences(catalog: catalog);
        return RecommendationService.instance.getRelatedMangas(
          currentManga: _manga!,
          catalog: catalog,
          userGenreScores: prefs.genreScores,
          limit: 10,
        );
      });
    }
  }

  Future<void> _fetchHistory() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    ReadingHistory? history;
    final localUserId = userId ?? 'guest';

    // Ưu tiên local để tiết kiệm Firebase read.
    history = await DatabaseHelper.instance.getHistoryForManga(
      localUserId,
      widget.mangaId,
    );

    if (history == null && _readerProgress != null) {
      history = ReadingHistory(
        userId: localUserId,
        mangaId: widget.mangaId,
        chapterId: _readerProgress!.chapterId,
        chapterTitle: _chapterTitleFor(_readerProgress!.chapterId),
        lastPageIndex: _readerProgress!.pageIndex,
        updatedAt: _readerProgress!.updatedAt,
      );
    }

    // Cloud chỉ là fallback khi máy chưa có dữ liệu local.
    if (history == null && userId != null) {
      history = await HistoryService.instance.getHistoryForManga(
        widget.mangaId,
      );
    }

    if (mounted) {
      setState(() {
        _history = history;
      });
    }
  }

  Future<void> _fetchBookmarks() async {
    final bookmarks = await DatabaseHelper.instance.getBookmarksForManga(
      widget.mangaId,
    );
    if (mounted) {
      setState(() => _bookmarks = bookmarks);
    }
  }

  Future<void> _fetchLocalReaderData() async {
    final progress = await DatabaseHelper.instance.getReaderProgress(
      widget.mangaId,
    );
    final bookmarks = await DatabaseHelper.instance.getBookmarksForManga(
      widget.mangaId,
    );
    final libraryStatus = await LibraryStatusService.instance.getEntry(
      widget.mangaId,
    );
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final readChapterIds = await DatabaseHelper.instance.getReadChapterIds(
      widget.mangaId,
      userId: userId,
    );
    final downloaded = await DatabaseHelper.instance.getDownloadsByManga(
      widget.mangaId,
    );
    final downloadedIds = downloaded
        .map((d) => d['chapterId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    if (!mounted) return;

    setState(() {
      _readerProgress = progress;
      _bookmarks = bookmarks;
      _libraryStatus = libraryStatus;
      _readChapterIds = readChapterIds;
      _downloadedChapterIds = downloadedIds;
    });
    await _fetchHistory();
  }

  String _chapterTitleFor(String chapterId) {
    for (final chapter in _chapters) {
      if (chapter.id == chapterId) return chapter.title;
    }
    return 'Chương $chapterId';
  }

  String? _getFirstChapterId() {
    if (_chapters.isEmpty) return null;
    return _chapters.first.id;
  }

  String? _getNextUnreadChapterId() {
    if (_chapters.isEmpty) return null;
    for (final c in _chapters) {
      if (!_readChapterIds.contains(c.id)) {
        return c.id;
      }
    }
    return _chapters.last.id;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final manga = _manga;
    if (manga == null || manga.id.isEmpty) {
      final theme = Theme.of(context);
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    size: 52,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Không tìm thấy bộ truyện này',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bộ truyện có thể đã bị xóa khỏi hệ thống hoặc kết nối mạng bị gián đoạn.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white60,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _fetchData(),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Thử lại'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.home_rounded, size: 18),
                      label: const Text('Về trang chủ', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
        ),
      );
    }

    final chapters = _chapters;
    final bookmarkedChapterIds = _bookmarks.map((b) => b.chapterId).toSet();

    // Thống kê số lượng chương theo từng bộ lọc
    final totalCount = chapters.length;
    final unreadCount = chapters.where((c) => !_readChapterIds.contains(c.id)).length;
    final downloadedCount = chapters.where((c) => _downloadedChapterIds.contains(c.id)).length;
    final bookmarkedCount = chapters.where((c) => bookmarkedChapterIds.contains(c.id)).length;

    final normalizedQuery =
        CatalogCacheService.instance.normalize(_chapterSearchQuery);
    final rawDisplay = chapters.where((c) {
      // 1. Lọc theo từ khóa tìm kiếm
      if (normalizedQuery.isNotEmpty) {
        final normTitle = CatalogCacheService.instance.normalize(c.title);
        final normId = CatalogCacheService.instance.normalize(c.id);
        if (!normTitle.contains(normalizedQuery) && !normId.contains(normalizedQuery)) {
          return false;
        }
      }

      // 2. Lọc theo bộ lọc trạng thái chương
      switch (_selectedChapterFilter) {
        case ChapterFilterStatus.all:
          return true;
        case ChapterFilterStatus.unread:
          return !_readChapterIds.contains(c.id);
        case ChapterFilterStatus.downloaded:
          return _downloadedChapterIds.contains(c.id);
        case ChapterFilterStatus.bookmarked:
          return bookmarkedChapterIds.contains(c.id);
      }
    }).toList();

    final displayChapters =
        _isSortReversed ? rawDisplay.reversed.toList() : rawDisplay;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      // Giao diện chính sử dụng CustomScrollView để tạo hiệu ứng Header Parallax
      body: RefreshIndicator(
        onRefresh: _fetchData,
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                // 1. Phần Đầu Trang (Ảnh bìa + Thông tin chính)
                SliverToBoxAdapter(
                  child: MangaHeaderSection(
                    manga: manga,
                    chaptersLength: chapters.length,
                  ),
                ),

                // 2. Danh sách Thể loại (Genres) cuộn ngang
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 40,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: manga.genres.isNotEmpty
                          ? manga.genres.length
                          : 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final genre = manga.genres.isNotEmpty
                            ? manga.genres[index]
                            : manga.contentType.label;
                        return InkWell(
                          onTap: () {
                            context.push(
                              Uri(
                                path: '/search-global',
                                queryParameters: {
                                  if (manga.genres.isNotEmpty) 'genre': genre,
                                  'type': manga.contentType.name,
                                },
                              ).toString(),
                            );
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              genre,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // 2b. Reading Progress Banner — chỉ hiện khi đã đọc ít nhất 1 chương
                if (_readChapterIds.isNotEmpty && chapters.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _ReadingProgressBanner(
                      readCount: _readChapterIds.length,
                      totalCount: chapters.length,
                    ),
                  ),

                // 3. Thanh tiêu đề danh sách chương
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Danh sách ${manga.contentType.unitLabel.toLowerCase()} (${chapters.length})',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.swap_vert_rounded,
                                    color: _isSortReversed
                                        ? Colors.orangeAccent
                                        : Colors.white70,
                                    size: 22,
                                  ),
                                  tooltip: _isSortReversed
                                      ? 'Đang xếp: Mới nhất trước (Bấm để đảo chiều)'
                                      : 'Đang xếp: Cũ nhất trước (Bấm để đảo chiều)',
                                  onPressed: () async {
                                    setState(() {
                                      _isSortReversed = !_isSortReversed;
                                    });
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setBool(
                                      'manga_sort_reversed_${widget.mangaId}',
                                      _isSortReversed,
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: Icon(
                                    _isSearchingChapters
                                        ? Icons.search_off
                                        : Icons.search,
                                    color: _isSearchingChapters
                                        ? Colors.orangeAccent
                                        : Colors.white70,
                                    size: 20,
                                  ),
                                  tooltip: 'Tìm số chương',
                                  onPressed: () {
                                    setState(() {
                                      _isSearchingChapters =
                                          !_isSearchingChapters;
                                      if (!_isSearchingChapters) {
                                        _chapterSearchController.clear();
                                        _chapterSearchQuery = '';
                                      }
                                    });
                                  },
                                ),
                                // Menu Hành động
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert),
                                  color: Theme.of(context).cardColor,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  onSelected: (value) async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    if (value == 'share_to_forum') {
                                      QuickShareToForumSheet.show(context, manga);
                                    } else if (value == 'mark_all_read') {
                                      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
                                      await DatabaseHelper.instance.markChaptersAsRead(
                                        mangaId: widget.mangaId,
                                        chapterIds: chapters.map((c) => c.id).toList(),
                                        userId: uid,
                                      );
                                      await _fetchData();
                                      if (mounted) {
                                        messenger.hideCurrentSnackBar();
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text('Đã đánh dấu tất cả là đã đọc'),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    } else if (value == 'mark_all_unread') {
                                      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
                                      await DatabaseHelper.instance.markAllChaptersAsUnread(
                                        mangaId: widget.mangaId,
                                        userId: uid,
                                      );
                                      await _fetchData();
                                      if (mounted) {
                                        messenger.hideCurrentSnackBar();
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text('Đã đánh dấu tất cả là chưa đọc'),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    } else if (value == 'bulk_download') {
                                      await BulkDownloadSheet.show(
                                        context,
                                        chapters: chapters,
                                        manga: manga,
                                        currentChapterId: _history?.chapterId ?? _readerProgress?.chapterId,
                                      );
                                      if (mounted) {
                                        _fetchData();
                                      }
                                    } else if (value == 'download_all') {
                                      _downloadManyChapters(chapters);
                                    } else if (value == 'download_latest_10') {
                                      _downloadManyChapters(
                                        _latestChapters(chapters),
                                      );
                                    } else if (value == 'delete_all') {
                                      _deleteAllDownloads(chapters);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'share_to_forum',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.forum_outlined,
                                            color: Colors.purpleAccent,
                                          ),
                                          SizedBox(width: 12),
                                          Text('Chia sẻ lên Diễn đàn'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'mark_all_read',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.done_all_rounded,
                                            color: Colors.greenAccent,
                                          ),
                                          SizedBox(width: 12),
                                          Text('Đánh dấu tất cả đã đọc'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'mark_all_unread',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.remove_done_rounded,
                                            color: Colors.amberAccent,
                                          ),
                                          SizedBox(width: 12),
                                          Text('Đánh dấu tất cả chưa đọc'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'bulk_download',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.checklist_rounded,
                                            color: Colors.cyanAccent,
                                          ),
                                          SizedBox(width: 12),
                                          Text('Tùy chọn tải nhiều chương...'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'download_all',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.download_rounded,
                                            color: Colors.blue,
                                          ),
                                          SizedBox(width: 12),
                                          Text('Tải tất cả'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'download_latest_10',
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.download_for_offline_outlined,
                                            color: Colors.orange,
                                          ),
                                          SizedBox(width: 12),
                                          Text(
                                            'Tải 10 ${manga.contentType.unitLabel.toLowerCase()} mới nhất',
                                          ),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete_all',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.delete_outline,
                                            color: Colors.red,
                                          ),
                                          SizedBox(width: 12),
                                          Text('Xóa tất cả tải xuống'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (_isSearchingChapters)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: TextField(
                              controller: _chapterSearchController,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Tìm nhanh số chương (ví dụ: 12, Chapter 50)...',
                                hintStyle: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: Colors.orangeAccent,
                                  size: 18,
                                ),
                                suffixIcon: _chapterSearchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.clear,
                                          color: Colors.white54,
                                          size: 16,
                                        ),
                                        onPressed: () {
                                          _chapterSearchController.clear();
                                          setState(
                                            () => _chapterSearchQuery = '',
                                          );
                                        },
                                      )
                                    : null,
                                fillColor: Colors.white.withValues(alpha: 0.08),
                                filled: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (val) {
                                if (_chapterSearchDebounce?.isActive ?? false) {
                                  _chapterSearchDebounce!.cancel();
                                }
                                _chapterSearchDebounce = Timer(
                                  const Duration(milliseconds: 150),
                                  () {
                                    if (mounted) {
                                      setState(() => _chapterSearchQuery = val);
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              _buildChapterFilterChip(
                                label: 'Tất cả',
                                count: totalCount,
                                icon: Icons.all_inclusive_rounded,
                                status: ChapterFilterStatus.all,
                                isSelected: _selectedChapterFilter == ChapterFilterStatus.all,
                                activeColor: Colors.blueAccent,
                              ),
                              const SizedBox(width: 8),
                              _buildChapterFilterChip(
                                label: 'Chưa đọc',
                                count: unreadCount,
                                icon: Icons.mark_chat_unread_outlined,
                                status: ChapterFilterStatus.unread,
                                isSelected: _selectedChapterFilter == ChapterFilterStatus.unread,
                                activeColor: Colors.orangeAccent,
                              ),
                              const SizedBox(width: 8),
                              _buildChapterFilterChip(
                                label: 'Đã tải',
                                count: downloadedCount,
                                icon: Icons.download_done_rounded,
                                status: ChapterFilterStatus.downloaded,
                                isSelected: _selectedChapterFilter == ChapterFilterStatus.downloaded,
                                activeColor: Colors.greenAccent,
                              ),
                              const SizedBox(width: 8),
                              _buildChapterFilterChip(
                                label: 'Bookmark',
                                count: bookmarkedCount,
                                icon: Icons.bookmark_rounded,
                                status: ChapterFilterStatus.bookmarked,
                                isSelected: _selectedChapterFilter == ChapterFilterStatus.bookmarked,
                                activeColor: Colors.amberAccent,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 4. Phần giới thiệu nội dung truyện
                SliverToBoxAdapter(
                  child: MangaDescriptionSection(
                    description: manga.description,
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 20)),

                // 5. Danh sách các chương (Hiển thị dạng List)
                StreamBuilder<Map<String, int>>(
                  stream: _chapterViewsStream,
                  builder: (context, snapshot) {
                    return ChapterListSliver(
                      displayChapters: displayChapters,
                      allChapters: chapters,
                      mangaId: widget.mangaId,
                      manga: manga,
                      localMangaInfo: _manga != null
                          ? _cloudToLocal(_manga!)
                          : null,
                      chapterViews: snapshot.data ?? const {},
                      theme: theme,
                      onChapterRead: _fetchData,
                      readChapterIds: _readChapterIds,
                      currentProgress: _readerProgress,
                    );
                  },
                ),

                _buildRecommendations(manga),

                // Khoảng trống dưới cùng để không bị che bởi Bottom Dock
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),

            // Nút Back và Nút Like nổi trên Header
            Positioned(
              top: 40,
              left: 10,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => context.pop(),
              ),
            ),
            Positioned(
              top: 40,
              right: 10,
              child: Row(
                children: [
                  // Nút Chia Sẻ Lên Diễn Đàn
                  IconButton(
                    icon: const Icon(Icons.share_rounded, color: Colors.white),
                    tooltip: 'Chia sẻ lên Diễn đàn',
                    onPressed: () => QuickShareToForumSheet.show(context, manga),
                  ),
                  // Nút Tải Chương Hàng Loạt (Bulk Download)
                  IconButton(
                    icon: const Icon(Icons.download, color: Colors.white),
                    tooltip: 'Tải chương hàng loạt',
                    onPressed: () async {
                      await BulkDownloadSheet.show(
                        context,
                        chapters: chapters,
                        manga: manga,
                        currentChapterId: _history?.chapterId ?? _readerProgress?.chapterId,
                      );
                      if (mounted) {
                        _fetchData();
                      }
                    },
                  ),
                  // Nút Đặt vào Thư viện (Folder)
                  StreamBuilder<List<String>>(
                    stream: _mangaCategoriesStream,
                    builder: (context, snapshot) {
                      final selectedCats = snapshot.data ?? [];
                      final isInLibrary = selectedCats.isNotEmpty;
                      return IconButton(
                        icon: Icon(
                          isInLibrary
                              ? Icons.folder_special
                              : Icons.create_new_folder_outlined,
                          color: isInLibrary
                              ? Colors.orangeAccent
                              : Colors.white,
                        ),
                        onPressed: () =>
                            _showSetCategoryDialog(context, selectedCats),
                      );
                    },
                  ),
                  // Nút Theo Dõi (Tim)
                  StreamBuilder<bool>(
                    stream: _followStream,
                    builder: (context, snapshot) {
                      final isFollowed = snapshot.data ?? false;
                      return IconButton(
                        icon: Icon(
                          isFollowed ? Icons.favorite : Icons.favorite_border,
                          color: isFollowed ? Colors.red : Colors.white,
                        ),
                        onPressed: () async {
                          HapticFeedback.lightImpact();
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Vui lòng đăng nhập để sử dụng tính năng theo dõi',
                                  ),
                                ),
                              );
                            }
                            return;
                          }

                          if (isFollowed) {
                            // Hỏi xác nhận hủy theo dõi
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? theme.cardColor,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                title: const Text(
                                  'Hủy Theo Dõi?',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                                content: const Text(
                                  'Bạn có chắc chắn muốn hủy theo dõi truyện này?',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, false),
                                    child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () =>
                                        Navigator.pop(ctx, true),
                                    child: const Text('Đồng ý'),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              try {
                                await FollowService.instance.unfollowManga(widget.mangaId);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã hủy theo dõi'),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Lỗi hủy theo dõi: $e')),
                                  );
                                }
                              }
                            }
                          } else {
                            // Theo dõi
                            try {
                              final cover = (manga.coverFileId.startsWith('/') ||
                                      manga.coverFileId.contains('\\'))
                                  ? manga.coverFileId
                                  : DriveService.instance.getThumbnailLink(
                                      manga.coverFileId,
                                    );
                              await FollowService.instance.followManga(
                                mangaId: manga.id,
                                title: manga.title,
                                coverUrl: cover,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Đã theo dõi thành công!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Lỗi theo dõi truyện: $e')),
                                );
                              }
                            }
                          }
                        },
                      );
                    },
                  ),
                  // Nút Chuông Thông Báo Chương Mới (Hiển thị khi đã theo dõi)
                  StreamBuilder<bool>(
                    stream: _followStream,
                    builder: (context, followSnap) {
                      final isFollowed = followSnap.data ?? false;
                      if (!isFollowed) return const SizedBox.shrink();

                      return StreamBuilder<bool>(
                        stream: _notificationStream,
                        builder: (context, notifSnap) {
                          final isNotifEnabled = notifSnap.data ?? true;
                          return IconButton(
                            icon: Icon(
                              isNotifEnabled
                                  ? Icons.notifications_active
                                  : Icons.notifications_off_outlined,
                              color: isNotifEnabled
                                  ? Colors.amber
                                  : Colors.white54,
                            ),
                            tooltip: isNotifEnabled
                                ? 'Đang nhận thông báo chương mới (Bấm để tắt)'
                                : 'Đã tắt thông báo (Bấm để nhận thông báo)',
                            onPressed: () async {
                              HapticFeedback.selectionClick();
                              try {
                                final newState = await FollowService.instance.toggleNotification(widget.mangaId);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        newState
                                            ? '🔔 Đã bật thông báo khi có chương mới!'
                                            : '🔕 Đã tắt thông báo cho bộ truyện này.',
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Lỗi cập nhật thông báo: $e')),
                                  );
                                }
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),

            // Thanh công cụ dưới cùng (Bottom Dock) - Trạng thái đọc & Nút hành động
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      theme.scaffoldBackgroundColor, // Mờ dần theo nền
                      theme.scaffoldBackgroundColor.withValues(alpha: 0.0),
                    ],
                    stops: const [0.6, 1.0],
                  ),
                ),
                child: Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Đọc Đến', style: theme.textTheme.bodySmall),
                            Text(
                              _readerProgress != null
                                  ? '${_chapterTitleFor(_readerProgress!.chapterId)} • ${_formatDate(_readerProgress!.updatedAt)}'
                                  : _history != null
                                  ? '${_history!.chapterTitle ?? "Chương ${_history!.chapterId}"} • ${_formatDate(_history!.updatedAt)}'
                                  : (_libraryStatus?.status == MangaReadingStatus.completed
                                      ? 'Đã đọc xong toàn bộ'
                                      : (chapters.isNotEmpty
                                            ? 'Chưa đọc'
                                            : 'Chưa có chương')),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if ((_readerProgress != null || _history != null) && chapters.isNotEmpty) ...[
                        OutlinedButton(
                          onPressed: () async {
                            final firstId = _getFirstChapterId();
                            if (firstId != null) {
                              await context.push(
                                '/reader/$firstId?mangaId=${Uri.encodeComponent(widget.mangaId)}',
                              );
                              if (mounted) {
                                await _fetchData();
                              }
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: const Text('Đọc từ đầu', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ElevatedButton(
                        onPressed: () async {
                          String? chapterIdToOpen;
                          int? targetPage;
                          if (_readerProgress != null &&
                              _readerProgress!.chapterId.isNotEmpty) {
                            chapterIdToOpen = _readerProgress!.chapterId;
                            targetPage = _readerProgress!.pageIndex;
                          } else if (_history != null) {
                            chapterIdToOpen = _history!.chapterId;
                            targetPage = _history!.lastPageIndex;
                          } else {
                            // Nếu chưa có lịch sử đọc cụ thể, ưu tiên mở chương chưa đọc đầu tiên
                            chapterIdToOpen = _getNextUnreadChapterId() ?? _getFirstChapterId();
                            targetPage = 0;
                          }

                          if (chapterIdToOpen != null) {
                            final pageQuery = targetPage > 0
                                ? '&page=$targetPage'
                                : '';
                            await context.push(
                              '/reader/$chapterIdToOpen?mangaId=${Uri.encodeComponent(widget.mangaId)}$pageQuery',
                            );
                            if (mounted) {
                              await _fetchData();
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9800),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                        ),
                        child: Text(
                          _readerProgress != null || _history != null
                              ? 'Đọc Tiếp'
                              : 'Bắt Đầu Đọc',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            tooltip: 'Bookmark',
                            icon: Icon(
                              _bookmarks.isEmpty
                                  ? Icons.bookmark_border
                                  : Icons.bookmarks,
                              color: _bookmarks.isEmpty
                                  ? theme.iconTheme.color?.withValues(
                                      alpha: 0.6,
                                    )
                                  : Colors.amber,
                            ),
                            onPressed: () => _showBookmarkList(theme),
                          ),
                          if (_bookmarks.isNotEmpty)
                            Positioned(
                              top: 3,
                              right: 3,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _bookmarks.length.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      IconButton(
                        tooltip: 'Trạng thái đọc',
                        icon: Icon(
                          _statusIcon(_libraryStatus?.status),
                          color: Colors.lightBlueAccent,
                        ),
                        onPressed: () => _showReadingStatusDialog(theme),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays > 0) return '${diff.inDays} ngày trước';
    if (diff.inHours > 0) return '${diff.inHours} giờ trước';
    return 'Mới đây';
  }

  Widget _buildChapterFilterChip({
    required String label,
    required int count,
    required IconData icon,
    required ChapterFilterStatus status,
    required bool isSelected,
    required Color activeColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _selectedChapterFilter = status;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : Colors.white.withValues(alpha: 0.12),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? activeColor : Colors.white60,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? activeColor : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeColor.withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBookmarkList(ThemeData theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (_bookmarks.isEmpty) {
              return SizedBox(
                height: 200,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                        child: const Icon(
                          Icons.bookmark_outline_rounded,
                          size: 40,
                          color: Colors.white38,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Chưa có bookmark nào',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Nhấn bookmark trong lúc đọc để lưu trang yêu thích',
                        style: TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              );
            }

            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Danh sách Bookmark (${_bookmarks.length})',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _bookmarks.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                      itemBuilder: (context, index) {
                        final bookmark = _bookmarks[index];
                        final hasNote = bookmark.note != null && bookmark.note!.trim().isNotEmpty;
                        return ListTile(
                          leading: const Icon(Icons.bookmark, color: Colors.amber),
                          title: Text(
                            _chapterTitleFor(bookmark.chapterId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Trang ${bookmark.pageIndex + 1} • ${_formatDate(bookmark.updatedAt)}',
                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                              if (hasNote) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.sticky_note_2_outlined, color: Colors.amberAccent, size: 13),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          bookmark.note!,
                                          style: const TextStyle(
                                            color: Colors.amberAccent,
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: hasNote ? 'Sửa ghi chú' : 'Thêm ghi chú',
                                icon: Icon(
                                  hasNote ? Icons.edit_note : Icons.add_comment_outlined,
                                  color: hasNote ? Colors.amberAccent : Colors.white60,
                                  size: 22,
                                ),
                                onPressed: () => _editBookmarkNote(bookmark, setModalState),
                              ),
                              IconButton(
                                tooltip: 'Xóa bookmark',
                                icon: const Icon(Icons.delete_outline, color: Colors.white60, size: 20),
                                onPressed: () async {
                                  HapticFeedback.lightImpact();
                                  await DatabaseHelper.instance.deleteBookmark(bookmark.id);
                                  await _fetchBookmarks();
                                  setModalState(() {});
                                  if (mounted) setState(() {});
                                },
                              ),
                            ],
                          ),
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            Navigator.pop(context);
                            await context.push(
                              '/reader/${bookmark.chapterId}?mangaId=${Uri.encodeComponent(widget.mangaId)}&page=${bookmark.pageIndex}',
                            );
                            await _fetchLocalReaderData();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _editBookmarkNote(
    ReaderBookmark bookmark,
    StateSetter setModalState,
  ) async {
    HapticFeedback.lightImpact();
    final textController = TextEditingController(text: bookmark.note ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Theme.of(dialogCtx).dialogTheme.backgroundColor ?? Theme.of(dialogCtx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: Colors.amber, size: 24),
            const SizedBox(width: 8),
            Text(
              'Ghi chú (Trang ${bookmark.pageIndex + 1})',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _chapterTitleFor(bookmark.chapterId),
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Nhập ghi chú cho trang đánh dấu này...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          if (bookmark.note != null && bookmark.note!.isNotEmpty)
            TextButton(
              onPressed: () {
                textController.clear();
                Navigator.pop(dialogCtx, true);
              },
              child: const Text('Xóa ghi chú', style: TextStyle(color: Colors.redAccent)),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Lưu', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    final newNote = textController.text.trim();
    textController.dispose();

    if (result == true) {
      await DatabaseHelper.instance.updateBookmarkNote(
        bookmark.id,
        newNote.isEmpty ? null : newNote,
      );
      await _fetchBookmarks();
      setModalState(() {});
      if (mounted) setState(() {});
    }
  }

  Future<void> _showReadingStatusDialog(ThemeData theme) async {
    final selected = await showModalBottomSheet<MangaReadingStatus>(
      context: context,
      backgroundColor: theme.cardColor,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...MangaReadingStatus.values.map((status) {
                final isSelected = _libraryStatus?.status == status;
                final (label, icon, color) = LibraryStatusService.getStatusDisplay(status);
                return ListTile(
                  leading: Icon(
                    icon,
                    color: isSelected ? color : Colors.white70,
                  ),
                  title: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? color : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected ? Icon(Icons.check, color: color) : null,
                  onTap: () => Navigator.pop(context, status),
                );
              }),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.sell_outlined, color: Colors.purpleAccent),
                title: const Text('Nhãn tùy chỉnh (Tags)'),
                subtitle: Text(
                  (_libraryStatus?.tags.isNotEmpty ?? false)
                      ? _libraryStatus!.tags.join(', ')
                      : 'Chưa có nhãn',
                ),
                onTap: () {
                  Navigator.pop(context);
                  Future.microtask(_showTagsDialog);
                },
              ),
            ],
          ),
        );
      },
    );
    if (selected == null) return;

    await LibraryStatusService.instance.setStatus(widget.mangaId, selected);
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã đặt trạng thái: ${_statusLabel(selected)}')),
    );

    // Nếu chọn Đã hoàn thành và có các chương chưa đọc, hỏi người dùng có muốn đánh dấu tất cả chương là đã đọc không
    if (selected == MangaReadingStatus.completed && _chapters.isNotEmpty) {
      final unreadChapters =
          _chapters.where((c) => !_readChapterIds.contains(c.id)).toList();
      if (unreadChapters.isNotEmpty && mounted) {
        final markAll = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor:
                Theme.of(ctx).dialogTheme.backgroundColor ??
                Theme.of(ctx).cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.done_all_rounded, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text(
                  'Đánh dấu toàn bộ chương?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: Text(
              'Bạn đã chọn "Đã xong". Bạn có muốn đánh dấu toàn bộ ${unreadChapters.length} chương chưa đọc là đã đọc không?',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Không cần', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Đánh dấu tất cả',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );

        if (markAll == true && mounted) {
          final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
          await DatabaseHelper.instance.markChaptersAsRead(
            mangaId: widget.mangaId,
            chapterIds: _chapters.map((c) => c.id).toList(),
            userId: uid,
          );
          await _fetchData();
        }
      }
    }
  }

  Future<void> _showTagsDialog() async {
    final updatedTags = await CustomTagManagerDialog.show(
      context,
      mangaId: widget.mangaId,
      currentTags: _libraryStatus?.tags ?? [],
    );

    if (updatedTags != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã cập nhật nhãn đọc')));
    }
  }

  IconData _statusIcon(MangaReadingStatus? status) {
    if (status == null) return Icons.menu_book_rounded;
    return LibraryStatusService.getStatusDisplay(status).$2;
  }

  String _statusLabel(MangaReadingStatus status) {
    return LibraryStatusService.getStatusDisplay(status).$1;
  }

  void _showSetCategoryDialog(
    BuildContext context,
    List<String> currentSelected,
  ) {
    LibraryDialogs.showSetCategoryDialog(context, [
      widget.mangaId,
    ], currentSelected);
  }

  Future<void> _downloadManyChapters(List<CloudChapter> chapters) async {
    if (chapters.isEmpty) return;
    if (_manga == null) return;

    final isDownloadedList = await Future.wait(
      chapters.map((c) => DownloadService.instance.isDownloaded(c.id, mangaId: widget.mangaId)),
    );

    // Lưu metadata truyện 1 lần duy nhất trước vòng lặp để tránh ghi SQLite N lần
    final localManga = _cloudToLocal(_manga!);
    await DatabaseHelper.instance.saveLocalManga(localManga);
    int addedCount = 0;

    for (int i = 0; i < chapters.length; i++) {
      if (isDownloadedList[i]) continue;
      final chapter = chapters[i];
      final status = DownloadService.instance.getDownloadStatus(chapter.id);
      if (status != DownloadStatus.idle && status != DownloadStatus.failed) {
        continue;
      }

      await DownloadService.instance.addToQueue(
        chapterId: chapter.id,
        mangaId: widget.mangaId,
        mangaTitle: _manga!.title,
        chapterTitle: chapter.title,
        fileType: chapter.fileType,
      );
      addedCount++;
    }

    if (mounted && addedCount > 0) {
      final router = GoRouter.of(context);
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Đã thêm $addedCount chương vào hàng đợi tải'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Xem',
            textColor: Colors.white,
            onPressed: () {
              messenger.hideCurrentSnackBar();
              router.push('/downloads');
            },
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tất cả chương đã được tải hoặc đang tải'),
        ),
      );
    }
  }

  List<CloudChapter> _latestChapters(List<CloudChapter> chapters) {
    if (chapters.isEmpty) return [];
    if (chapters.length <= 10) return List.from(chapters);
    return chapters.sublist(chapters.length - 10);
  }

  Future<void> _deleteAllDownloads(List<CloudChapter> chapters) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Xóa tải xuống?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Bạn có chắc muốn xóa tất cả tải xuống của truyện này?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
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
      ),
    );

    if (confirm != true) return;

    final isDownloadedList = await Future.wait(
      chapters.map((c) => DownloadService.instance.isDownloaded(c.id, mangaId: widget.mangaId)),
    );

    final chaptersToDelete = [
      for (int i = 0; i < chapters.length; i++)
        if (isDownloadedList[i]) chapters[i],
    ];

    if (chaptersToDelete.isNotEmpty) {
      await Future.wait(
        chaptersToDelete.map((c) => DownloadService.instance.deleteDownload(c.id)),
      );
      await FolderService.deleteMangaFolder(
        widget.mangaId,
        mangaTitle: _manga?.title,
      );
      await _fetchData();
    }

    if (mounted) {
      if (chaptersToDelete.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã xóa ${chaptersToDelete.length} chương tải xuống')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không có chương nào đã tải để xóa')),
        );
      }
    }
  }

  String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return '';
    return value.toString().trim();
  }

  int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Widget _buildRecommendations(CloudManga currentManga) {
    if (_recommendationsFuture == null) {
      return const SliverToBoxAdapter(child: SizedBox());
    }

    return SliverToBoxAdapter(
      child: FutureBuilder<List<CloudManga>>(
        future: _recommendationsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const SizedBox();
          }
          final recommendedMangas = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: Text(
                  'Có thể bạn sẽ thích',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(
                height: 180,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: recommendedMangas.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final rm = recommendedMangas[index];
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        context.push('/detail/${rm.id}');
                      },
                      child: SizedBox(
                        width: 110,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: DriveImage(
                                        fileId: rm.coverFileId,
                                        fit: BoxFit.cover,
                                        width: 110,
                                      ),
                                    ),
                                  ),
                                  if (rm.contentType == MangaContentType.novel)
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.75),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5), width: 0.8),
                                        ),
                                        child: const Text(
                                          'Chữ',
                                          style: TextStyle(
                                            color: Colors.orangeAccent,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              rm.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Banner tiến độ đọc — hiển thị X/Y chương đã đọc + progress bar.
/// Chỉ render khi readCount > 0, nên không cần kiểm tra bên trong.
class _ReadingProgressBanner extends StatelessWidget {
  final int readCount;
  final int totalCount;

  const _ReadingProgressBanner({
    required this.readCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (totalCount > 0 ? readCount / totalCount : 0.0).clamp(0.0, 1.0);
    final percent = (progress * 100).round();
    final isCompleted = readCount >= totalCount;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCompleted
              ? Colors.greenAccent.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isCompleted
                        ? Icons.check_circle_rounded
                        : Icons.auto_stories_rounded,
                    color: isCompleted ? Colors.greenAccent : Colors.blueAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isCompleted ? 'Đã đọc xong' : 'Tiến độ đọc',
                    style: TextStyle(
                      color: isCompleted ? Colors.greenAccent : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                '$readCount/$totalCount chương • $percent%',
                style: TextStyle(
                  color: isCompleted ? Colors.greenAccent : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                isCompleted ? Colors.greenAccent : Colors.blueAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
