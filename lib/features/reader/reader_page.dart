import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
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

  // Lắng nghe thay đổi state để update controller nếu cần (ví dụ nhảy trang)
  void _listenToStateChanges() {
    ref.listen<ReaderState>(readerProvider, (
      ReaderState? previous,
      ReaderState next,
    ) {
      if (previous?.currentPageIndex != next.currentPageIndex) {
        if (next.readingMode == ReadingMode.horizontal) {
          if (_pageController.hasClients &&
              _pageController.page?.round() != next.currentPageIndex) {
            _pageController.jumpToPage(next.currentPageIndex);
          }
        } else {
          // Với ListView, bỏ qua sync
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerProvider);
    final notifier = ref.read(readerProvider.notifier);

    _listenToStateChanges();

    if (state.errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, elevation: 0),
        body: Center(
          child: Text(
            state.errorMessage!,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
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

                // AppBar
                if (state.showControls)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: AppBar(
                      backgroundColor: Colors.black.withOpacity(0.8),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.currentChapter?.title ?? '',
                            style: const TextStyle(fontSize: 16),
                          ),
                          if (state.pages.isNotEmpty)
                            Text(
                              '${state.currentPageIndex + 1} / ${state.pages.length}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
                      actions: [
                        IconButton(
                          icon: Icon(
                            state.readingMode == ReadingMode.horizontal
                                ? Icons.view_day
                                : Icons.view_array,
                          ),
                          tooltip: 'Chế độ đọc',
                          onPressed: () {
                            notifier.setReadingMode(
                              state.readingMode == ReadingMode.horizontal
                                  ? ReadingMode.vertical
                                  : ReadingMode.horizontal,
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                // Bottom Bar
                if (state.showControls)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildBottomBar(context, notifier),
                  ),
              ],
            ),
    );
  }

  Widget _buildHorizontalView(ReaderState state, ReaderNotifier notifier) {
    return PhotoViewGallery.builder(
      scrollPhysics: const BouncingScrollPhysics(),
      builder: (BuildContext context, int index) {
        return PhotoViewGalleryPageOptions(
          imageProvider: MemoryImage(state.pages[index]),
          initialScale: PhotoViewComputedScale.contained,
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 2,
        );
      },
      itemCount: state.pages.length,
      loadingBuilder: (context, event) =>
          const Center(child: CircularProgressIndicator()),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      pageController: _pageController,
      onPageChanged: notifier.onPageChanged,
    );
  }

  Widget _buildVerticalView(ReaderState state, ReaderNotifier notifier) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: state.pages.length,
      itemBuilder: (context, index) {
        return Image.memory(
          state.pages[index],
          fit: BoxFit.fitWidth,
          width: double.infinity,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.broken_image, size: 50, color: Colors.grey),
        );
      },
    );
  }

  Widget _buildBottomBar(BuildContext context, ReaderNotifier notifier) {
    final nextId = notifier.getNextChapterId();
    final prevId = notifier.getPrevChapterId();

    return Container(
      color: Colors.black.withOpacity(0.8),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: prevId != null
                ? () {
                    context.pushReplacement('/reader/$prevId');
                  }
                : null,
            icon: const Icon(Icons.skip_previous, color: Colors.white),
            label: const Text('Trước', style: TextStyle(color: Colors.white)),
          ),

          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.grid_view, color: Colors.white),
          ),

          TextButton.icon(
            onPressed: nextId != null
                ? () {
                    context.pushReplacement('/reader/$nextId');
                  }
                : null,
            label: const Text('Sau', style: TextStyle(color: Colors.white)),
            icon: const Icon(Icons.skip_next, color: Colors.white),
            // Đảo icon cho đúng logic đọc
            iconAlignment: IconAlignment.end,
          ),
        ],
      ),
    );
  }
}
