import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/novel_service.dart';
import 'novel_reader_widget.dart';

class LocalNovelReaderPage extends StatelessWidget {
  final LocalNovel novel;
  const LocalNovelReaderPage({super.key, required this.novel});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: File(novel.path).readAsBytes(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              title: Text(novel.title, overflow: TextOverflow.ellipsis),
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
            body: Center(child: CircularProgressIndicator(color: Colors.amber)),
          );
        }

        return NovelReaderWidget(
          title: novel.title,
          epubBytes: snapshot.data!,
          storageKey: novel.path,
        );
      },
    );
  }
}
