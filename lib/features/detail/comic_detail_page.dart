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

class ComicDetailPage extends StatefulWidget {
  final String comicId;
  const ComicDetailPage({super.key, required this.comicId});

  @override
  State<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends State<ComicDetailPage> {
  bool showAll = false;
  ReadingHistory? _history;

  // Placeholder for comments until migrated
  List<String> comments = [];
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    ReadingHistory? history;

    // 1. Try fetching from Cloud first (if logged in)
    if (userId != null) {
      history = await HistoryService.instance.getHistoryForComic(
        widget.comicId,
      );
    }

    // 2. Fallback to Local DB if cloud returns null or not logged in
    if (history == null) {
      // Local DB requires non-null userId for querying, use 'guest' or actual ID
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

  Future<CloudComic?> _fetchComic() async {
    final comics = await DriveService.instance.getComics();
    try {
      return comics.firstWhere((c) => c.id == widget.comicId);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CloudComic?>(
      future: _fetchComic(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final comic = snapshot.data;
        if (comic == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Lỗi')),
            body: const Center(child: Text('Không tìm thấy truyện')),
          );
        }

        return FutureBuilder<List<CloudChapter>>(
          future: DriveService.instance.getChapters(widget.comicId),
          builder: (context, chapterSnapshot) {
            final chapters = chapterSnapshot.data ?? [];
            final displayChapters = showAll
                ? chapters
                : chapters.take(5).toList();
            final followService = FollowService();
            final theme = Theme.of(context);

            return Scaffold(
              backgroundColor: theme.scaffoldBackgroundColor,
              // Nút back và menu overlay
              body: Stack(
                children: [
                  CustomScrollView(
                    slivers: [
                      // 1. Header Area (Bìa + Thông tin)
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
                              child: Container(
                                color: Colors.black.withOpacity(0.7),
                              ),
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
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                80,
                                16,
                                20,
                              ),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          comic.title,
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
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
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.remove_red_eye_outlined,
                                              size: 16,
                                              color: Colors.white70,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${comic.viewCount}K',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ), // Tạm dùng K cho đẹp
                                            const SizedBox(width: 16),
                                            const Icon(
                                              Icons.notifications_none,
                                              size: 16,
                                              color: Colors.white70,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${(comic.viewCount / 10).round()}',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ), // Fake sub count
                                            const SizedBox(width: 16),
                                            const Icon(
                                              Icons.favorite_border,
                                              size: 16,
                                              color: Colors.white70,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${comic.likeCount}',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
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
                      ),

                      // 2. Genres (Thể loại)
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 40,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            scrollDirection: Axis.horizontal,
                            itemCount: comic.genres.isNotEmpty
                                ? comic.genres.length
                                : 1,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final genre = comic.genres.isNotEmpty
                                  ? comic.genres[index]
                                  : "Manhwa"; // Default if empty
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  genre,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 12,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      // 3. Tab Bar (Tự chế) - DS Chương / Giới thiệu
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'DS Chương',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  if (chapters.isNotEmpty) {
                                    _showChapterListModal(context, chapters);
                                  }
                                },
                                child: Row(
                                  children: [
                                    Text(
                                      'Chương ${chapters.length}',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    Icon(
                                      Icons.chevron_right,
                                      color: theme.textTheme.bodyMedium?.color,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 4. Giới thiệu Text
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
                              Text(
                                comic.description,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.4,
                                ),
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SliverToBoxAdapter(child: SizedBox(height: 20)),

                      // 5. Danh sách chương
                      SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final ch = displayChapters[index];
                          return InkWell(
                            onTap: () async {
                              await context.push('/reader/${ch.id}');
                              _fetchHistory();
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    ch.title,
                                    style: theme.textTheme.bodyLarge,
                                  ),
                                  Text(
                                    _formatDate(ch.uploadedAt),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }, childCount: displayChapters.length),
                      ),

                      // Padding for Bottom Dock
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),

                  // Top Overlay Buttons
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
                    child: StreamBuilder<bool>(
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
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                await followService.unfollowComic(
                                  widget.comicId,
                                );
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
                                coverUrl: DriveService.instance
                                    .getThumbnailLink(comic.coverFileId),
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
                  ),

                  // Bottom Dock
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
                                  Text(
                                    'Đọc Đến',
                                    style: theme.textTheme.bodySmall,
                                  ),
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
                                  chapterIdToOpen = chapters.last.id;
                                }

                                if (chapterIdToOpen != null) {
                                  await context.push(
                                    '/reader/$chapterIdToOpen',
                                  );
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
                              child: const Text(
                                'Đọc Tiếp',
                                style: TextStyle(fontWeight: FontWeight.bold),
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
            );
          },
        );
      },
    );
  }

  void _showChapterListModal(
    BuildContext context,
    List<CloudChapter> chapters,
  ) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      useSafeArea: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 1.0,
          minChildSize: 0.5,
          maxChildSize: 1.0,
          expand: false,
          builder: (context, scrollController) {
            return Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: theme.appBarTheme.backgroundColor,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.close, color: theme.iconTheme.color),
                  onPressed: () => Navigator.pop(context),
                ),
                title: Text(
                  'DS Chương',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                centerTitle: true,
                actions: [
                  IconButton(
                    icon: Icon(
                      Icons.notifications_none,
                      color: theme.iconTheme.color,
                    ),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: Icon(Icons.swap_vert, color: theme.iconTheme.color),
                    onPressed: () {
                      // TODO: Implement sort
                    },
                  ),
                ],
              ),
              body: ListView.separated(
                controller: scrollController,
                itemCount: chapters.length,
                separatorBuilder: (_, __) =>
                    Divider(color: theme.dividerColor, height: 1),
                itemBuilder: (context, index) {
                  final ch = chapters[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    title: Text(ch.title, style: theme.textTheme.bodyLarge),
                    trailing: Text(
                      _formatDate(ch.uploadedAt),
                      style: theme.textTheme.bodySmall,
                    ),
                    onTap: () async {
                      Navigator.pop(context); // Đóng modal
                      await context.push('/reader/${ch.id}');
                      _fetchHistory();
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays > 0) return '${diff.inDays} ngày trước';
    if (diff.inHours > 0) return '${diff.inHours} giờ trước';
    return 'Mới đây';
  }
}
