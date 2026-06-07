import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui';

import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/content_type.dart';
import '../../data/drive_service.dart';
import '../../data/models.dart';
import '../../data/models_cloud.dart';
import '../shared/drive_image.dart';
import '../../services/notification_service.dart';
import '../../services/permission_service.dart';
import '../../services/folder_service.dart';
import '../../services/sync_service.dart';
import '../../services/follow_service.dart';

import 'widgets/continue_reading_section.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Trang chủ — wrapper mỏng chỉ đặt Scaffold, toàn bộ logic nằm trong _HomeContent.
// Tách ra để theo pattern: StatelessWidget ngoài, StatefulWidget bên trong.
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

class _HomeData {
  final List<CloudManga> mangas;
  final List<String> mangaBannerIds;
  final List<String> novelBannerIds;
  _HomeData(this.mangas, this.mangaBannerIds, this.novelBannerIds);
}

class _HomeContentState extends State<_HomeContent> {
  // Future lưu kết quả getMangas() và banner settings
  late Future<_HomeData> _homeDataFuture;
  MangaContentType _selectedContentType = MangaContentType.manga;

  @override
  void initState() {
    super.initState();
    _homeDataFuture = _loadData();
    _loadContentTypePreference();

    // Dùng addPostFrameCallback vì không được gọi side-effect trong initState —
    // widget chưa gắn vào tree, context chưa sẵn sàng.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Đồng bộ lịch sử đọc offline (khi không có mạng) lên Firestore
      SyncService.instance.syncPendingHistory();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Kiểm tra quyền storage để lưu file manga xuống thư mục /MangaReader/
      _checkStoragePermission();
    });

    _homeDataFuture.then((_) {
      NotificationService.instance.checkLocalChapterUpdates();
    });
  }

  Future<void> _loadContentTypePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final type = parseContentType(prefs.getString('home_content_type'));
    if (mounted) {
      setState(() => _selectedContentType = type);
    }
  }

  Future<void> _toggleContentType() async {
    final next = _selectedContentType.isManga
        ? MangaContentType.novel
        : MangaContentType.manga;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('home_content_type', next.name);
    if (mounted) {
      setState(() => _selectedContentType = next);
    }
  }

  Future<_HomeData> _loadData({bool forceRefresh = false}) async {
    final mangas = await DriveService.instance.getMangas(
      forceRefresh: forceRefresh,
    );

    List<String> mangaBannerIds = [];
    List<String> novelBannerIds = [];
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('home_banner')
          .get();
      if (doc.exists) {
        mangaBannerIds = List<String>.from(doc.data()?['mangaIds'] ?? []);
        novelBannerIds = List<String>.from(doc.data()?['novelIds'] ?? []);
      }
    } catch (e) {
      debugPrint('Lỗi tải banner: $e');
    }

    return _HomeData(mangas, mangaBannerIds, novelBannerIds);
  }

  // Nếu chưa có quyền storage → hiện dialog xin quyền.
  // barrierDismissible: false → bắt buộc user phải chọn, không dismiss bằng tap ngoài.
  Future<void> _checkStoragePermission() async {
    final hasPermission = await PermissionService.hasStoragePermission();
    if (!hasPermission) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Cấp quyền truy cập'),
          content: const Text(
            'Để lưu truyện vào thư mục "/MangaReader" ở bộ nhớ máy và dễ dàng quản lý file, ứng dụng cần quyền truy cập bộ nhớ.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Để sau'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                final granted =
                    await PermissionService.requestStoragePermission();
                if (granted) {
                  // Khởi tạo lại FolderService để dùng đường dẫn mới sau khi cấp quyền
                  await FolderService.init();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '✅ Đã cấp quyền! Folder MangaReader đã được tạo.',
                        ),
                      ),
                    );
                  }
                }
              },
              child: const Text('Cấp quyền'),
            ),
          ],
        ),
      );
    }
  }

  // Pull-to-refresh: tạo Future mới với forceRefresh=true → FutureBuilder tự rebuild
  Future<void> _refresh() async {
    setState(() {
      _homeDataFuture = _loadData(forceRefresh: true);
    });
    await _homeDataFuture;
    await NotificationService.instance.checkLocalChapterUpdates();
  }

  // Helper: chuyển CloudManga → Manga (local model) để truyền vào các widget con
  Manga _fromCloud(CloudManga c) {
    return Manga(
      id: c.id,
      title: c.title,
      author: c.author,
      description: c.description,
      coverUrl: c.coverFileId,
      genres: const [],
      contentType: c.contentType,
    );
  }

  // Mục "Mới Cập Nhật": lấy 10 truyện đầu (Drive đã sort theo updatedAt giảm dần)
  List<Manga> _getNewUpdates(List<Manga> all) => all.take(10).toList();

  // "Hot Hôm Nay": Lượt view cao trong ngày (giả lập bằng truyện cập nhật 24h qua)
  // Nếu view bằng nhau thì hiển thị ngẫu nhiên
  List<Manga> _getHotToday(List<CloudManga> all, int count) {
    final now = DateTime.now();
    final recent = all
        .where((m) => now.difference(m.updatedAt).inHours <= 24)
        .toList();
    var sourceList = recent.length >= count
        ? recent
        : List<CloudManga>.from(all);

    // Xáo trộn danh sách trước. Hàm sort của Dart là stable sort,
    // nên nếu viewCount bằng nhau, thứ tự ngẫu nhiên này sẽ được giữ lại.
    sourceList.shuffle();
    sourceList.sort((a, b) => b.viewCount.compareTo(a.viewCount));

    return sourceList.take(count).map(_fromCloud).toList();
  }

  // "Top Trending": Lượt view cao trong tháng (giả lập bằng truyện cập nhật 30 ngày qua)
  // Nếu view bằng nhau thì hiển thị ngẫu nhiên
  List<Manga> _getTrending(List<CloudManga> all, int count) {
    final now = DateTime.now();
    final recent = all
        .where((m) => now.difference(m.updatedAt).inDays <= 30)
        .toList();
    var sourceList = recent.length >= count
        ? recent
        : List<CloudManga>.from(all);

    sourceList.shuffle();
    sourceList.sort((a, b) => b.viewCount.compareTo(a.viewCount));

    return sourceList.take(count).map(_fromCloud).toList();
  }

  // Banner nổi bật (Featured): Ưu tiên lấy từ Firestore, nếu trống thì lấy ngẫu nhiên
  List<Manga> _getFeatured(List<Manga> all, List<String> bannerIds, int count) {
    if (bannerIds.isNotEmpty) {
      final featured = all.where((m) => bannerIds.contains(m.id)).toList();
      if (featured.isNotEmpty) {
        // Giữ đúng thứ tự admin đã chọn
        featured.sort(
          (a, b) => bannerIds.indexOf(a.id).compareTo(bannerIds.indexOf(b.id)),
        );
        return featured;
      }
    }

    final list = List<Manga>.from(all)..shuffle();
    return list.take(count).toList();
  }

  // Shimmer skeleton hiển thị khi đang chờ getMangas() — không cần package ngoài.
  // Dùng TweenAnimationBuilder để tạo hiệu ứng opacity pulse liên tục.
  Widget _buildShimmerSkeleton(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.05, end: 0.15),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      onEnd: () => setState(() {}), // loop animation
      builder: (context, alpha, _) {
        return CustomScrollView(
          physics: const NeverScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
                child: _shimmerBox(40, 180, alpha),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _shimmerBox(200, double.infinity, alpha, radius: 12),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _shimmerBox(18, 130, alpha, radius: 6),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 160,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: 5,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, __) =>
                      _shimmerBox(160, 110, alpha, radius: 10),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _shimmerBox(18, 150, alpha, radius: 6),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 160,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: 5,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, __) =>
                      _shimmerBox(160, 110, alpha, radius: 10),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _shimmerBox(
    double height,
    double width,
    double alpha, {
    double radius = 8,
  }) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: Colors.white.withValues(alpha: alpha),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: Colors.redAccent,
      backgroundColor: Theme.of(context).cardColor,
      // StreamBuilder ngoài cùng: lắng nghe trạng thái đăng nhập Drive OAuth.
      // Dùng để kiểm tra authSnapshot.data == null → hiện gợi ý "cần đăng nhập Admin"
      child: StreamBuilder<GoogleSignInAccount?>(
        stream: DriveService.instance.onAuthStateChanged,
        initialData: DriveService.instance.currentUser,
        builder: (context, authSnapshot) {
          // FutureBuilder bên trong: chờ tải xong data mới render nội dung
          return FutureBuilder<_HomeData>(
            future: _homeDataFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildShimmerSkeleton(context);
              }

              if (snapshot.hasError) {
                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Đã xảy ra lỗi:\n${snapshot.error}',
                              style: const TextStyle(color: Colors.redAccent),
                              textAlign: TextAlign.center,
                            ),
                            TextButton(
                              onPressed: _refresh,
                              child: const Text('Tải lại'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }

              final homeData = snapshot.data;
              final cloudMangas = homeData?.mangas ?? [];
              final visibleCloudMangas = cloudMangas
                  .where((m) => m.contentType == _selectedContentType)
                  .toList();
              final bannerIds = _selectedContentType.isNovel
                  ? homeData?.novelBannerIds ?? []
                  : homeData?.mangaBannerIds ?? [];
              final allMangas = visibleCloudMangas.map(_fromCloud).toList();

              if (allMangas.isEmpty) {
                // AlwaysScrollableScrollPhysics: cho phép kéo refresh ngay cả khi empty
                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _selectedContentType.isNovel
                                  ? 'Chưa có novel nào.'
                                  : 'Chưa có truyện tranh nào.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            // Gợi ý thêm khi chưa đăng nhập Drive OAuth
                            if (authSnapshot.data == null)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  '(Bạn cần đăng nhập trong trang Quản trị để xem truyện)',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            TextButton(
                              onPressed: _refresh,
                              child: const Text('Tải lại'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }

              // Phân loại danh sách cho từng section
              final newUpdates = _getNewUpdates(allMangas);
              final featured = _getFeatured(allMangas, bannerIds, 10);
              final hotToday = _getHotToday(
                visibleCloudMangas,
                10,
              ); // Sort theo viewCount
              final trending = _getTrending(
                visibleCloudMangas,
                10,
              ); // Sort theo likeCount

              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // AppBar nổi (floating: true) — ẩn khi cuộn xuống, hiện lại khi cuộn lên
                  SliverAppBar(
                    floating: true,
                    pinned: true,
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.85),
                    flexibleSpace: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                    elevation: 0,
                    title: Row(
                      children: [
                        const Icon(
                          Icons.auto_stories,
                          color: Colors.redAccent,
                          size: 30,
                        ),
                        const SizedBox(width: 8),
                        // ShaderMask: tô màu gradient cho text "MangaReader"
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
                      // Chuông thông báo: chấm đỏ hiện khi có thông báo chưa đọc
                      StreamBuilder<List<AppNotification>>(
                        stream: NotificationService.instance
                            .streamUserNotifications(),
                        builder: (context, snapshot) {
                          final notifications = snapshot.data ?? [];
                          final hasUnread = notifications.any((n) => !n.isRead);
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
                              // Chấm đỏ nhỏ — Positioned chồng lên icon khi có unread
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
                        tooltip: _selectedContentType.isManga
                            ? 'Chuyển sang Novel'
                            : 'Chuyển sang Truyện tranh',
                        icon: Icon(
                          Icons.swap_vert,
                          color: Theme.of(context).iconTheme.color,
                        ),
                        onPressed: _toggleContentType,
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.search,
                          color: Theme.of(context).iconTheme.color,
                        ),
                        onPressed: () => context.push(
                          '/search-global?type=${_selectedContentType.name}',
                        ),
                      ),
                    ],
                  ),

                  const ContinueReadingSection(),

                  SliverToBoxAdapter(
                    child: _AutoSlideBanner(mangas: featured),
                  ),

                  _SectionTitle(
                    label: _selectedContentType.isNovel
                        ? 'Novel Hot Hôm Nay'
                        : '🔥 Truyện Hot Hôm Nay',
                  ),
                  _MangaReaderCarousel(mangas: hotToday),

                  _SectionTitle(
                    label: _selectedContentType.isNovel
                        ? 'Novel Mới Cập Nhật'
                        : '🆕 Mới Cập Nhật',
                  ),
                  _MangaReaderCarousel(mangas: newUpdates),

                  _SectionTitle(
                    label: _selectedContentType.isNovel
                        ? 'Top Novel'
                        : '🏆 Top Trending',
                  ),
                  SliverToBoxAdapter(child: _RankList(mangas: trending)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// Tiêu đề section (VD: "🔥 Truyện Hot Hôm Nay") — widget tái sử dụng cho nhiều section
class _SectionTitle extends StatelessWidget {
  final String label;
  const _SectionTitle({required this.label});

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
          ],
        ),
      ),
    );
  }
}

// Carousel cuộn ngang — dùng cho Hot Today và Mới Cập Nhật
// Bấm mỗi card → navigate '/detail/{id}'
class _MangaReaderCarousel extends StatelessWidget {
  final List<Manga> mangas;
  const _MangaReaderCarousel({required this.mangas});

  static const double _cardWidth = 130;
  static const double _coverHeight = 190;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: _coverHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: mangas.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final c = mangas[index];
            return GestureDetector(
              onTap: () => context.push('/detail/${c.id}'),
              child: SizedBox(
                width: _cardWidth,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DriveImage(
                        fileId: c.coverUrl,
                        fit: BoxFit.cover,
                        width: _cardWidth,
                        height: _coverHeight,
                      ),
                      // Gradient Overlay
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: 80,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87, Colors.black],
                            ),
                          ),
                        ),
                      ),
                      // Text
                      Positioned(
                        bottom: 12,
                        left: 8,
                        right: 8,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              c.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              c.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Follow Button (Frosted Glass)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                            child: Container(
                              color: Colors.white.withValues(alpha: 0.1),
                              child: _FollowButton(manga: c),
                            ),
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
    );
  }
}

class _FollowButton extends StatefulWidget {
  final Manga manga;
  const _FollowButton({required this.manga});

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  final FollowService _followService = FollowService();
  bool _isToggling = false;

  Future<void> _toggleFollow(bool isFollowing) async {
    if (_isToggling) return;
    setState(() => _isToggling = true);

    try {
      await _followService.toggleFollow(
        widget.manga.id,
        title: widget.manga.title,
        coverUrl: widget.manga.coverUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isFollowing ? 'Đã hủy theo dõi' : 'Đã theo dõi'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể cập nhật theo dõi: $e')),
      );
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _followService.isFollowing(widget.manga.id),
      initialData: false,
      builder: (context, snapshot) {
        final isFollowing = snapshot.data ?? false;
        return Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _isToggling ? null : () => _toggleFollow(isFollowing),
            child: SizedBox(
              width: 30,
              height: 30,
              child: Center(
                child: _isToggling
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        isFollowing ? Icons.favorite : Icons.favorite_border,
                        color: isFollowing ? Colors.redAccent : Colors.white,
                        size: 18,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Danh sách xếp hạng dọc — Top 3 có số khổng lồ chìm sau ảnh
class _RankList extends StatelessWidget {
  final List<Manga> mangas;
  const _RankList({required this.mangas});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(mangas.length, (i) {
        final c = mangas[i];
        
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: InkWell(
            onTap: () => context.push('/detail/${c.id}'),
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Center(
                    child: i == 0
                        ? const Text('🥇', style: TextStyle(fontSize: 28))
                        : i == 1
                            ? const Text('🥈', style: TextStyle(fontSize: 28))
                            : i == 2
                                ? const Text('🥉', style: TextStyle(fontSize: 28))
                                : Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.color
                                          ?.withValues(alpha: 0.5),
                                    ),
                                  ),
                  ),
                ),
                const SizedBox(width: 8),
                // Ảnh bìa
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: DriveImage(
                    fileId: c.coverUrl,
                    width: 60,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 16),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tác giả: ${c.author}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// Banner tự động trượt ngang mỗi 4 giây dùng PageController + Timer.periodic.
// Có chấm indicator ở dưới (AnimatedContainer để animate kích thước khi active).
class _AutoSlideBanner extends StatefulWidget {
  final List<Manga> mangas;
  const _AutoSlideBanner({required this.mangas});

  @override
  State<_AutoSlideBanner> createState() => _AutoSlideBannerState();
}

class _AutoSlideBannerState extends State<_AutoSlideBanner> {
  late final PageController _controller;
  int _currentPage = 0;
  Timer? _timer; // Nullable để tránh crash khi cancel trước khi init xong

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 1.0);
    _startTimer();
  }

  // Timer chạy vòng lặp: mỗi 4 giây chuyển sang trang kế, quay vòng khi đến cuối
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) return;
      if (widget.mangas.isEmpty) return;
      final nextPage = (_currentPage + 1) % widget.mangas.length;
      _controller.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
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
    if (widget.mangas.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 280,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.mangas.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              final c = widget.mangas[index];
              return GestureDetector(
                onTap: () => context.push('/detail/${c.id}'),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DriveImage(
                      fileId: c.coverUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                    // Gradient Overlay
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: 140,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black54,
                              Colors.black87,
                              Colors.black,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      bottom: 24,
                      right: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Frosted Glass Tag
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  c.contentType.label,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            c.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 8),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // Indicator chấm: active → rộng 12px, inactive → 6px (AnimatedContainer animate smooth)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.mangas.length, (i) {
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
