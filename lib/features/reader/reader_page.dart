import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../../data/models_cloud.dart';
import '../../features/shared/drive_image.dart';
import 'reader_provider.dart';
import '../../services/notification_service.dart';

class ReaderPage extends ConsumerStatefulWidget {
  final String chapterId;
  const ReaderPage({super.key, required this.chapterId});

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late ScrollController _scrollController;

  // ========================================
  // HỆ THỐNG CHUYỂN CHƯƠNG KHI GIỮ (HOLD-TO-LOAD)
  // Ngăn chặn việc nhảy chương vô tình khi cuộn quá đà
  // ========================================

  // Trạng thái phát hiện hành động giữ
  bool _isInNextChapterZone = false;
  bool _isInPrevChapterZone = false;
  bool _isHoldingForNextChapter = false;
  bool _isHoldingForPrevChapter = false;

  // Bộ đếm thời gian cho hành động giữ
  Timer? _holdTimer;
  static const Duration _holdDuration = Duration(milliseconds: 1500);

  // Controller cho animation progress ring
  late AnimationController _holdProgressController;

  // Thời gian chờ để tránh chuyển chương liên tục (Cooldown)
  DateTime? _lastChapterChange;
  static const Duration _chapterChangeCooldown = Duration(seconds: 2);
  bool _isChapterTransitionLocked = false;

  // Ngưỡng phát hiện vùng chuyển chương (pixel)
  static const double _nextChapterThreshold = 100.0; // Khoảng cách từ đáy
  static const double _prevChapterThreshold =
      -60.0; // Khoảng cách overscroll ở đỉnh

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _scrollController = ScrollController();

    // Animation controller cho vòng tròn tiến trình
    _holdProgressController = AnimationController(
      vsync: this,
      duration: _holdDuration,
    );

    // Lắng nghe sự kiện cuộn để phát hiện vùng chuyển chương
    _scrollController.addListener(_onVerticalScroll);

    // Load data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(readerProvider.notifier).init(widget.chapterId);
    });
  }

  void _onVerticalScroll() {
    final state = ref.read(readerProvider);

    // Only handle in vertical mode
    if (state.readingMode != ReadingMode.vertical) return;
    if (!_scrollController.hasClients) return;

    final pixels = _scrollController.position.pixels;
    final maxExtent = _scrollController.position.maxScrollExtent;

    // Kiểm tra vùng chuyển chương tiếp theo (gần đáy)
    final isNearEnd = pixels >= maxExtent - _nextChapterThreshold;

    // Kiểm tra vùng chuyển chương trước (overscroll ở đỉnh)
    final isOverscrollTop = pixels < _prevChapterThreshold;

    // Xử lý logic vùng chương tiếp theo
    if (isNearEnd && !_isInNextChapterZone) {
      _enterNextChapterZone();
    } else if (!isNearEnd && _isInNextChapterZone) {
      _exitNextChapterZone();
    }

    // Xử lý logic vùng chương trước
    if (isOverscrollTop && !_isInPrevChapterZone) {
      _enterPrevChapterZone();
    } else if (!isOverscrollTop && _isInPrevChapterZone) {
      _exitPrevChapterZone();
    }
  }

  void _enterNextChapterZone() {
    final notifier = ref.read(readerProvider.notifier);
    if (notifier.getNextChapterId() == null) return;
    if (_isChapterTransitionLocked) return;

    setState(() {
      _isInNextChapterZone = true;
      _isHoldingForNextChapter = true;
    });

    // Start hold timer
    _holdProgressController.forward(from: 0);
    _holdTimer = Timer(_holdDuration, () {
      _triggerNextChapter();
    });
  }

  void _exitNextChapterZone() {
    setState(() {
      _isInNextChapterZone = false;
      _isHoldingForNextChapter = false;
    });
    _cancelHoldTimer();
  }

  void _enterPrevChapterZone() {
    final notifier = ref.read(readerProvider.notifier);
    if (notifier.getPrevChapterId() == null) return;
    if (_isChapterTransitionLocked) return;

    setState(() {
      _isInPrevChapterZone = true;
      _isHoldingForPrevChapter = true;
    });

    // Start hold timer
    _holdProgressController.forward(from: 0);
    _holdTimer = Timer(_holdDuration, () {
      _triggerPrevChapter();
    });
  }

  void _exitPrevChapterZone() {
    setState(() {
      _isInPrevChapterZone = false;
      _isHoldingForPrevChapter = false;
    });
    _cancelHoldTimer();
  }

  void _cancelHoldTimer() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdProgressController.stop();
    _holdProgressController.reset();
  }

  void _triggerNextChapter() {
    if (_isChapterTransitionLocked) return;

    // Check cooldown
    if (_lastChapterChange != null &&
        DateTime.now().difference(_lastChapterChange!) <
            _chapterChangeCooldown) {
      return;
    }

    setState(() {
      _isChapterTransitionLocked = true;
      _isHoldingForNextChapter = false;
    });

    _lastChapterChange = DateTime.now();

    // Haptic feedback
    HapticFeedback.mediumImpact();

    // Load chapter
    ref.read(readerProvider.notifier).loadNextChapter().then((_) {
      if (mounted) {
        setState(() {
          _isChapterTransitionLocked = false;
          _isInNextChapterZone = false;
        });
        _cancelHoldTimer();

        // Scroll to top of new chapter
        _scrollController.jumpTo(0);
      }
    });
  }

  void _triggerPrevChapter() {
    if (_isChapterTransitionLocked) return;

    // Check cooldown
    if (_lastChapterChange != null &&
        DateTime.now().difference(_lastChapterChange!) <
            _chapterChangeCooldown) {
      return;
    }

    setState(() {
      _isChapterTransitionLocked = true;
      _isHoldingForPrevChapter = false;
    });

    _lastChapterChange = DateTime.now();

    // Haptic feedback
    HapticFeedback.mediumImpact();

    // Load chapter
    ref.read(readerProvider.notifier).loadPrevChapter().then((_) {
      if (mounted) {
        setState(() {
          _isChapterTransitionLocked = false;
          _isInPrevChapterZone = false;
        });
        _cancelHoldTimer();

        // Tối ưu: Khi về chương trước, nhảy xuống cuối trang để đọc ngược lên mượt hơn
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent - 200,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onVerticalScroll);
    _cancelHoldTimer();
    _holdProgressController.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerProvider);
    final notifier = ref.read(readerProvider.notifier);

    // Logic đồng bộ vị trí trang khi thay đổi state (Giản lược)
    ref.listen<ReaderState>(readerProvider, (prev, next) {
      if (prev?.currentPageIndex != next.currentPageIndex &&
          next.readingMode == ReadingMode.horizontal) {
        if (_pageController.hasClients &&
            _pageController.page?.round() != next.currentPageIndex) {
          _pageController.jumpToPage(next.currentPageIndex);
        }
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      drawer: _buildDrawer(state, notifier),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Content
                GestureDetector(
                  onTap: notifier.toggleControls,
                  child: state.readingMode == ReadingMode.horizontal
                      ? _buildHorizontalView(state, notifier)
                      : _buildVerticalView(state, notifier),
                ),

                // TOP OVERLAY
                if (state.showControls)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                        10,
                        MediaQuery.of(context).padding.top + 5,
                        10,
                        10,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.9),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Back Button
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                              size: 24,
                            ),
                            onPressed: () => context.pop(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 10),

                          // Cover Image
                          if (state.comic != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: DriveImage(
                                fileId: state.comic!.coverFileId,
                                width: 40,
                                height: 60,
                                fit: BoxFit.cover,
                              ),
                            ),
                          const SizedBox(width: 10),

                          // Info & Chapter Selector
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  state.comic?.title ?? 'Đang tải...',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (state.comic?.author != null)
                                  Text(
                                    state.comic!.author,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                const SizedBox(height: 4),

                                // Chapter Selector Button
                                InkWell(
                                  onTap: () => _showChapterListModal(
                                    context,
                                    state.chapters,
                                    state.currentChapter,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.list,
                                          color: Colors.white70,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          state.currentChapter?.title ??
                                              'Chương ?',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.keyboard_arrow_down,
                                          color: Colors.white70,
                                          size: 14,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Menu Button (Drawer)
                          Builder(
                            builder: (context) => IconButton(
                              icon: const Icon(
                                Icons.menu,
                                color: Colors.white,
                                size: 24,
                              ),
                              onPressed: () =>
                                  Scaffold.of(context).openDrawer(),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // BOTTOM OVERLAY
                if (state.showControls)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 30,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.9),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios,
                              color: Colors.white,
                            ),
                            onPressed: notifier.getPrevChapterId() != null
                                ? () => context.pushReplacement(
                                    '/reader/${notifier.getPrevChapterId()}',
                                  )
                                : null,
                          ),
                          IconButton(
                            icon: Icon(
                              state.isFollowed
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: state.isFollowed
                                  ? Colors.red
                                  : Colors.white,
                            ),
                            onPressed: () async {
                              if (state.isFollowed) {
                                // Ask to unfollow
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    title: const Text(
                                      'Hủy Theo Dõi?',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    content: const Text(
                                      'Bạn có chắc chắn muốn hủy theo dõi truyện này?',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text(
                                          'Hủy',
                                          style: TextStyle(
                                            color: Colors.white54,
                                          ),
                                        ),
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
                                  await notifier.toggleFollow();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Đã hủy theo dõi'),
                                      ),
                                    );
                                  }
                                }
                              } else {
                                // Just follow
                                await notifier.toggleFollow();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã theo dõi thành công!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                          // Notification Count
                          StreamBuilder<int>(
                            stream: NotificationService.instance
                                .streamComicNotificationCount(
                                  state.comic?.id ?? '',
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
                                  const SizedBox(width: 2),
                                  Text(
                                    _formatCount(count),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.white,
                            ),
                            onPressed: notifier.getNextChapterId() != null
                                ? () => context.pushReplacement(
                                    '/reader/${notifier.getNextChapterId()}',
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  // Horizontal View
  Widget _buildHorizontalView(ReaderState state, ReaderNotifier notifier) {
    return PhotoViewGallery.builder(
      scrollPhysics: const BouncingScrollPhysics(),
      builder: (context, index) {
        return PhotoViewGalleryPageOptions(
          imageProvider: MemoryImage(state.pages[index]),
          initialScale: PhotoViewComputedScale.contained,
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 2,
        );
      },
      itemCount: state.pages.length,
      pageController: _pageController,
      onPageChanged: notifier.onPageChanged,
      loadingBuilder: (context, event) =>
          const Center(child: CircularProgressIndicator()),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
    );
  }

  // Giao diện dọc với tính năng cuộn liên tục (Continuous Scrolling)
  Widget _buildVerticalView(ReaderState state, ReaderNotifier notifier) {
    // Tổng item = 1 header + danh sách trang ảnh + 1 footer
    final itemCount = state.pages.length + 2;

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      physics:
          const BouncingScrollPhysics(), // Cho phép overscroll để kích hoạt chuyển chương trước
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Item đầu tiên: Header chuyển chương trước
        if (index == 0) {
          return _buildChapterTransitionHeader(state, notifier);
        }

        // Item cuối cùng: Footer chuyển chương sau
        if (index == itemCount - 1) {
          return _buildChapterTransitionFooter(state, notifier);
        }

        // Trang ảnh bình thường (index trừ 1 do có header)
        final pageIndex = index - 1;
        return Image.memory(
          state.pages[pageIndex],
          fit: BoxFit.fitWidth,
          width: double.infinity,
          errorBuilder: (_, __, ___) => const SizedBox(
            height: 200,
            child: Icon(Icons.broken_image, color: Colors.white),
          ),
        );
      },
    );
  }

  // Header chuyển chương (cho chương trước) với vòng tròn giữ để tải
  Widget _buildChapterTransitionHeader(
    ReaderState state,
    ReaderNotifier notifier,
  ) {
    final hasPrevChapter = notifier.getPrevChapterId() != null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 40),

          // Loading, holding, or previous chapter indicator
          if (state.isLoadingPrevChapter)
            const Column(
              children: [
                CircularProgressIndicator(strokeWidth: 2),
                SizedBox(height: 12),
                Text(
                  'Đang tải chương trước...',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            )
          else if (_isHoldingForPrevChapter && hasPrevChapter)
            // Hiển thị vòng tròn tiến trình khi đang giữ
            Column(
              children: [
                const SizedBox(height: 20),
                SizedBox(
                  width: 60,
                  height: 60,
                  child: AnimatedBuilder(
                    animation: _holdProgressController,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Vòng tròn nền
                          CircularProgressIndicator(
                            value: 1.0,
                            strokeWidth: 4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withOpacity(0.1),
                            ),
                          ),
                          // Vòng tròn tiến trình
                          CircularProgressIndicator(
                            value: _holdProgressController.value,
                            strokeWidth: 4,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.blueAccent,
                            ),
                          ),
                          // Icon mũi tên lên
                          Icon(
                            Icons.arrow_upward,
                            color: Colors.blueAccent.withOpacity(
                              0.5 + (_holdProgressController.value * 0.5),
                            ),
                            size: 24,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Giữ để đọc chương trước...',
                  style: TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )
          else if (hasPrevChapter)
            Column(
              children: [
                const Icon(
                  Icons.keyboard_double_arrow_up,
                  color: Colors.white54,
                  size: 28,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cuộn thêm để đọc chương trước',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                // Nút thủ công
                OutlinedButton.icon(
                  onPressed: () => notifier.loadPrevChapter(),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Chương trước'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                const Icon(
                  Icons.first_page,
                  color: Colors.blueAccent,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  'Đây là chương đầu tiên',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 20),

          // Divider mờ dần
          Container(
            height: 2,
            width: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.white.withOpacity(0.2),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Footer chuyển chương (cho chương sau) với vòng tròn giữ để tải
  Widget _buildChapterTransitionFooter(
    ReaderState state,
    ReaderNotifier notifier,
  ) {
    final hasNextChapter = notifier.getNextChapterId() != null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Divider
          Container(
            height: 2,
            width: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.white.withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Chapter end text
          Text(
            'Hết ${state.currentChapter?.title ?? 'chương'}',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),

          // Loading, holding, or next chapter indicator
          if (state.isLoadingNextChapter)
            const Column(
              children: [
                CircularProgressIndicator(strokeWidth: 2),
                SizedBox(height: 12),
                Text(
                  'Đang tải chương tiếp theo...',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            )
          else if (_isHoldingForNextChapter && hasNextChapter)
            // Show hold progress indicator
            Column(
              children: [
                SizedBox(
                  width: 60,
                  height: 60,
                  child: AnimatedBuilder(
                    animation: _holdProgressController,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Background circle
                          CircularProgressIndicator(
                            value: 1.0,
                            strokeWidth: 4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withOpacity(0.2),
                            ),
                          ),
                          // Progress circle
                          CircularProgressIndicator(
                            value: _holdProgressController.value,
                            strokeWidth: 4,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.blueAccent,
                            ),
                          ),
                          // Icon in center
                          Icon(
                            Icons.arrow_downward,
                            color: Colors.blueAccent.withOpacity(
                              0.5 + (_holdProgressController.value * 0.5),
                            ),
                            size: 24,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Giữ để đọc chương tiếp...',
                  style: TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )
          else if (hasNextChapter)
            Column(
              children: [
                const Icon(
                  Icons.keyboard_double_arrow_down,
                  color: Colors.white54,
                  size: 28,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cuộn xuống và giữ để đọc chương tiếp',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                // Manual button as fallback
                OutlinedButton.icon(
                  onPressed: _isChapterTransitionLocked
                      ? null
                      : () => _triggerNextChapter(),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('Chương tiếp'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.green,
                  size: 32,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Bạn đã đọc hết truyện!',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Quay lại'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // Chapter List Modal
  void _showChapterListModal(
    BuildContext context,
    List<CloudChapter> chapters,
    CloudChapter? currentChapter,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor:
          Colors.transparent, // Transparent to let DraggableSheet handle bg
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return _ChapterListModalContent(
          chapters: chapters,
          currentChapter: currentChapter,
        );
      },
    );
  }

  // Drawer (Menu)
  Widget _buildDrawer(ReaderState state, ReaderNotifier notifier) {
    return Drawer(
      backgroundColor: const Color(0xFF1E1E1E),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.black),
            child: Center(
              child: Text(
                'Cài đặt & Tùy chọn',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.refresh, color: Colors.white),
            title: const Text('Tải lại', style: TextStyle(color: Colors.white)),
            onTap: () => notifier.init(widget.chapterId),
          ),
          ListTile(
            leading: Icon(
              state.readingMode == ReadingMode.horizontal
                  ? Icons.view_day
                  : Icons.view_array,
              color: Colors.white,
            ),
            title: Text(
              state.readingMode == ReadingMode.horizontal
                  ? 'Chuyển sang đọc dọc'
                  : 'Chuyển sang đọc ngang',
              style: const TextStyle(color: Colors.white),
            ),
            onTap: () {
              notifier.setReadingMode(
                state.readingMode == ReadingMode.horizontal
                    ? ReadingMode.vertical
                    : ReadingMode.horizontal,
              );
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.white),
            title: const Text(
              'Xóa lịch sử đọc',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              // TODO: Clear history
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

class _ChapterListModalContent extends StatefulWidget {
  final List<CloudChapter> chapters;
  final CloudChapter? currentChapter;

  const _ChapterListModalContent({
    required this.chapters,
    required this.currentChapter,
  });

  @override
  State<_ChapterListModalContent> createState() =>
      _ChapterListModalContentState();
}

class _ChapterListModalContentState extends State<_ChapterListModalContent> {
  final DraggableScrollableController _controller =
      DraggableScrollableController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleSize() {
    if (_controller.size > 0.6) {
      _controller.animateTo(
        0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _controller.animateTo(
        1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: 0.5,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      expand: false,
      snap: true,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1C1C1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.white12, width: 1),
                  ),
                ),
                child: Consumer(
                  builder: (context, ref, child) {
                    final state = ref.watch(readerProvider);
                    final notifier = ref.read(readerProvider.notifier);

                    return Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Expanded(
                          child: Text(
                            'DS Chương',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        // Follow Icon (Heart)
                        IconButton(
                          icon: Icon(
                            state.isFollowed
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: state.isFollowed ? Colors.red : Colors.white,
                          ),
                          onPressed: () async {
                            await notifier.toggleFollow();
                          },
                        ),
                        // Notification Count
                        StreamBuilder<int>(
                          stream: NotificationService.instance
                              .streamComicNotificationCount(
                                state.comic?.id ?? '',
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
                                const SizedBox(width: 2),
                                Text(
                                  _formatCount(count),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        // Resize Icon
                        IconButton(
                          icon: const Icon(
                            Icons.swap_vert,
                            color: Colors.white,
                          ),
                          onPressed: _toggleSize,
                        ),
                      ],
                    );
                  },
                ),
              ),

              // List
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: widget.chapters.length,
                  itemBuilder: (context, index) {
                    final chapter = widget.chapters[index];
                    final isSelected = chapter.id == widget.currentChapter?.id;

                    // Format date: dd/MM/yyyy
                    final date =
                        "${chapter.uploadedAt.day}/${chapter.uploadedAt.month}/${chapter.uploadedAt.year}";

                    return InkWell(
                      onTap: () {
                        Navigator.pop(context); // Close modal
                        if (!isSelected) {
                          // Navigate to selected chapter
                          context.pushReplacement('/reader/${chapter.id}');
                        }
                      },
                      child: Container(
                        color: isSelected
                            ? Colors.white.withOpacity(0.05)
                            : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                chapter.title,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.blueAccent
                                      : Colors.white70,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            Text(
                              date,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
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
          ),
        );
      },
    );
  }
}

String _formatCount(int count) {
  if (count < 1000) return count.toString();
  if (count < 1000000) return '${(count / 1000).toStringAsFixed(1)}k';
  return '${(count / 1000000).toStringAsFixed(1)}m';
}
