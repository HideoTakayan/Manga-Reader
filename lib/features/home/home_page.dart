import 'package:flutter/material.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../data/drive_service.dart';
import '../../data/models.dart';
import '../../data/models_cloud.dart';
import '../shared/drive_image.dart';

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

class _HomeContent extends StatelessWidget {
  const _HomeContent();

  Comic _fromCloud(CloudComic c) {
    return Comic(
      id: c.id,
      title: c.title,
      author: c.author,
      description: c.description,
      coverUrl: c.coverFileId, // We use this for DriveImage
      genres: const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GoogleSignInAccount?>(
      stream: DriveService.instance.onAuthStateChanged,
      initialData: DriveService.instance.currentUser,
      builder: (context, authSnapshot) {
        // Log in status changed -> Trigger re-fetch
        return FutureBuilder<List<CloudComic>>(
          future: DriveService.instance.getComics(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final cloudComics = snapshot.data ?? [];
            final comics = cloudComics.map(_fromCloud).toList();

            if (comics.isEmpty) {
              return Center(
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
                      onPressed: () {
                        (context as Element).markNeedsBuild();
                      },
                      child: const Text("Tải lại"),
                    ),
                  ],
                ),
              );
            }

            return CustomScrollView(
              slivers: [
                // 🔺 Thanh tiêu đề
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
                    IconButton(
                      icon: Icon(
                        Icons.search,
                        color: Theme.of(context).iconTheme.color,
                      ),
                      onPressed: () => context.push('/search-global'),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.notifications_none,
                        color: Theme.of(context).iconTheme.color,
                      ),
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Thông báo đang phát triển...'),
                            ),
                          ),
                    ),
                  ],
                ),

                // 🔥 Banner nổi bật (auto-slide)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _AutoSlideBanner(comics: comics),
                  ),
                ),

                // 🔥 Truyện hot
                _SectionTitle(label: '🔥 Truyện Hot Hôm Nay', onViewAll: () {}),
                _MangaReaderCarousel(comics: comics),

                // 🆕 Mới cập nhật
                _SectionTitle(label: '🆕 Mới Cập Nhật', onViewAll: () {}),
                _MangaReaderCarousel(comics: comics.reversed.toList()),

                // 🏆 Top được xem nhiều
                _SectionTitle(label: '🏆 Top Trending', onViewAll: () {}),
                SliverToBoxAdapter(child: _RankList(comics: comics)),
              ],
            );
          },
        );
      },
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
