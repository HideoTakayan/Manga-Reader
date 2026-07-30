import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/novel_service.dart';
import 'novel_reader_widget.dart';

class LocalNovelReaderPage extends StatefulWidget {
  final LocalNovel novel;
  const LocalNovelReaderPage({super.key, required this.novel});

  @override
  State<LocalNovelReaderPage> createState() => _LocalNovelReaderPageState();
}

class _LocalNovelReaderPageState extends State<LocalNovelReaderPage> {
  @override
  Widget build(BuildContext context) {
    if (!File(widget.novel.path).existsSync()) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(
            widget.novel.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Không mở được file EPUB này. File có thể đã bị xóa, đổi chỗ hoặc hỏng.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    return NovelReaderWidget(
      title: widget.novel.title,
      epubPath: widget.novel.path,
      storageKey: widget.novel.path,
      realMangaId: 'LOCAL_NOVEL|${widget.novel.path}',
      realChapterId: 'LOCAL_NOVEL|${widget.novel.path}',
    );
  }
}
