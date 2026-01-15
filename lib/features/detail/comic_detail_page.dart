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
import '../../services/notification_service.dart';

class ComicDetailPage extends StatefulWidget {
  final String comicId;
  const ComicDetailPage({super.key, required this.comicId});

  @override
  State<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends State<ComicDetailPage> {
  ReadingHistory? _history;
  CloudComic? _comic;
  List<CloudChapter> _chapters = [];
  bool _isLoading = true;
  bool _isDescriptionExpanded = false;

  // Dữ liệu giả cho phần bình luận (chức năng comment chưa hoàn thiện)
  List<String> comments = [];
  final TextEditingController _commentController = TextEditingController();

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

  /// Tải dữ liệu tổng hợp cho trang chi tiết (Truyện, Chapters, Lịch sử)
  /// Sử dụng `forceRefresh` để lấy dữ liệu mới nhất nếu được gọi từ thao tác pull-to-refresh
  Future<void> _fetchData() async {
    // Nếu chưa có dữ liệu truyện, hiển thị loading
    if (_comic == null) {
      if (mounted) setState(() => _isLoading = true);
    }

    try {
      // 1. Lấy thông tin chi tiết của truyện từ Drive Service
      final comics = await DriveService.instance.getComics(forceRefresh: true);
      final comic = comics.firstWhere(
        (c) => c.id == widget.comicId,
        orElse: () => CloudComic(
          id: '',
          title: '',
          coverFileId: '',
          author: '',
          status: '',
          description: '',
          updatedAt: DateTime.now(),
          genres: [],
          chapterOrder: [],
        ),
      );

      if (comic.id.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 2. Lấy danh sách các chương
      final chapters = await DriveService.instance.getChapters(widget.comicId);

      // 3. Tải lịch sử đọc
      await _fetchHistory();

      if (mounted) {
        setState(() {
          _comic = comic;
          _chapters = chapters;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading comic detail: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchHistory() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    ReadingHistory? history;

    // Bước 1: Thử lấy dữ liệu từ Cloud Firestore (nếu người dùng đã đăng nhập)
    if (userId != null) {
      history = await HistoryService.instance.getHistoryForComic(
        widget.comicId,
      );
    }

    // Bước 2: Nếu không có trên Cloud (hoặc guest), tìm trong Local Database
    if (history == null) {
      final localUserId = userId ?? 'guest';
      history = await DatabaseHelper.instance.getHistoryForComic(
        localUserId,
        widget.comicId,
      );
    }

    if (mounted) {
      setState(() {
        _history = history;
      });
    }
  }

  // Helper method removed as its merged into _fetchData

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final comic = _comic;
    if (comic == null || comic.id.isEmpty) {
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
                          fileId: comic.coverFileId,
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
                                  fileId: comic.coverFileId,
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
                                    comic.title,
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
                                          comic.author,
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
                                        comic.status,
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
                                        .streamComicStats(widget.comicId),
                                    builder: (context, statsSnapshot) {
                                      final stats =
                                          statsSnapshot.data ??
                                          {
                                            'viewCount': comic.viewCount,
                                            'likeCount': comic.likeCount,
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
                                          const SizedBox(width: 16),
                                          // Notification Subscriptions Count
                                          StreamBuilder<int>(
                                            stream: NotificationService.instance
                                                .streamComicNotificationCount(
                                                  widget.comicId,
                                                ),
                                            builder: (context, snapshot) {
                                              final count = snapshot.data ?? 0;
                                              return Row(
                                                children: [
                                                  const Icon(
                                                    Icons.notifications_none,
                                                    size: 16,
                                                    color: Colors.white70,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    _formatCount(count),
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
                      itemCount: comic.genres.isNotEmpty
                          ? comic.genres.length
                          : 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final genre = comic.genres.isNotEmpty
                            ? comic.genres[index]
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
                        // Đã xóa nút xem thêm chương ở đây vì đã hiển thị hết danh sách
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
                                comic.description,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.4,
                                  color: Colors.white70,
                                ),
                                maxLines: _isDescriptionExpanded ? null : 4,
                                overflow: _isDescriptionExpanded
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                              ),
                              if (comic.description.length > 150)
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
                                      .streamChapterViews(widget.comicId),
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
                  // Nút Chuông Thông Báo
                  StreamBuilder<bool>(
                    stream: NotificationService.instance
                        .streamSubscriptionStatus(widget.comicId),
                    builder: (context, snapshot) {
                      final isSubscribed = snapshot.data ?? false;
                      return IconButton(
                        icon: Icon(
                          isSubscribed
                              ? Icons.notifications_active
                              : Icons.notifications_none,
                          color: isSubscribed ? Colors.yellow : Colors.white,
                        ),
                        onPressed: () async {
                          await NotificationService.instance.toggleSubscription(
                            widget.comicId,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isSubscribed
                                      ? 'Đã tắt thông báo cho truyện này'
                                      : 'Đã bật thông báo thành công!',
                                ),
                                backgroundColor: isSubscribed
                                    ? Colors.red
                                    : Colors.green,
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                  // Nút Theo Dõi (Tim)
                  StreamBuilder<bool>(
                    stream: followService.isFollowing(widget.comicId),
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
                              await followService.unfollowComic(widget.comicId);
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
                            await followService.followComic(
                              comicId: comic.id,
                              title: comic.title,
                              coverUrl: DriveService.instance.getThumbnailLink(
                                comic.coverFileId,
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
}
