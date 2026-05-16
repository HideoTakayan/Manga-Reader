import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/models_cloud.dart';
import '../reader_provider.dart';

class ChapterListModalContent extends StatefulWidget {
  final List<CloudChapter> chapters;
  final CloudChapter? currentChapter;

  const ChapterListModalContent({
    super.key,
    required this.chapters,
    required this.currentChapter,
  });

  @override
  State<ChapterListModalContent> createState() =>
      _ChapterListModalContentState();
}

class _ChapterListModalContentState extends State<ChapterListModalContent> {
  final DraggableScrollableController _controller =
      DraggableScrollableController();
  late List<CloudChapter> _uniqueChapters;

  @override
  void initState() {
    super.initState();
    _computeUniqueChapters();
  }

  @override
  void didUpdateWidget(ChapterListModalContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.chapters != oldWidget.chapters) {
      _computeUniqueChapters();
    }
  }

  void _computeUniqueChapters() {
    final seen = <String>{};
    _uniqueChapters = widget.chapters.where((c) => seen.add(c.id)).toList();
  }

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
                  itemCount: _uniqueChapters.length,
                  itemBuilder: (context, index) {
                    final chapter = _uniqueChapters[index];
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
                            ? Colors.white.withValues(alpha: 0.05)
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
