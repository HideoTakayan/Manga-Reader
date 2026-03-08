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

class ReaderPage extends ConsumerStatefulWidget {
  final String chapterId;
  const ReaderPage({super.key, required this.chapterId});

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

// SingleTickerProviderStateMixin: cung cấp vsync cho AnimationController
// → tiết kiệm tài nguyên, chỉ dùng khi có đúng 1 AnimationController
class _ReaderPageState extends ConsumerState<ReaderPage>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late ScrollController _scrollController;

  // ==== HỆ THỐNG HOLD-TO-LOAD (chuyển chương bằng cách giữ ở vùng biên) ====
  // Tránh chuyển chương vô tình khi cuộn quá đà — phải giữ 1.5 giây mới chuyển

  bool _isInNextChapterZone = false; // Đang trong vùng dưới (gần hết chương)
  bool _isInPrevChapterZone = false; // Đang trong vùng trên (overscroll ngược)
  bool _isHoldingForNextChapter = false; // Đang đếm ngược để sang chương sau
  bool _isHoldingForPrevChapter = false; // Đang đếm ngược để về chương trước

  Timer? _holdTimer;
  static const Duration _holdDuration = Duration(milliseconds: 1500);

  late AnimationController _holdProgressController;

  DateTime? _lastChapterChange;
  static const Duration _chapterChangeCooldown = Duration(seconds: 2);
  bool _isChapterTransitionLocked =
      false; 

  static const double _nextChapterThreshold =
      100.0; 
  static const double _prevChapterThreshold =
      -60.0; 

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _scrollController = ScrollController();

    _holdProgressController = AnimationController(
      vsync: this,
      duration: _holdDuration,
    );

    _scrollController.addListener(_onVerticalScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(readerProvider.notifier).init(widget.chapterId);
    });
  }

  void _onVerticalScroll() {
    final state = ref.read(readerProvider);

    if (state.readingMode != ReadingMode.vertical) return;
    if (!_scrollController.hasClients) return;

    final pixels = _scrollController.position.pixels;
    final maxExtent = _scrollController.position.maxScrollExtent;

    final isNearEnd = pixels >= maxExtent - _nextChapterThreshold;

    final isOverscrollTop = pixels < _prevChapterThreshold;

    if (isNearEnd && !_isInNextChapterZone) {
      _enterNextChapterZone();
    } else if (!isNearEnd && _isInNextChapterZone) {
      _exitNextChapterZone();
    }
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
    if (_lastChapterChange != null &&
        DateTime.now().difference(_lastChapterChange!) < _chapterChangeCooldown)
      return;

    setState(() {
      _isChapterTransitionLocked = true;
      _isHoldingForNextChapter = false;
    });
    _lastChapterChange = DateTime.now();
    HapticFeedback.mediumImpact(); 

    ref.read(readerProvider.notifier).loadNextChapter().then((_) {
      if (mounted) {
        setState(() {
          _isChapterTransitionLocked = false;
          _isInNextChapterZone = false;
        });
        _cancelHoldTimer();
        _scrollController.jumpTo(0);
      }
    });
  }

  void _triggerPrevChapter() {
    if (_isChapterTransitionLocked) return;

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

    HapticFeedback.mediumImpact();

    ref.read(readerProvider.notifier).loadPrevChapter().then((_) {
      if (mounted) {
        setState(() {
          _isChapterTransitionLocked = false;
          _isInPrevChapterZone = false;
        });
        _cancelHoldTimer();
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
                // Nội dung
                GestureDetector(
                  onTap: notifier.toggleControls,
                  child: state.readingMode == ReadingMode.horizontal
                      ? _buildHorizontalView(state, notifier)
                      : _buildVerticalView(state, notifier),
                ),

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
                          // Nút quay lại
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

                          // Ảnh bìa
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

                          // Thông tin & Chọn chương
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

                                // Nút chọn chương
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

                          // Nút Menu (Ngăn kéo)
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

                // LỚP PHỦ DƯỚI CÙNG
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
                                // Hỏi để hủy theo dõi
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
                                // Chỉ theo dõi
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

  // Chế độ đọc NGANG: PhotoViewGallery — swipe trái/phải giữa các trang
  // MemoryImage(Uint8List): ảnh đã decode (unzip .cbz) sẵn trong provider
  // PhotoViewComputedScale.contained: hiện đủ cả trang trong màn hình
  // maxScale: covered * 2 → zoom tối đa 2x
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
      onPageChanged:
          notifier.onPageChanged, // Cập nhật currentPageIndex trong provider
      loadingBuilder: (context, event) =>
          const Center(child: CircularProgressIndicator()),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
    );
  }

  // Chế độ đọc DỌC: ListView cuộn liên tục
  // Cấu trúc item: [header] [trang 0] [trang 1] ... [trang N] [footer]
  // BouncingScrollPhysics: cho phép overscroll ở đầu → kích hoạt prev chapter zone
  Widget _buildVerticalView(ReaderState state, ReaderNotifier notifier) {
    final itemCount = state.pages.length + 2; // +2 = header + footer

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      physics: const BouncingScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == 0) return _buildChapterTransitionHeader(state, notifier);
        if (index == itemCount - 1)
          return _buildChapterTransitionFooter(state, notifier);
        // pageIndex = index - 1 vì index 0 là header
        final pageIndex = index - 1;
        return Image.memory(
          state.pages[pageIndex],
          fit: BoxFit.fitWidth, // Vừa khít chiều rộng, chiều cao tự scale
          width: double.infinity,
          errorBuilder: (_, __, ___) => const SizedBox(
            height: 200,
            child: Icon(Icons.broken_image, color: Colors.white),
          ),
        );
      },
    );
  }

  // Tiêu đề chuyển chương (cho chương trước) với vòng tròn giữ để tải
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

          // Đang tải, đang giữ, hoặc chỉ báo chương trước
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
                          // Biểu tượng mũi tên lên
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
                // Nút nhấn thủ công
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

          // Đường chia mờ dần
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

  // Chân trang chuyển chương (cho chương sau) với vòng tròn giữ để tải
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

          // Văn bản kết thúc chương
          Text(
            'Hết ${state.currentChapter?.title ?? 'chương'}',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),

          // Đang tải, đang giữ, hoặc chỉ báo chương tiếp theo
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
            // Hiển thị chỉ báo tiến trình giữ
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
                          // Vòng tròn nền
                          CircularProgressIndicator(
                            value: 1.0,
                            strokeWidth: 4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withOpacity(0.2),
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
                          // Biểu tượng ở giữa
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
                // Nút thủ công để dự phòng
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

  // Cửa sổ danh sách chương
  void _showChapterListModal(
    BuildContext context,
    List<CloudChapter> chapters,
    CloudChapter? currentChapter,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor:
          Colors.transparent, // Trong suốt để DraggableSheet xử lý nền
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

  // Ngăn kéo (Menu)
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
              // TODO: Xóa lịch sử
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
              // Tiêu đề
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
                        // Biểu tượng theo dõi (Trái tim)
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

                        // Biểu tượng đổi kích thước
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

              // Danh sách
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  // Dedup bằng Set.add() — trả về false nếu id đã tồn tại
                  // Đây là biện pháp phòng ngừa nếu server trả về chapter trùng id
                  itemCount: () {
                    final seen = <String>{};
                    return widget.chapters.where((c) => seen.add(c.id)).length;
                  }(),
                  itemBuilder: (context, index) {
                    // Recompute uniqueChapters mỗi lần — kém hiệu quả nhưng đảm bảo đúng 100%
                    // Tối ưu hơn: tính 1 lần ở initState/build, truyền vào widget
                    final seen = <String>{};
                    final uniqueChapters = widget.chapters
                        .where((c) => seen.add(c.id))
                        .toList();

                    if (index >= uniqueChapters.length) return const SizedBox();

                    final chapter = uniqueChapters[index];
                    final isSelected = chapter.id == widget.currentChapter?.id;

                    // Định dạng ngày: dd/MM/yyyy
                    final date =
                        "${chapter.uploadedAt.day}/${chapter.uploadedAt.month}/${chapter.uploadedAt.year}";

                    return InkWell(
                      onTap: () {
                        Navigator.pop(context); // Đóng cửa sổ
                        if (!isSelected) {
                          // Điều hướng đến chương đã chọn
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
