import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/follow_service.dart';
import '../shared/drive_image.dart';
import '../../data/models_cloud.dart';
import '../../data/models.dart';
import '../../data/drive_service.dart';
import '../../data/database_helper.dart';
import '../../services/history_service.dart';
import '../../services/interaction_service.dart';
import '../../services/library_service.dart';
import '../../services/download_service.dart';
import '../../services/folder_service.dart';
import '../../core/utils/chapter_sort_helper.dart';
import '../../core/utils/chapter_utils.dart';
import '../shared/library_dialogs.dart';

class MangaDetailPage extends StatefulWidget {
  final String mangaId;
  const MangaDetailPage({super.key, required this.mangaId});

  @override
  State<MangaDetailPage> createState() => _MangaDetailPageState();
}

class _MangaDetailPageState extends State<MangaDetailPage> {
  ReadingHistory? _history;
  CloudManga? _manga;
  List<CloudChapter> _chapters = [];
  bool _isLoading = true;
  bool _isDescriptionExpanded = false;

  // Dữ liệu giả cho phần bình luận (chức năng comment chưa hoàn thiện)
  List<String> comments = [];
  final TextEditingController _commentController = TextEditingController();

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
    _commentController.dispose();
    super.dispose();
  }

  /// Tải dữ liệu tổng hợp cho trang chi tiết (Offline First Strategy)
  Future<void> _fetchData() async {
    if (_manga == null) {
      if (mounted) setState(() => _isLoading = true);
    }

    try {
      // --- 1. OFFLINE FIRST: Try Load Local Data ---
      CloudManga? localData;
      List<CloudChapter> localChaptersList = [];

      // A. Try DB Info
      Manga? dbManga = await DatabaseHelper.instance.getLocalManga(
        widget.mangaId,
      );

      // B. If no DB Info, recover metadata from Downloaded Chapters (Backward Compatibility)
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
        // Construct CloudManga wrapper for UI
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

        // 🔧 FIX: Deduplicate downloaded chapters (phòng trường hợp DB có duplicate)
        final Map<String, Map<String, dynamic>> uniqueDownloads = {};
        for (final d in downloadedMaps) {
          final chapterId = d['chapterId'] as String;
          // Giữ entry mới nhất (downloadDate cao nhất)
          if (!uniqueDownloads.containsKey(chapterId) ||
              (d['downloadDate'] ?? 0) >
                  (uniqueDownloads[chapterId]!['downloadDate'] ?? 0)) {
            uniqueDownloads[chapterId] = d;
          }
        }

        localChaptersList = uniqueDownloads.values.map((d) {
          return CloudChapter(
            id: d['chapterId'],
            title: d['chapterTitle'] ?? d['chapterId'],
            fileId: d['chapterId'],
            fileType: 'cbz',
            uploadedAt: DateTime.fromMillisecondsSinceEpoch(
              d['downloadDate'] ?? 0,
            ),
            viewCount: 0,
          );
        }).toList();

        // Sort numeric ascending (Match Online Mode)
        localChaptersList = ChapterSortHelper.sort(localChaptersList);
      }

      // Show local data immediately if available
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
            // Keep loading true to verify network
          });
        }
      }

      // --- 2. NETWORK SYNC (Try to get fresh data) ---
      final mangas = await DriveService.instance.getMangas(forceRefresh: true);
      final manga = mangas.firstWhere(
        (c) => c.id == widget.mangaId,
        orElse: () => throw Exception('Manga not found on server'),
      );

      final chapters = await DriveService.instance.getChapters(widget.mangaId);

      // Save fresh info to local DB
      await DatabaseHelper.instance.saveLocalManga(_cloudToLocal(manga));
      await _fetchHistory();

      // 🔧 FIX: Advanced Deduplication & Sort (Centralized)
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

      // If we have local data, consider it a success state (Offline Mode)
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
        // Real error (No local data, no network)
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchHistory() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    ReadingHistory? history;

    // Bước 1: Thử lấy dữ liệu từ Cloud Firestore (nếu người dùng đã đăng nhập)
    if (userId != null) {
      history = await HistoryService.instance.getHistoryForManga(
        widget.mangaId,
      );
    }

    // Bước 2: Nếu không có trên Cloud (hoặc guest), tìm trong Local Database
    if (history == null) {
      final localUserId = userId ?? 'guest';
      history = await DatabaseHelper.instance.getHistoryForManga(
        localUserId,
        widget.mangaId,
      );
    }

    if (mounted) {
      setState(() {
        _history = history;
      });
    }
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
                  child: Stack(
                    children: [
                      // Background mờ
                      Positioned.fill(
                        child: DriveImage(
                          fileId: manga.coverFileId,
                          fit: BoxFit.cover,
                        ),
                      ),
                      // Darken overlay
                      Positioned.fill(
                        child: Container(color: Colors.black.withOpacity(0.7)),
                      ),
                      // Gradient che dưới (Hòa vào nền Scaffold)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                theme.scaffoldBackgroundColor,
                              ],
                              stops: const [0.0, 1.0],
                            ),
                          ),
                        ),
                      ),

                      // Nội dung chính
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 80, 16, 20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Ảnh bìa chính
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 120,
                                height: 160,
                                child: DriveImage(
                                  fileId: manga.coverFileId,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Thông tin bên phải
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    manga.title,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: Colors
                                          .white, // Always white on dark header
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.person_outline,
                                        size: 16,
                                        color: Colors.white70,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          manga.author,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.info_outline,
                                        size: 16,
                                        color: Colors.white70,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        manga.status,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.list,
                                        size: 16,
                                        color: Colors.white70,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Chương ${chapters.length}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  StreamBuilder<Map<String, int>>(
                                    stream: InteractionService.instance
                                        .streamMangaStats(widget.mangaId),
                                    builder: (context, statsSnapshot) {
                                      final stats =
                                          statsSnapshot.data ??
                                          {
                                            'viewCount': manga.viewCount,
                                            'likeCount': manga.likeCount,
                                          };
                                      final viewCount = stats['viewCount'] ?? 0;
                                      final likeCount = stats['likeCount'] ?? 0;

                                      return Row(
                                        children: [
                                          const Icon(
                                            Icons.remove_red_eye_outlined,
                                            size: 16,
                                            color: Colors.white70,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$viewCount',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          const Icon(
                                            Icons.favorite_border,
                                            size: 16,
                                            color: Colors.white70,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatCount(likeCount),
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                            : "Manhwa"; // Default if empty
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
                                color: Colors.white.withOpacity(0.1),
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
                        // Action Menu
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) async {
                            if (value == 'download_all') {
                              _downloadManyChapters(chapters);
                            } else if (value == 'download_latest_10') {
                              _downloadManyChapters(chapters.take(10).toList());
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Giới Thiệu',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isDescriptionExpanded = !_isDescriptionExpanded;
                            });
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                manga.description,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.4,
                                  color: Colors.white70,
                                ),
                                maxLines: _isDescriptionExpanded ? null : 4,
                                overflow: _isDescriptionExpanded
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                              ),
                              if (manga.description.length > 150)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    _isDescriptionExpanded
                                        ? 'Rút gọn'
                                        : 'Xem thêm...',
                                    style: TextStyle(
                                      color: theme.primaryColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 20)),

                // 5. Danh sách các chương (Hiển thị dạng List)
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final ch = displayChapters[index];
                    return InkWell(
                      onTap: () async {
                        await context.push('/reader/${ch.id}');
                        // Khi quay lại, làm mới toàn bộ dữ liệu để cập nhật views/history
                        _fetchData();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: theme.dividerColor.withOpacity(0.1),
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                ch.title,
                                style: theme.textTheme.bodyLarge,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatDate(ch.uploadedAt),
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: 2),
                                // Sử dụng StreamBuilder để cập nhật lượt xem thời gian thực cho từng chapter
                                StreamBuilder<Map<String, int>>(
                                  stream: InteractionService.instance
                                      .streamChapterViews(widget.mangaId),
                                  builder: (context, snapshot) {
                                    final viewsMap = snapshot.data ?? {};
                                    final views =
                                        viewsMap[ch.id] ?? ch.viewCount;

                                    return Row(
                                      children: [
                                        Icon(
                                          Icons.remove_red_eye,
                                          size: 10,
                                          color:
                                              theme.textTheme.bodySmall?.color,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          '$views',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(fontSize: 10),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            // Download Icon với 3 trạng thái
                            StreamBuilder<Map<String, DownloadTask>>(
                              stream: DownloadService.instance.downloadStream,
                              builder: (context, downloadSnapshot) {
                                final task = downloadSnapshot.data?[ch.id];

                                // Nếu đang tải
                                if (task?.status ==
                                    DownloadStatus.downloading) {
                                  return SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        CircularProgressIndicator(
                                          value: task!.progress,
                                          strokeWidth: 3,
                                          valueColor:
                                              const AlwaysStoppedAnimation<
                                                Color
                                              >(Colors.blue),
                                          backgroundColor: Colors.grey
                                              .withOpacity(0.3),
                                        ),
                                        Text(
                                          '${(task.progress * 100).toInt()}%',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                theme.brightness ==
                                                    Brightness.dark
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                // Nếu đang chờ trong queue
                                if (task?.status == DownloadStatus.queued) {
                                  return SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            Colors.orange,
                                          ),
                                      backgroundColor: Colors.grey.withOpacity(
                                        0.3,
                                      ),
                                    ),
                                  );
                                }

                                // Nếu bị tạm dừng
                                if (task?.status == DownloadStatus.paused) {
                                  return IconButton(
                                    icon: const Icon(
                                      Icons.pause_circle,
                                      size: 28,
                                      color: Colors.orange,
                                    ),
                                    onPressed: () {
                                      DownloadService.instance.resumeDownload(
                                        ch.id,
                                      );
                                    },
                                  );
                                }

                                // Nếu lỗi
                                if (task?.status == DownloadStatus.failed) {
                                  return IconButton(
                                    icon: const Icon(
                                      Icons.error,
                                      size: 28,
                                      color: Colors.red,
                                    ),
                                    onPressed: () {
                                      DownloadService.instance.retryDownload(
                                        ch.id,
                                      );
                                    },
                                  );
                                }

                                // Kiểm tra đã tải chưa
                                return FutureBuilder<bool>(
                                  future: DownloadService.instance.isDownloaded(
                                    ch.id,
                                    mangaId: widget
                                        .mangaId, // Use cache for faster check
                                  ),
                                  builder: (context, snapshot) {
                                    final isDownloaded = snapshot.data ?? false;

                                    return IconButton(
                                      icon: Icon(
                                        isDownloaded
                                            ? Icons.check_circle
                                            : Icons.download_outlined,
                                        size: 28,
                                        color: isDownloaded
                                            ? Colors.green
                                            : theme.iconTheme.color
                                                  ?.withOpacity(0.6),
                                      ),
                                      onPressed: () async {
                                        if (isDownloaded) {
                                          // Xóa download
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              backgroundColor: theme.cardColor,
                                              title: Text(
                                                'Xóa chương đã tải?',
                                                style:
                                                    theme.textTheme.titleLarge,
                                              ),
                                              content: Text(
                                                'Bạn có chắc muốn xóa "${ch.title}" khỏi bộ nhớ máy?',
                                                style:
                                                    theme.textTheme.bodyMedium,
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                        false,
                                                      ),
                                                  child: const Text('Hủy'),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                        true,
                                                      ),
                                                  child: const Text(
                                                    'Xóa',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );

                                          if (confirm == true) {
                                            await DownloadService.instance
                                                .deleteDownload(ch.id);
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Đã xóa chương',
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        } else {
                                          // Tải chapter
                                          await DownloadService.instance
                                              .addToQueue(
                                                chapterId: ch.id,
                                                mangaId: widget.mangaId,
                                                mangaTitle: manga.title,
                                                chapterTitle: ch.title,
                                                fileType: ch.fileType,
                                                mangaInfo: _manga != null
                                                    ? _cloudToLocal(_manga!)
                                                    : null,
                                              );

                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Đã thêm vào hàng đợi tải',
                                                ),
                                                backgroundColor: Colors.green,
                                              ),
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
                    );
                  }, childCount: displayChapters.length),
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
                  // Nút Download All Chapters
                  IconButton(
                    icon: const Icon(Icons.download, color: Colors.white),
                    onPressed: () async {
                      // Hỏi có muốn thêm vào thư viện không
                      final addToLibrary = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: theme.cardColor,
                          title: Text(
                            'Tải tất cả chương?',
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

                      if (addToLibrary == null) return;

                      // Nếu chọn thêm vào thư viện
                      if (addToLibrary) {
                        final selectedCats = await LibraryService.instance
                            .streamMangaCategories(widget.mangaId)
                            .first;
                        if (context.mounted) {
                          _showSetCategoryDialog(context, selectedCats);
                        }
                      }

                      // Bắt đầu tải tất cả chapters
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
                  // Nút Đặt vào Thư viện (Folder) - Mới
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
                            // Ask to unfollow
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
                            // Follow
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
                      theme.scaffoldBackgroundColor, // Fade to bg
                      theme.scaffoldBackgroundColor.withOpacity(0.0),
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
                        color: Colors.black.withOpacity(0.1),
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
                              _history != null
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
                          if (_history != null) {
                            chapterIdToOpen = _history!.chapterId;
                          } else if (chapters.isNotEmpty) {
                            // Nếu chưa đọc, bắt đầu từ chương đầu tiên (giả định list đã sort)
                            chapterIdToOpen = chapters.first.id;
                          }

                          if (chapterIdToOpen != null) {
                            await context.push('/reader/$chapterIdToOpen');
                            _fetchHistory(); // Refresh on return
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
                          _history != null ? 'Đọc Tiếp' : 'Bắt Đầu Đọc',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.bookmark_border,
                        color: theme.iconTheme.color?.withOpacity(0.6),
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

  String _formatCount(int count) {
    if (count < 1000) return count.toString();
    if (count < 1000000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '${(count / 1000000).toStringAsFixed(1)}m';
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
      // Check if downloaded or queued
      final isDownloaded = await DownloadService.instance.isDownloaded(
        chapter.id,
        mangaId: widget.mangaId,
      );
      if (isDownloaded) continue;

      final status = DownloadService.instance.getDownloadStatus(chapter.id);
      if (status != DownloadStatus.idle && status != DownloadStatus.failed) {
        continue;
      }

      // Add to queue
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
}
