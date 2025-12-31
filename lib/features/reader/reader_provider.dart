import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:archive/archive.dart';
import 'package:collection/collection.dart';

import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';

enum ReadingMode { vertical, horizontal }

class ReaderState {
  final bool isLoading;
  final ReadingMode readingMode;
  final List<CloudChapter> chapters;
  final CloudChapter? currentChapter;
  final List<Uint8List> pages; // Changed to Uint8List for memory images
  final int currentPageIndex;
  final bool showControls;
  final String? errorMessage;

  const ReaderState({
    this.isLoading = true,
    this.readingMode = ReadingMode.vertical,
    this.chapters = const [],
    this.currentChapter,
    this.pages = const [],
    this.currentPageIndex = 0,
    this.showControls = true,
    this.errorMessage,
  });

  ReaderState copyWith({
    bool? isLoading,
    ReadingMode? readingMode,
    List<CloudChapter>? chapters,
    CloudChapter? currentChapter,
    List<Uint8List>? pages,
    int? currentPageIndex,
    bool? showControls,
    String? errorMessage,
  }) {
    return ReaderState(
      isLoading: isLoading ?? this.isLoading,
      readingMode: readingMode ?? this.readingMode,
      chapters: chapters ?? this.chapters,
      currentChapter: currentChapter ?? this.currentChapter,
      pages: pages ?? this.pages,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      showControls: showControls ?? this.showControls,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class ReaderNotifier extends StateNotifier<ReaderState> {
  ReaderNotifier() : super(const ReaderState());

  Future<void> init(String chapterId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      // 1. Get Chapter File Metadata to find Comic ID (Parent)
      final fileMeta = await DriveService.instance.getFile(chapterId);
      if (fileMeta == null ||
          fileMeta.parents == null ||
          fileMeta.parents!.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Không tìm thấy thông tin chương truyện',
        );
        return;
      }

      final comicId = fileMeta.parents!.first;

      // 2. Get All Chapters (for navigation)
      final chapters = await DriveService.instance.getChapters(comicId);
      // Sort chapters if needed (e.g. by name validation)
      // For now, assuming they are returned in some order or user sorted manually.
      // Let's sort by name for simple logic.
      chapters.sort((a, b) => _compareChapterNames(a.title, b.title));

      final currentChapter = chapters.firstWhereOrNull(
        (c) => c.id == chapterId,
      );

      state = state.copyWith(
        chapters: chapters,
        currentChapter: currentChapter,
      );

      // 3. Download Chapter Content
      final fileBytes = await DriveService.instance.downloadFile(chapterId);
      if (fileBytes == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Lỗi tải nội dung chương truyện',
        );
        return;
      }

      // 4. Unzip and Extract Images
      final archive = ZipDecoder().decodeBytes(fileBytes);
      final List<Uint8List> images = [];

      // Sort files in archive to ensure page order
      // Archive files might not be sorted alphabetically
      final sortedFiles = archive.files.toList()
        ..sort((a, b) => _compareChapterNames(a.name, b.name));

      for (final file in sortedFiles) {
        if (file.isFile) {
          final filename = file.name.toLowerCase();
          if (filename.endsWith('.jpg') ||
              filename.endsWith('.jpeg') ||
              filename.endsWith('.png') ||
              filename.endsWith('.webp')) {
            images.add(file.content);
          }
        }
      }

      if (images.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Không tìm thấy ảnh trong file truyện',
        );
        return;
      }

      state = state.copyWith(
        isLoading: false,
        pages: images,
        currentPageIndex: 0,
      );
    } catch (e) {
      debugPrint('Error loading reader: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Đã xảy ra lỗi: $e',
      );
    }
  }

  // Simple string comparison for chapter/page names (numeric aware ideally, but simple for now)
  int _compareChapterNames(String a, String b) {
    return a.compareTo(b);
  }

  void toggleControls() {
    state = state.copyWith(showControls: !state.showControls);
  }

  void setReadingMode(ReadingMode mode) {
    state = state.copyWith(readingMode: mode);
  }

  void onPageChanged(int index) {
    state = state.copyWith(currentPageIndex: index);
    // TODO: Add history saving logic here
  }

  String? getNextChapterId() {
    if (state.currentChapter == null || state.chapters.isEmpty) return null;
    final currentIndex = state.chapters.indexWhere(
      (c) => c.id == state.currentChapter!.id,
    );
    if (currentIndex != -1 && currentIndex + 1 < state.chapters.length) {
      return state.chapters[currentIndex + 1].id;
    }
    return null;
  }

  String? getPrevChapterId() {
    if (state.currentChapter == null || state.chapters.isEmpty) return null;
    final currentIndex = state.chapters.indexWhere(
      (c) => c.id == state.currentChapter!.id,
    );
    if (currentIndex != -1 && currentIndex - 1 >= 0) {
      return state.chapters[currentIndex - 1].id;
    }
    return null;
  }
}

final readerProvider =
    StateNotifierProvider.autoDispose<ReaderNotifier, ReaderState>((ref) {
      return ReaderNotifier();
    });
