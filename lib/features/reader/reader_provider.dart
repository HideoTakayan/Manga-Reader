import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdfx/pdfx.dart';
import '../../services/follow_service.dart';
import '../../services/history_service.dart';

import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../../data/database_helper.dart';
import '../../data/models.dart';

enum ReadingMode { vertical, horizontal }

class ReaderState {
  final bool isLoading;
  final bool isLoadingNextChapter;
  final bool isLoadingPrevChapter;
  final ReadingMode readingMode;
  final List<CloudChapter> chapters;
  final CloudChapter? currentChapter;
  final List<Uint8List> pages;
  final int currentPageIndex;
  final bool showControls;
  final String? errorMessage;
  final bool isLiked;
  final bool isFollowed;
  final String? comicId;
  final CloudComic? comic;
  final bool hasReachedEnd;
  final bool hasReachedStart;

  const ReaderState({
    this.isLoading = true,
    this.isLoadingNextChapter = false,
    this.isLoadingPrevChapter = false,
    this.readingMode = ReadingMode.vertical,
    this.chapters = const [],
    this.currentChapter,
    this.pages = const [],
    this.currentPageIndex = 0,
    this.showControls = true,
    this.errorMessage,
    this.isLiked = false,
    this.isFollowed = false,
    this.comicId,
    this.comic,
    this.hasReachedEnd = false,
    this.hasReachedStart = false,
  });

  ReaderState copyWith({
    bool? isLoading,
    bool? isLoadingNextChapter,
    bool? isLoadingPrevChapter,
    ReadingMode? readingMode,
    List<CloudChapter>? chapters,
    CloudChapter? currentChapter,
    List<Uint8List>? pages,
    int? currentPageIndex,
    bool? showControls,
    String? errorMessage,
    bool? isLiked,
    bool? isFollowed,
    String? comicId,
    CloudComic? comic,
    bool? hasReachedEnd,
    bool? hasReachedStart,
  }) {
    return ReaderState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingNextChapter: isLoadingNextChapter ?? this.isLoadingNextChapter,
      isLoadingPrevChapter: isLoadingPrevChapter ?? this.isLoadingPrevChapter,
      readingMode: readingMode ?? this.readingMode,
      chapters: chapters ?? this.chapters,
      currentChapter: currentChapter ?? this.currentChapter,
      pages: pages ?? this.pages,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      showControls: showControls ?? this.showControls,
      errorMessage: errorMessage ?? this.errorMessage,
      isLiked: isLiked ?? this.isLiked,
      isFollowed: isFollowed ?? this.isFollowed,
      comicId: comicId ?? this.comicId,
      comic: comic ?? this.comic,
      hasReachedEnd: hasReachedEnd ?? this.hasReachedEnd,
      hasReachedStart: hasReachedStart ?? this.hasReachedStart,
    );
  }
}

final readerProvider =
    NotifierProvider.autoDispose<ReaderNotifier, ReaderState>(
      ReaderNotifier.new,
    );

class ReaderNotifier extends AutoDisposeNotifier<ReaderState> {
  @override
  ReaderState build() {
    return const ReaderState();
  }

  Future<void> init(String chapterId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      // ========================================
      // OPTIMIZATION: Parallel API Calls
      // Previously: 6 sequential calls (~5s)
      // Now: Parallel where possible (~2s)
      // ========================================

      // Phase 1: Start download immediately while getting metadata
      // These two are independent and can run in parallel
      final downloadFuture = DriveService.instance.downloadFile(chapterId);
      final metaFuture = DriveService.instance.getFile(chapterId);

      // Wait for metadata first (needed for comicId)
      final fileMeta = await metaFuture;
      if (fileMeta == null ||
          fileMeta['parents'] == null ||
          (fileMeta['parents'] as List).isEmpty) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Không tìm thấy thông tin chương truyện',
        );
        return;
      }

      final comicId = (fileMeta['parents'] as List).first as String;

      // Phase 2: Now that we have comicId, fetch chapters and comics in parallel
      // while download continues in background
      final chaptersFuture = DriveService.instance.getChapters(comicId);
      final comicsFuture = DriveService.instance.getComics();
      
      // Check follow status in parallel (non-blocking)
      Future<bool> followFuture = Future.value(false);
      if (FirebaseAuth.instance.currentUser != null) {
        final followService = FollowService();
        followFuture = followService.isFollowing(comicId).first;
      }

      // Wait for all parallel operations
      final results = await Future.wait([
        chaptersFuture,
        comicsFuture,
        downloadFuture,
        followFuture,
      ]);

      final chapters = results[0] as List<CloudChapter>;
      final comics = results[1] as List<CloudComic>;
      final fileBytes = results[2] as Uint8List?;
      final followed = results[3] as bool;

      // Find current chapter in list
      final currentChapter = chapters.firstWhereOrNull(
        (c) => c.id == chapterId,
      );

      // Validate download
      if (fileBytes == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Lỗi tải nội dung chương truyện',
        );
        return;
      }

      // Phase 3: Extract images (CPU-bound, can't parallelize with API calls)
      final fileType = currentChapter?.fileType ?? 'zip';
      List<Uint8List> images = [];

      if (fileType == 'pdf') {
        images = await _extractImagesFromPdf(fileBytes);
      } else {
        images = await _extractImagesFromZip(fileBytes);
      }

      if (images.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Không tìm thấy ảnh trong file truyện',
        );
        return;
      }

      // Find comic info
      final fetchedComic = comics.firstWhereOrNull((c) => c.id == comicId);

      // Update state with all data
      state = state.copyWith(
        isLoading: false,
        chapters: chapters,
        currentChapter: currentChapter,
        pages: images,
        currentPageIndex: 0,
        isFollowed: followed,
        isLiked: false,
        comicId: comicId,
        comic: fetchedComic,
      );

      // Save history (non-blocking)
      _saveProgress();
      
      // Prefetch adjacent chapters in background (non-blocking)
      _prefetchAdjacentChapters();
    } catch (e) {
      debugPrint('Error loading reader: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Đã xảy ra lỗi: $e',
      );
    }
  }

  /// Prefetch next and previous chapters in background for faster navigation
  void _prefetchAdjacentChapters() {
    // Prefetch in background without blocking UI
    Future.microtask(() async {
      final nextId = getNextChapterId();
      final prevId = getPrevChapterId();
      
      // Fire and forget - these will be cached by DriveService
      if (nextId != null) {
        DriveService.instance.downloadFile(nextId).then((_) {
          debugPrint('✅ Prefetched next chapter: $nextId');
        }).catchError((_) {});
      }
      if (prevId != null) {
        DriveService.instance.downloadFile(prevId).then((_) {
          debugPrint('✅ Prefetched prev chapter: $prevId');
        }).catchError((_) {});
      }
    });
  }


  // Trích xuất ảnh từ file ZIP/CBZ
  Future<List<Uint8List>> _extractImagesFromZip(Uint8List fileBytes) async {
    final archive = ZipDecoder().decodeBytes(fileBytes);
    final List<Uint8List> images = [];

    // Sắp xếp file trong archive để đảm bảo thứ tự trang
    final sortedFiles = archive.files.toList()
      ..sort((a, b) => _naturalSort(a.name, b.name));

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

    return images;
  }

  // Trích xuất ảnh từ file PDF
  Future<List<Uint8List>> _extractImagesFromPdf(Uint8List fileBytes) async {
    try {
      final document = await PdfDocument.openData(fileBytes);
      final List<Uint8List> images = [];

      for (int i = 0; i < document.pagesCount; i++) {
        final page = await document.getPage(i + 1);
        final pageImage = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: PdfPageImageFormat.png,
        );

        if (pageImage != null && pageImage.bytes != null) {
          images.add(pageImage.bytes);
        }

        await page.close();
      }

      await document.close();
      return images;
    } catch (e) {
      debugPrint('Error extracting PDF: $e');
      return [];
    }
  }

  // So sánh chuỗi có hỗ trợ nhận diện số (Natural Sort)
  // Ví dụ: "10.jpg" sẽ đứng sau "2.jpg"
  int _naturalSort(String a, String b) {
    final regExp = RegExp(r"(\d+)|(\D+)");
    final aMatches = regExp.allMatches(a.toLowerCase()).toList();
    final bMatches = regExp.allMatches(b.toLowerCase()).toList();

    for (int i = 0; i < aMatches.length && i < bMatches.length; i++) {
      final aPart = aMatches[i].group(0)!;
      final bPart = bMatches[i].group(0)!;

      if (aPart != bPart) {
        final aInt = int.tryParse(aPart);
        final bInt = int.tryParse(bPart);

        if (aInt != null && bInt != null) {
          return aInt.compareTo(bInt);
        }
        return aPart.compareTo(bPart);
      }
    }
    return a.length.compareTo(b.length);
  }

  // So sánh chuỗi đơn giản cho tên chapter/page
  int _compareChapterNames(String a, String b) {
    return _naturalSort(a, b);
  }

  // Helper sắp xếp theo số (ví dụ: Chapter 1 < Chapter 10)
  int shortChapterSort(String a, String b) {
    return _naturalSort(a, b);
  }

  void toggleControls() {
    state = state.copyWith(showControls: !state.showControls);
  }

  void setReadingMode(ReadingMode mode) {
    state = state.copyWith(readingMode: mode);
  }

  void onPageChanged(int index) {
    state = state.copyWith(currentPageIndex: index);
    _saveProgress();
  }

  Future<void> _saveProgress() async {
    if (state.comicId == null || state.currentChapter == null) return;

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
      final history = ReadingHistory(
        userId: userId,
        comicId: state.comicId!,
        chapterId: state.currentChapter!.id,
        chapterTitle: state.currentChapter?.title,
        lastPageIndex: state.currentPageIndex,
        updatedAt: DateTime.now(),
      );
      // 2. Save to Local DB (SQLite)
      await DatabaseHelper.instance.saveHistory(history);

      // 3. Sync to Cloud (Firestore)
      await HistoryService.instance.saveHistory(history);
    } catch (e) {
      debugPrint("Error saving history: $e");
    }
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

  /// Load next chapter seamlessly without full page reload
  Future<void> loadNextChapter() async {
    // Prevent multiple calls
    if (state.isLoadingNextChapter) return;

    final nextChapterId = getNextChapterId();
    if (nextChapterId == null) {
      // No more chapters
      state = state.copyWith(hasReachedEnd: true);
      return;
    }

    state = state.copyWith(isLoadingNextChapter: true, hasReachedEnd: false);

    try {
      // Download next chapter content
      final fileBytes = await DriveService.instance.downloadFile(nextChapterId);
      if (fileBytes == null) {
        state = state.copyWith(isLoadingNextChapter: false);
        return;
      }

      // Find next chapter metadata
      final nextChapter = state.chapters.firstWhereOrNull(
        (c) => c.id == nextChapterId,
      );

      // Extract images
      final fileType = nextChapter?.fileType ?? 'zip';
      List<Uint8List> images = [];

      if (fileType == 'pdf') {
        images = await _extractImagesFromPdf(fileBytes);
      } else {
        images = await _extractImagesFromZip(fileBytes);
      }

      if (images.isEmpty) {
        state = state.copyWith(isLoadingNextChapter: false);
        return;
      }

      // Update state with new chapter
      state = state.copyWith(
        isLoadingNextChapter: false,
        currentChapter: nextChapter,
        pages: images,
        currentPageIndex: 0,
        hasReachedEnd: false,
      );

      // Save progress for new chapter
      _saveProgress();
    } catch (e) {
      debugPrint('Error loading next chapter: $e');
      state = state.copyWith(isLoadingNextChapter: false);
    }
  }

  /// Reset the hasReachedEnd flag
  void resetEndReached() {
    state = state.copyWith(hasReachedEnd: false);
  }

  /// Load previous chapter seamlessly without full page reload
  Future<void> loadPrevChapter() async {
    // Prevent multiple calls
    if (state.isLoadingPrevChapter) return;

    final prevChapterId = getPrevChapterId();
    if (prevChapterId == null) {
      // No previous chapters
      state = state.copyWith(hasReachedStart: true);
      return;
    }

    state = state.copyWith(isLoadingPrevChapter: true, hasReachedStart: false);

    try {
      // Download previous chapter content
      final fileBytes = await DriveService.instance.downloadFile(prevChapterId);
      if (fileBytes == null) {
        state = state.copyWith(isLoadingPrevChapter: false);
        return;
      }

      // Find previous chapter metadata
      final prevChapter = state.chapters.firstWhereOrNull(
        (c) => c.id == prevChapterId,
      );

      // Extract images
      final fileType = prevChapter?.fileType ?? 'zip';
      List<Uint8List> images = [];

      if (fileType == 'pdf') {
        images = await _extractImagesFromPdf(fileBytes);
      } else {
        images = await _extractImagesFromZip(fileBytes);
      }

      if (images.isEmpty) {
        state = state.copyWith(isLoadingPrevChapter: false);
        return;
      }

      // Update state with previous chapter (start at last page)
      state = state.copyWith(
        isLoadingPrevChapter: false,
        currentChapter: prevChapter,
        pages: images,
        currentPageIndex: images.length - 1,
        hasReachedStart: false,
      );

      // Save progress for new chapter
      _saveProgress();
    } catch (e) {
      debugPrint('Error loading previous chapter: $e');
      state = state.copyWith(isLoadingPrevChapter: false);
    }
  }

  /// Reset the hasReachedStart flag
  void resetStartReached() {
    state = state.copyWith(hasReachedStart: false);
  }

  Future<void> toggleFollow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && state.currentChapter != null) {
      try {
        final fileMeta = await DriveService.instance.getFile(
          state.currentChapter!.id,
        );
        if (fileMeta != null &&
            fileMeta['parents'] != null &&
            (fileMeta['parents'] as List).isNotEmpty) {
          final comicId = (fileMeta['parents'] as List).first as String;
          final followService = FollowService();

          // Lấy trạng thái hiện tại
          final isFollowed = await followService.isFollowing(comicId).first;

          if (isFollowed) {
            await followService.unfollowComic(comicId);
            state = state.copyWith(isFollowed: false);
          } else {
            final comics = await DriveService.instance.getComics();
            final comic = comics.firstWhereOrNull((c) => c.id == comicId);

            if (comic != null) {
              await followService.followComic(
                comicId: comicId,
                title: comic.title,
                coverUrl: DriveService.instance.getThumbnailLink(
                  comic.coverFileId,
                ),
              );
              state = state.copyWith(isFollowed: true);
            }
          }
        }
      } catch (e) {
        debugPrint("Error toggling follow: $e");
      }
    }
  }

  void toggleLike() {
    state = state.copyWith(isLiked: !state.isLiked);
  }
}
