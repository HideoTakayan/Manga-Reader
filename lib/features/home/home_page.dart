import 'package:flutter/material.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../data/drive_service.dart';
import '../../data/models.dart';
import '../../data/models_cloud.dart';
import '../shared/drive_image.dart';
import '../../services/notification_service.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: const _HomeContent(),
    );
  }
}

class _HomeContent extends StatefulWidget {
  const _HomeContent();

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> {
  late Future<List<CloudComic>> _comicsFuture;

  @override
  void initState() {
    super.initState();
    _comicsFuture = DriveService.instance.getComics();
  }

  Future<void> _refresh() async {
    setState(() {
      _comicsFuture = DriveService.instance.getComics(forceRefresh: true);
    });
    await _comicsFuture;
  }

  Comic _fromCloud(CloudComic c) {
    return Comic(
      id: c.id,
      title: c.title,
      author: c.author,
      description: c.description,
      coverUrl: c.coverFileId,
      genres: const [],
    );
  }

  List<Comic> _getNewUpdates(List<Comic> all) {
    // Sắp xếp mặc định theo thời gian cập nhật giảm dần (được xử lý ở DriveService)
    // Lấy 10 truyện mới nhất
    return all.take(10).toList();
  }

  List<Comic> _getRandom(List<Comic> all, int count) {
    final list = List<Comic>.from(all)..shuffle();
    return list.take(count).toList();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: Colors.redAccent,
      backgroundColor: Theme.of(context).cardColor,
      child: StreamBuilder<GoogleSignInAccount?>(
        stream: DriveService.instance.onAuthStateChanged,
        initialData: DriveService.instance.currentUser,
        builder: (context, authSnapshot) {
          return FutureBuilder<List<CloudComic>>(
            future: _comicsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final cloudComics = snapshot.data ?? [];
              final allComics = cloudComics.map(_fromCloud).toList();

              if (allComics.isEmpty) {
                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Chưa có truyện nào.",
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (authSnapshot.data == null)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  "(Bạn cần đăng nhập trong trang Quản trị để xem truyện)",
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            TextButton(
                              onPressed: _refresh,
                              child: const Text("Tải lại"),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }

              // 1. Mới cập nhật (10 truyện mới nhất)
              final newUpdates = _getNewUpdates(allComics);

              // 2. Random cho các mục khác
              final featured = _getRandom(allComics, 10);
              final hotToday = _getRandom(allComics, 10);
              final trending = _getRandom(allComics, 10);

              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Thanh công cụ phía trên (AppBar), ẩn đi khi cuộn xuống
                  SliverAppBar(
                    floating: true,
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                    elevation: 0,
                    title: Row(
                      children: [
                        const Icon(
                          Icons.auto_stories,
                          color: Colors.redAccent,
                          size: 30,
                        ),
                        const SizedBox(width: 8),
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Colors.redAccent, Colors.orangeAccent],
                          ).createShader(bounds),
                          child: Text(
                            'MangaReader',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: Theme.of(
                                context,
                              ).textTheme.titleLarge?.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      // Nút Chuông Thông Báo
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: NotificationService.instance
                            .streamUserNotifications(),
                        builder: (context, snapshot) {
                          final notifications = snapshot.data ?? [];
                          final hasUnread = notifications.any(
                            (n) => n['isRead'] != true,
                          );

                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.notifications_none,
                                  color: Theme.of(context).iconTheme.color,
                                ),
                                onPressed: () => context.push('/notifications'),
                              ),
                              if (hasUnread)
                                Positioned(
                                  right: 12,
                                  top: 12,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: Colors.redAccent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.search,
                          color: Theme.of(context).iconTheme.color,
                        ),
                        onPressed: () => context.push('/search-global'),
                      ),
                    ],
                  ),

                  // Banner tự động trượt (Hiển thị các truyện nổi bật)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _AutoSlideBanner(comics: featured),
                    ),
                  ),

                  // 🔥 Mục Truyện Hot Hôm Nay
                  _SectionTitle(
                    label: '🔥 Truyện Hot Hôm Nay',
                    onViewAll: () {},
                  ),
                  _MangaReaderCarousel(comics: hotToday),

                  // 🆕 Mới cập nhật (Top 10 mới nhất)
                  _SectionTitle(label: '🆕 Mới Cập Nhật', onViewAll: () {}),
                  _MangaReaderCarousel(comics: newUpdates),

                  // 🏆 Top Trending (Random 10)
                  _SectionTitle(label: '🏆 Top Trending', onViewAll: () {}),
                  SliverToBoxAdapter(child: _RankList(comics: trending)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  final VoidCallback? onViewAll;
  const _SectionTitle({required this.label, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            TextButton(
              onPressed: onViewAll,
              child: const Text('', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MangaReaderCarousel extends StatelessWidget {
  final List<Comic> comics;
  const _MangaReaderCarousel({required this.comics});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 220,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: comics.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final c = comics[index];
            return GestureDetector(
              onTap: () => context.push('/detail/${c.id}'),
              child: SizedBox(
                width: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: DriveImage(
                                fileId: c.coverUrl, // Actually coverFileId
                                fit: BoxFit.cover,
                                width: 140,
                                height: double.infinity,
                              ),
                            ),
                          ),
                          const Positioned(
                            top: 6,
                            right: 6,
                            child: Icon(
                              Icons.favorite_border,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Chapter 1',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RankList extends StatelessWidget {
  final List<Comic> comics;
  const _RankList({required this.comics});

  @override
  Widget build(BuildContext context) {
    final rankColors = [Colors.amber, Colors.orangeAccent, Colors.redAccent];

    return Column(
      children: List.generate(comics.length, (i) {
        final c = comics[i];
        final color = i < 3 ? rankColors[i] : Colors.white54;

        return ListTile(
          onTap: () => context.push('/detail/${c.id}'),
          leading: Stack(
            alignment: Alignment.topLeft,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: DriveImage(
                  fileId: c.coverUrl,
                  width: 50,
                  height: 70,
                  fit: BoxFit.cover,
                ),
              ),
              if (i < 3)
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.9),
                      borderRadius: const BorderRadius.only(
                        bottomRight: Radius.circular(8),
                      ),
                    ),
                    child: Text(
                      '#${i + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            c.title,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontSize: 16),
          ),
          subtitle: Text(
            'Tác giả: ${c.author}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      }),
    );
  }
}

class _AutoSlideBanner extends StatefulWidget {
  final List<Comic> comics;
  const _AutoSlideBanner({required this.comics});

  @override
  State<_AutoSlideBanner> createState() => _AutoSlideBannerState();
}

class _AutoSlideBannerState extends State<_AutoSlideBanner> {
  late final PageController _controller;
  int _currentPage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.9);

    // Start auto-slide timer
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) return;
      if (widget.comics.isEmpty) return;

      final nextPage = (_currentPage + 1) % widget.comics.length;
      _controller.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
      // _currentPage will be updated in onPageChanged
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.comics.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.comics.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              final c = widget.comics[index];
              return GestureDetector(
                onTap: () => context.push('/detail/${c.id}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Ảnh nền
                        DriveImage(
                          fileId: c.coverUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),

                        // Hiệu ứng gradient mờ ở dưới ảnh để nổi chữ
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: 60,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black54,
                                  Colors.black87,
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Tên truyện hiển thị ở góc dưới
                        Positioned(
                          left: 12,
                          bottom: 12,
                          right: 12,
                          child: Text(
                            c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  color: Colors.black54,
                                  offset: Offset(1, 1),
                                  blurRadius: 4,
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
            },
          ),
        ),
        const SizedBox(height: 8),
        // Chấm nhỏ báo trang hiện tại
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.comics.length, (i) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _currentPage == i ? 12 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: _currentPage == i
                    ? Colors.redAccent
                    : Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}
