import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/follow_service.dart';
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
import '../shared/library_dialogs.dart';
import 'widgets/chapter_list_sliver.dart';
import 'widgets/manga_header_section.dart';
import 'widgets/manga_description_section.dart';

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
  List<CloudChapter> _chapters = [];
  bool _isLoading = true;

  // Helper chuyển đổi CloudManga -> Local Manga
  Manga _cloudToLocal(CloudManga cm) {
    return Manga(
      id: cm.id,
      title: cm.title,
      coverUrl: cm.coverFileId,
      author: cm.author,
      description: cm.description,
      genres: cm.genres,
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Tải dữ liệu tổng hợp cho trang chi tiết (Chiến lược ưu tiên ngoại tuyến)
  Future<void> _fetchData() async {
    if (_manga == null) {
      if (mounted) setState(() => _isLoading = true);
    }

    try {
      // --- 1. ƯU TIÊN NGOẠI TUYẾN: Thử Tải Dữ Liệu Cục Bộ ---
      CloudManga? localData;
      List<CloudChapter> localChaptersList = [];

      // A. Thử thông tin trong CSDL
      Manga? dbManga = await DatabaseHelper.instance.getLocalManga(
        widget.mangaId,
      );

      // B. Nếu không có thông tin CSDL, khôi phục metadata từ các Chương đã Tải (Tương thích ngược)
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
            author: 'Vô danh (Offline)',
            description:
                'Không có thông tin chi tiết (Tải từ phiên bản cũ hoặc chưa đồng bộ). Bạn vẫn có thể đọc bình thường.',
            genres: [],
          );
        }
      }

      if (dbManga != null) {
        // Tạo wrapper CloudManga cho Giao diện
        localData = CloudManga(
          id: dbManga.id,
          title: dbManga.title,
          coverFileId: dbManga.coverUrl,
          author: dbManga.author,
          status: 'Offline',
          description: dbManga.description,
          updatedAt: DateTime.now(),
          genres: dbManga.genres,
          chapterOrder: [],
        );

        final downloadedMaps = await DatabaseHelper.instance
            .getDownloadsByManga(widget.mangaId);

        // 🔧 SỬA LỖI: Loại bỏ các chương tải xuống bị trùng lặp (phòng trường hợp DB có duplicate)
        final Map<String, Map<String, dynamic>> uniqueDownloads = {};
        for (final d in downloadedMaps) {
          final chapterId = _readString(d, 'chapterId');
          if (chapterId.isEmpty) continue;
          // Giữ entry mới nhất (downloadDate cao nhất)
          if (!uniqueDownloads.containsKey(chapterId) ||
              _readInt(d, 'downloadDate') >
                  _readInt(uniqueDownloads[chapterId]!, 'downloadDate')) {
            uniqueDownloads[chapterId] = d;
          }
        }

        localChaptersList = uniqueDownloads.values.map((d) {
          final chapterId = _readString(d, 'chapterId');
          final chapterTitle = _readString(d, 'chapterTitle');
          return CloudChapter(
            id: chapterId,
            title: chapterTitle.isEmpty ? chapterId : chapterTitle,
            fileId: chapterId,
            fileType: 'cbz',
            uploadedAt: DateTime.fromMillisecondsSinceEpoch(
              _readInt(d, 'downloadDate'),
            ),
            viewCount: 0,
          );
        }).toList();

        // Sắp xếp số tăng dần (Khớp với Chế độ Trực tuyến)
        localChaptersList = ChapterSortHelper.sort(localChaptersList);
      }

      await _fetchLocalReaderData();

      // Hiển thị dữ liệu cục bộ ngay lập tức nếu có
      if (localData != null && mounted) {
        // FIX: Xử lý deduplicate và sort ngay cho data offline để tránh hiển thị trùng/lộn xộn
        final processedLocal = await ChapterUtils.mergeChapters(
          [],
          localChaptersList,
          widget.mangaId,
        );

        if (mounted) {
          setState(() {
            _manga = localData;
            _chapters = processedLocal;
            // Giữ trạng thái đang tải là true để xác minh mạng
          });
        }
      }

      // --- 2. ĐỒNG BỘ MẠNG (Thử lấy dữ liệu mới) ---
      final mangas = await DriveService.instance.getMangas(forceRefresh: true);
      final manga = mangas.firstWhere(
        (c) => c.id == widget.mangaId,
        orElse: () => throw Exception('Không tìm thấy truyện trên máy chủ'),
      );

      final chapters = await DriveService.instance.getChapters(widget.mangaId);

      // Lưu thông tin mới vào CSDL cục bộ
      await DatabaseHelper.instance.saveLocalManga(_cloudToLocal(manga));
      await _fetchHistory();
      await _fetchBookmarks();

      // 🔧 SỬA LỖI: Loại bỏ trùng lặp Nâng cao & Sắp xếp (Tập trung)
      // Gọi helper để xử lý logic gộp và sắp xếp nhất quán
      final deduplicatedChapters = await ChapterUtils.mergeChapters(
        chapters,
        localChaptersList,
        widget.mangaId,
      );

      if (mounted) {
        setState(() {
          _manga = manga;
          _chapters = deduplicatedChapters;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Network fetch failed (Offline Mode): $e');

      // Nếu chúng ta có dữ liệu cục bộ, coi đó là trạng thái thành công (Chế độ Ngoại tuyến)
      if (_manga != null) {
        if (mounted) {
          setState(() => _isLoading = false);
          if (e.toString().contains('SocketException') ||
              e.toString().contains('ClientException')) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Đang xem chế độ Offline'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } else {
        // Lỗi thực sự (Không có dữ liệu cục bộ, không có mạng)
        if (mounted) setState(() => _isLoading = false);
      }
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
    if (!mounted) return;

    setState(() {
      _readerProgress = progress;
      _bookmarks = bookmarks;
      _libraryStatus = libraryStatus;
    });
    await _fetchHistory();
  }

  String _chapterTitleFor(String chapterId) {
    for (final chapter in _chapters) {
      if (chapter.id == chapterId) return chapter.title;
    }
    return 'Chương $chapterId';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final manga = _manga;
    if (manga == null || manga.id.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lỗi')),
        body: const Center(child: Text('Không tìm thấy truyện')),
      );
    }

    final chapters = _chapters;
    final displayChapters = chapters; // Hiện tất cả các chương
    final followService = FollowService();
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
                            : "Manhwa"; // Mặc định nếu trống
                        return InkWell(
                          onTap: () {
                            context.push(
                              Uri(
                                path: '/search-global',
                                queryParameters: {'genre': genre},
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
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              genre,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // 3. Thanh tiêu đề danh sách chương
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'DS Chương (${chapters.length})',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        // Menu Hành động
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) async {
                            if (value == 'download_all') {
                              _downloadManyChapters(chapters);
                            } else if (value == 'download_latest_10') {
                              _downloadManyChapters(_latestChapters(chapters));
                            } else if (value == 'delete_all') {
                              _deleteAllDownloads(chapters);
                            }
                          },
                          itemBuilder: (context) => [
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
                            const PopupMenuItem(
                              value: 'download_latest_10',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.download_for_offline_outlined,
                                    color: Colors.orange,
                                  ),
                                  SizedBox(width: 12),
                                  Text('Tải 10 chương mới nhất'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete_all',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, color: Colors.red),
                                  SizedBox(width: 12),
                                  Text('Xóa tất cả tải xuống'),
                                ],
                              ),
                            ),
                          ],
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
                  stream: InteractionService.instance.streamChapterViews(
                    widget.mangaId,
                  ),
                  builder: (context, snapshot) {
                    return ChapterListSliver(
                      displayChapters: displayChapters,
                      mangaId: widget.mangaId,
                      manga: manga,
                      localMangaInfo: _manga != null
                          ? _cloudToLocal(_manga!)
                          : null,
                      chapterViews: snapshot.data ?? const {},
                      theme: theme,
                      onChapterRead: _fetchData,
                    );
                  },
                ),

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
                  // Nút Tải tất cả các Chương
                  IconButton(
                    icon: const Icon(Icons.download, color: Colors.white),
                    onPressed: () async {
                      // Bước 1: Xác nhận có tải không
                      final confirmDownload = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: theme.cardColor,
                          title: Text(
                            'Tải tất cả chương?',
                            style: theme.textTheme.titleLarge,
                          ),
                          content: Text(
                            'Tải ${chapters.length} chương của "${manga.title}" về máy?\n\n'
                            'Lưu ý: Quá trình này có thể tốn khoảng ${(chapters.length * 5)} MB dung lượng trống.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Hủy'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text(
                                'Tải xuống',
                                style: TextStyle(color: Colors.orange),
                              ),
                            ),
                          ],
                        ),
                      );

                      if (confirmDownload != true) return;

                      if (context.mounted) {
                        final addToLibrary = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: theme.cardColor,
                            title: Text(
                              'Thêm vào Thư viện?',
                              style: theme.textTheme.titleLarge,
                            ),
                            content: Text(
                              'Bạn có muốn thêm truyện vào thư viện để dễ quản lý không?',
                              style: theme.textTheme.bodyMedium,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Không'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Có'),
                              ),
                            ],
                          ),
                        );

                        if (addToLibrary == true && context.mounted) {
                          final selectedCats = await LibraryService.instance
                              .streamMangaCategories(widget.mangaId)
                              .first;
                          if (context.mounted) {
                            _showSetCategoryDialog(context, selectedCats);
                          }
                        }
                      }

                      // Bắt đầu tải tất cả các chương
                      for (final chapter in chapters) {
                        await DownloadService.instance.addToQueue(
                          chapterId: chapter.id,
                          mangaId: widget.mangaId,
                          mangaTitle: manga.title,
                          chapterTitle: chapter.title,
                          fileType: chapter.fileType,
                          mangaInfo: _manga != null
                              ? _cloudToLocal(_manga!)
                              : null,
                        );
                      }

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Đã thêm ${chapters.length} chương vào hàng đợi tải',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                  ),
                  // Nút Đặt vào Thư viện (Folder)
                  StreamBuilder<List<String>>(
                    stream: LibraryService.instance.streamMangaCategories(
                      widget.mangaId,
                    ),
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
                    stream: followService.isFollowing(widget.mangaId),
                    builder: (context, snapshot) {
                      final isFollowed = snapshot.data ?? false;
                      return IconButton(
                        icon: Icon(
                          isFollowed ? Icons.favorite : Icons.favorite_border,
                          color: isFollowed ? Colors.red : Colors.white,
                        ),
                        onPressed: () async {
                          if (isFollowed) {
                            // Hỏi xác nhận hủy theo dõi
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: theme.cardColor,
                                title: Text(
                                  'Hủy Theo Dõi?',
                                  style: theme.textTheme.titleLarge,
                                ),
                                content: Text(
                                  'Bạn có chắc chắn muốn hủy theo dõi truyện này?',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Hủy'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text(
                                      'Đồng ý',
                                      style: TextStyle(color: Colors.redAccent),
                                    ),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              await followService.unfollowManga(widget.mangaId);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Đã hủy theo dõi'),
                                  ),
                                );
                              }
                            }
                          } else {
                            // Theo dõi
                            await followService.followManga(
                              mangaId: manga.id,
                              title: manga.title,
                              coverUrl: DriveService.instance.getThumbnailLink(
                                manga.coverFileId,
                              ),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Đã theo dõi thành công!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          }
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
                                  : (chapters.isNotEmpty
                                        ? 'Chưa đọc'
                                        : 'Chưa có chương'),
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
                      ElevatedButton(
                        onPressed: () async {
                          String? chapterIdToOpen;
                          if (_readerProgress != null &&
                              _readerProgress!.chapterId.isNotEmpty) {
                            chapterIdToOpen = _readerProgress!.chapterId;
                          } else if (_history != null) {
                            chapterIdToOpen = _history!.chapterId;
                          } else if (chapters.isNotEmpty) {
                            // Nếu chưa đọc, bắt đầu từ chương đầu tiên (giả định list đã sort)
                            chapterIdToOpen = chapters.first.id;
                          }

                          if (chapterIdToOpen != null) {
                            await context.push(
                              '/reader/$chapterIdToOpen?mangaId=${Uri.encodeComponent(widget.mangaId)}',
                            );
                            await _fetchLocalReaderData();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9800),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
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

  void _showBookmarkList(ThemeData theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      showDragHandle: true,
      builder: (context) {
        if (_bookmarks.isEmpty) {
          return const SizedBox(
            height: 180,
            child: Center(child: Text('Chưa có bookmark nào')),
          );
        }

        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _bookmarks.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final bookmark = _bookmarks[index];
              return ListTile(
                leading: const Icon(Icons.bookmark, color: Colors.amber),
                title: Text(
                  _chapterTitleFor(bookmark.chapterId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Trang ${bookmark.pageIndex + 1} • ${_formatDate(bookmark.updatedAt)}',
                ),
                trailing: IconButton(
                  tooltip: 'Xóa bookmark',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await DatabaseHelper.instance.deleteBookmark(bookmark.id);
                    await _fetchBookmarks();
                    if (context.mounted) Navigator.pop(context);
                    if (mounted) _showBookmarkList(theme);
                  },
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await context.push(
                    '/reader/${bookmark.chapterId}?mangaId=${Uri.encodeComponent(widget.mangaId)}',
                  );
                  await _fetchLocalReaderData();
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showReadingStatusDialog(ThemeData theme) async {
    final selected = await showModalBottomSheet<MangaReadingStatus>(
      context: context,
      backgroundColor: theme.cardColor,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...MangaReadingStatus.values.map((status) {
                final isSelected = _libraryStatus?.status == status;
                return ListTile(
                  leading: Icon(
                    _statusIcon(status),
                    color: isSelected ? Colors.orange : null,
                  ),
                  title: Text(_statusLabel(status)),
                  trailing: isSelected ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, status),
                );
              }),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.sell_outlined),
                title: const Text('Tag tùy chỉnh'),
                subtitle: Text(
                  (_libraryStatus?.tags.isNotEmpty ?? false)
                      ? _libraryStatus!.tags.join(', ')
                      : 'Chưa có tag',
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
    await _fetchLocalReaderData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã đặt trạng thái: ${_statusLabel(selected)}')),
    );
  }

  Future<void> _showTagsDialog() async {
    final controller = TextEditingController(
      text: _libraryStatus?.tags.join(', ') ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tag tùy chỉnh'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ví dụ: hay, đọc sau, ưu tiên',
            helperText: 'Phân tách tag bằng dấu phẩy',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;

    final tags = result
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    await LibraryStatusService.instance.setTags(widget.mangaId, tags);
    await _fetchLocalReaderData();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã cập nhật tag')));
  }

  IconData _statusIcon(MangaReadingStatus? status) {
    switch (status) {
      case MangaReadingStatus.completed:
        return Icons.done_all;
      case MangaReadingStatus.paused:
        return Icons.pause_circle_outline;
      case MangaReadingStatus.dropped:
        return Icons.remove_circle_outline;
      case MangaReadingStatus.planToRead:
        return Icons.schedule;
      case MangaReadingStatus.reading:
      case null:
        return Icons.menu_book_outlined;
    }
  }

  String _statusLabel(MangaReadingStatus status) {
    switch (status) {
      case MangaReadingStatus.reading:
        return 'Đang đọc';
      case MangaReadingStatus.completed:
        return 'Đã đọc xong';
      case MangaReadingStatus.paused:
        return 'Tạm dừng';
      case MangaReadingStatus.dropped:
        return 'Dropped';
      case MangaReadingStatus.planToRead:
        return 'Đọc sau';
    }
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

    int addedCount = 0;

    for (final chapter in chapters) {
      // Kiểm tra xem đã tải hay đang chờ tải chưa
      final isDownloaded = await DownloadService.instance.isDownloaded(
        chapter.id,
        mangaId: widget.mangaId,
      );
      if (isDownloaded) continue;

      final status = DownloadService.instance.getDownloadStatus(chapter.id);
      if (status != DownloadStatus.idle && status != DownloadStatus.failed) {
        continue;
      }

      // Thêm vào hàng đợi tải
      await DownloadService.instance.addToQueue(
        chapterId: chapter.id,
        mangaId: widget.mangaId,
        mangaTitle: _manga!.title,
        chapterTitle: chapter.title,
        fileType: chapter.fileType,
        mangaInfo: _cloudToLocal(_manga!),
      );
      addedCount++;
    }

    if (mounted && addedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã thêm $addedCount chương vào hàng đợi tải'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Xem',
            textColor: Colors.white,
            onPressed: () => context.push('/downloads'),
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
    if (chapters.length <= 10) return chapters;
    return chapters.sublist(chapters.length - 10);
  }

  Future<void> _deleteAllDownloads(List<CloudChapter> chapters) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: const Text('Xóa tải xuống?'),
        content: const Text(
          'Bạn có chắc muốn xóa tất cả tải xuống của truyện này?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    int deletedCount = 0;
    for (final chapter in chapters) {
      final isDownloaded = await DownloadService.instance.isDownloaded(
        chapter.id,
        mangaId: widget.mangaId,
      );

      if (isDownloaded) {
        await DownloadService.instance.deleteDownload(chapter.id);
        deletedCount++;
      }
    }

    if (mounted && deletedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã xóa $deletedCount chương tải xuống')),
      );
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
}
