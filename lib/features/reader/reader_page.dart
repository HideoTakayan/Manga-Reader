import 'package:flutter/material.dart';
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

class _ReaderPageState extends ConsumerState<ReaderPage> {
  late PageController _pageController;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _scrollController = ScrollController();

    // Load data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(readerProvider.notifier).init(widget.chapterId);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerProvider);
    final notifier = ref.read(readerProvider.notifier);

    // Sync logic (simplified)
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

  // Vertical View
  Widget _buildVerticalView(ReaderState state, ReaderNotifier notifier) {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      itemCount: state.pages.length,
      itemBuilder: (context, index) {
        return Image.memory(
          state.pages[index],
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
