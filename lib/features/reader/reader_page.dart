import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../data/mock_catalog.dart';
import '../../data/models.dart';
import 'package:go_router/go_router.dart';

class ReaderPage extends StatefulWidget {
  final String chapterId;
  const ReaderPage({super.key, required this.chapterId});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late List<PageImage> pages;
  late ScrollController _scrollController;
  late Chapter currentChapter;
  late List<Chapter> allChapters;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _initData();

    // Theo dõi cuộn — nếu cuộn hết sẽ tự động chuyển chương sau
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _goToNextChapter();
      } else if (_scrollController.position.pixels <= 0) {
        _goToPreviousChapter();
      }
    });
  }

  void _initData() {
    allChapters = MockCatalog.chaptersOf(widget.chapterId.split('-').first);
    currentChapter = allChapters.firstWhere((c) => c.id == widget.chapterId,
        orElse: () => allChapters.first);
    pages = MockCatalog.pagesOf(widget.chapterId);
  }

  void _goToNextChapter() {
    final currentIndex = allChapters.indexOf(currentChapter);
    if (currentIndex < allChapters.length - 1) {
      final nextChapter = allChapters[currentIndex + 1];
      context.pushReplacement('/reader/${nextChapter.id}');
    }
  }

  void _goToPreviousChapter() {
    final currentIndex = allChapters.indexOf(currentChapter);
    if (currentIndex > 0) {
      final prevChapter = allChapters[currentIndex - 1];
      context.pushReplacement('/reader/${prevChapter.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          currentChapter.name,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () {
              context.pop(); // quay lại danh sách chương
            },
          ),
        ],
      ),
      body: pages.isEmpty
          ? const Center(
              child: Text(
                'Chưa có trang nào trong chương này.',
                style: TextStyle(color: Colors.white),
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              itemCount: pages.length,
              itemBuilder: (context, index) {
                final page = pages[index];
                return CachedNetworkImage(
                  imageUrl: page.imageUrl,
                  fit: BoxFit.fitWidth,
                  width: double.infinity,
                  placeholder: (context, url) => const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  errorWidget: (context, url, error) => const Icon(
                    Icons.broken_image,
                    color: Colors.white30,
                    size: 100,
                  ),
                );
              },
            ),
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final currentIndex = allChapters.indexOf(currentChapter);
    final hasPrev = currentIndex > 0;
    final hasNext = currentIndex < allChapters.length - 1;

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (hasPrev)
            TextButton.icon(
              onPressed: _goToPreviousChapter,
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              label: const Text('Chương trước',
                  style: TextStyle(color: Colors.white)),
            )
          else
            const SizedBox(width: 120),
          TextButton.icon(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.menu_book, color: Colors.amber),
            label:
                const Text('Danh sách', style: TextStyle(color: Colors.amber)),
          ),
          if (hasNext)
            TextButton.icon(
              onPressed: _goToNextChapter,
              icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
              label: const Text('Chương sau',
                  style: TextStyle(color: Colors.white)),
            )
          else
            const SizedBox(width: 120),
        ],
      ),
    );
  }
}
