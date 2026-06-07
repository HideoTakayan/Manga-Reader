import 'dart:io';
import 'dart:typed_data';
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
  late Future<Uint8List> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = File(widget.novel.path).readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
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

        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.amber),
                  SizedBox(height: 16),
                  Text(
                    'Đang đọc file EPUB...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          );
        }

        return NovelReaderWidget(
          title: widget.novel.title,
          epubBytes: snapshot.data!,
          storageKey: widget.novel.path,
          realMangaId: 'LOCAL_NOVEL|${widget.novel.path}',
          realChapterId: 'LOCAL_NOVEL|${widget.novel.path}',
        );
      },
    );
  }
}
