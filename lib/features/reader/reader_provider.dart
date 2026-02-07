import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdfx/pdfx.dart';
import '../../services/follow_service.dart';
import '../../services/history_service.dart';
import '../../services/interaction_service.dart';

import '../../core/utils/chapter_utils.dart';

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
  final CloudManga? comic;
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
    CloudManga? comic,
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
      // CHECK OFFLINE MODE TRƯỚC
      // ========================================
      final isDownloaded = await DatabaseHelper.instance.isChapterDownloaded(
        chapterId,
      );

      if (isDownloaded) {
        debugPrint('📂 OFFLINE MODE: Đọc từ file local');
        await _loadOfflineChapter(chapterId);
        return;
      }

      // ========================================
      // ONLINE MODE: Fetch từ Drive
      // ========================================
      debugPrint('🌐 ONLINE MODE: Tải từ Google Drive');
      await _loadOnlineChapter(chapterId);
    } catch (e) {
      debugPrint('Error loading reader: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Đã xảy ra lỗi: $e',
      );
    }
  }

  /// OFFLINE MODE: Đọc file local (NHANH!)
  Future<void> _loadOfflineChapter(String chapterId) async {
    try {
      // 1. Lấy thông tin download từ database
      final downloadInfo = await DatabaseHelper.instance.getDownload(chapterId);

      if (downloadInfo == null) {
        debugPrint('⚠️ Download info not found, fallback to online');
        await _loadOnlineChapter(chapterId);
        return;
      }

      final localPath = downloadInfo['localPath'] as String;
      final mangaId = downloadInfo['mangaId'] as String;
      final chapterTitle = downloadInfo['chapterTitle'] as String?;

      debugPrint('📁 Local path: $localPath');

      // 2. Đọc file từ local
      final file = File(localPath);
      if (!await file.exists()) {
        debugPrint('⚠️ File not found, fallback to online');
        // Xóa record lỗi
        await DatabaseHelper.instance.deleteDownload(chapterId);
        await _loadOnlineChapter(chapterId);
        return;
      }

      final fileBytes = await file.readAsBytes();
      debugPrint('✅ Đọc file thành công (${fileBytes.length} bytes)');

      // 3. Extract images (giống online mode)
      // Detect file type từ extension
      final fileType = localPath.endsWith('.pdf') ? 'pdf' : 'zip';
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

      debugPrint('✅ Extracted ${images.length} images');

      // 4. Load chapters list và manga info (background - không block UI)
      // Tạo state tạm thời để hiển thị reader ngay
      state = state.copyWith(
        isLoading: false,
        pages: images,
        currentPageIndex: 0,
        comicId: mangaId,
        currentChapter: CloudChapter(
          id: chapterId,
          title: chapterTitle ?? 'Chapter',
          fileId: '',
          fileType: fileType,
          uploadedAt: DateTime.now(),
          viewCount: 0,
        ),
      );

      debugPrint('✅ Reader hiển thị (OFFLINE MODE)');

      // [Offline Navigation] Load local chapters list
      try {
        var downloadedMaps = await DatabaseHelper.instance.getDownloadsByManga(
          mangaId,
        );

        // [Fallback 1] Nếu query theo ID thất bại, load tất cả và lọc (phòng lỗi SQL/ID)
        if (downloadedMaps.isEmpty) {
          final all = await DatabaseHelper.instance.getAllDownloads();
          downloadedMaps = all
              .where((d) => d['mangaId'].toString() == mangaId)
              .toList();
        }

        // [Fallback 2 - ULTIMATE] Scan Folder (Mihon Style)
        // Fix lỗi khi ID trong Database bị sai lệch hoặc không khớp:
        // -> Gom tất cả các chapter nằm cùng thư mục với chapter hiện tại.
        if (downloadedMaps.length <= 1) {
          try {
            final currentFile = File(localPath);
            final parentDir = currentFile.parent.path;

            final all = await DatabaseHelper.instance.getAllDownloads();
            final siblingMaps = all.where((d) {
              final path = d['localPath'] as String?;
              if (path == null) return false;
              // Kiểm tra xem có nằm chung thư mục không (Simple Contains check)
              return path.contains(parentDir);
            }).toList();

            if (siblingMaps.length > downloadedMaps.length) {
              debugPrint(
                '📂 FS Scan found ${siblingMaps.length} chapters in $parentDir',
              );

              // 🔧 SILENT REPAIR: Update database records to unify mangaId
              for (final map in siblingMaps) {
                if (map['mangaId'].toString() != mangaId) {
                  debugPrint(
                    '🛠️ Repairing chapter ${map['chapterId']} -> $mangaId',
                  );
                  await DatabaseHelper.instance.updateDownloadMangaId(
                    map['chapterId'].toString(),
                    mangaId,
                  );
                }
              }

              downloadedMaps = siblingMaps;
            }
          } catch (e) {
            debugPrint('FS Fallback error: $e');
          }
        }

        // [Fallback 3] Ít nhất phải có chương hiện tại để không bị lỗi màn hình trắng
        if (downloadedMaps.isEmpty && downloadInfo != null) {
          downloadedMaps = [downloadInfo];
        }

        if (downloadedMaps.isNotEmpty) {
          final localChapters = downloadedMaps
              .map((d) {
                try {
                  final path = d['localPath'] as String? ?? '';
                  final type = path.toLowerCase().endsWith('.pdf')
                      ? 'pdf'
                      : 'cbz';
                  return CloudChapter(
                    id: d['chapterId'].toString(),
                    title:
                        d['chapterTitle'] as String? ??
                        d['chapterId'].toString(),
                    fileId: d['chapterId'].toString(),
                    fileType: type,
                    uploadedAt: DateTime.fromMillisecondsSinceEpoch(
                      (d['downloadDate'] as int?) ?? 0,
                    ),
                    viewCount: 0,
                  );
                } catch (e) {
                  debugPrint('Error mapping chapter: $e');
                  return null;
                }
              })
              .whereType<CloudChapter>()
              .toList();

          // Deduplicate and Sort using ChapterUtils (clean list immediately)
          final sortedChapters = await ChapterUtils.mergeChapters(
            [], // No online chapters yet
            localChapters,
            mangaId,
          );
          state = state.copyWith(chapters: sortedChapters);

          // [DEBUG]
          debugPrint('------- DEBUG OFFLINE NAV -------');
          debugPrint('Current Chapter ID: $chapterId');
          debugPrint(
            'Sorted List IDs: ${sortedChapters.map((c) => c.id).toList()}',
          );
          debugPrint(
            'Sorted List Titles: ${sortedChapters.map((c) => c.title).toList()}',
          );
          final index = sortedChapters.indexWhere((c) => c.id == chapterId);
          debugPrint('Current Index: $index');
          debugPrint('---------------------------------');

          debugPrint(
            '✅ Loaded ${sortedChapters.length} offline chapters for navigation',
          );
        }
      } catch (e) {
        debugPrint('⚠️ Error loading offline chapters: $e');
      }

      // 5. Load metadata sau (background)
      _loadMetadataInBackground(mangaId, chapterId);

      // 6. Lưu lịch sử đọc
      _saveProgress();
    } catch (e) {
      debugPrint('Error in offline mode: $e');
      // Fallback to online
      await _loadOnlineChapter(chapterId);
    }
  }

  /// ONLINE MODE: Fetch từ Drive (CHẬM nhưng đầy đủ)
  Future<void> _loadOnlineChapter(String chapterId) async {
    // ========================================
    // TỐI ƯU HÓA: Gọi API song song (Parallel API Calls)
    // Trước đây: 6 gọi tuần tự (~5s)
    // Hiện tại: Chạy song song các tác vụ độc lập (~2s)
    // ========================================

    // Giai đoạn 1: Bắt đầu tải file ngay lập tức trong khi lấy metadata
    // Hai tác vụ này độc lập nên có thể chạy song song
    final downloadFuture = DriveService.instance.downloadFile(chapterId);
    final metaFuture = DriveService.instance.getFile(chapterId);

    // Chờ metadata trước (cần để lấy comicId)
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

    // Giai đoạn 2: Sau khi có comicId, tải danh sách chapter và thông tin truyện song song
    // trong khi việc tải file vẫn đang chạy ngầm
    final chaptersFuture = DriveService.instance.getChapters(comicId);
    final comicsFuture = DriveService.instance.getMangas();

    // Kiểm tra trạng thái theo dõi song song (không chặn)
    Future<bool> followFuture = Future.value(false);
    if (FirebaseAuth.instance.currentUser != null) {
      final followService = FollowService();
      followFuture = followService.isFollowing(comicId).first;
    }

    // Chờ tất cả các tác vụ song song hoàn tất
    final results = await Future.wait<dynamic>([
      chaptersFuture,
      comicsFuture,
      downloadFuture,
      followFuture,
    ]);

    final chapters = results[0] as List<CloudChapter>;
    final comics = results[1] as List<CloudManga>;
    final fileBytes = results[2] as Uint8List?;
    final followed = results[3] as bool;

    // Find current chapter in list
    final currentChapter = chapters.firstWhereOrNull((c) => c.id == chapterId);

    // Kiểm tra file tải về
    if (fileBytes == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi tải nội dung chương truyện',
      );
      return;
    }

    // Giai đoạn 3: Giải nén ảnh (Tác vụ nặng CPU, không thể chạy song song với API calls)
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

    // Tìm thông tin comic tương ứng
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

    // Lưu lịch sử đọc (chạy ngầm, không chặn UI)
    _saveProgress();

    // Tăng lượt xem (chạy ngầm)
    InteractionService.instance.incrementChapterView(comicId, chapterId);

    // Tải trước các chương liền kề (Prefetch) để chuyển trang mượt mà
    _prefetchAdjacentChapters();
  }

  /// Load metadata trong background (không block UI)
  void _loadMetadataInBackground(String mangaId, String chapterId) {
    Future.microtask(() async {
      try {
        debugPrint('🔄 Loading metadata in background...');

        // Fetch chapters list và manga info
        final chaptersFuture = DriveService.instance.getChapters(mangaId);
        final mangasFuture = DriveService.instance.getMangas();

        Future<bool> followFuture = Future.value(false);
        if (FirebaseAuth.instance.currentUser != null) {
          final followService = FollowService();
          followFuture = followService.isFollowing(mangaId).first;
        }

        final results = await Future.wait([
          chaptersFuture,
          mangasFuture,
          followFuture,
        ]);

        final onlineChapters = results[0] as List<CloudChapter>;
        final mangas = results[1] as List<CloudManga>;
        final followed = results[2] as bool;

        final currentChapter = onlineChapters.firstWhereOrNull(
          (c) => c.id == chapterId,
        );
        final manga = mangas.firstWhereOrNull((m) => m.id == mangaId);

        // 🔧 FIX: Merge online + offline chapters (giống manga_detail_page.dart)
        final mergedChapters = await ChapterUtils.mergeChapters(
          onlineChapters,
          state.chapters,
          mangaId,
        );

        // Update state với metadata đầy đủ
        state = state.copyWith(
          chapters: mergedChapters.isNotEmpty ? mergedChapters : onlineChapters,
          currentChapter: currentChapter,
          comic: manga,
          isFollowed: followed,
        );

        debugPrint('✅ Metadata loaded (${mergedChapters.length} chapters)');

        // Tăng lượt xem
        InteractionService.instance.incrementChapterView(mangaId, chapterId);

        // Prefetch adjacent chapters
        _prefetchAdjacentChapters();
      } catch (e) {
        debugPrint('⚠️ Error loading metadata: $e');
        // Không cần xử lý lỗi vì reader đã hiển thị
      }
    });
  }

  /// Tải trước chương trước và sau chạy ngầm để tăng tốc độ chuyển chương
  void _prefetchAdjacentChapters() {
    // Chạy trong microtask để không chặn luồng chính
    Future.microtask(() async {
      final nextId = getNextChapterId();
      final prevId = getPrevChapterId();

      // Tải và quên (Fire and forget) - kết quả sẽ được cache bởi DriveService
      if (nextId != null) {
        DriveService.instance
            .downloadFile(nextId)
            .then((_) {
              debugPrint('✅ Prefetched next chapter: $nextId');
            })
            .catchError((_) {});
      }
      if (prevId != null) {
        DriveService.instance
            .downloadFile(prevId)
            .then((_) {
              debugPrint('✅ Prefetched prev chapter: $prevId');
            })
            .catchError((_) {});
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
        mangaId: state.comicId!,
        chapterId: state.currentChapter!.id,
        chapterTitle: state.currentChapter?.title,
        lastPageIndex: state.currentPageIndex,
        updatedAt: DateTime.now(),
      );
      // 2. Lưu vào DB nội bộ (SQLite) để xem offline
      await DatabaseHelper.instance.saveHistory(history);

      // 3. Đồng bộ lên Cloud (Firestore)
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

  /// Tải chương tiếp theo một cách mượt mà không cần load lại trang
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
      // 1. Check Offline first & Download content
      Uint8List? fileBytes;
      final downloadInfo = await DatabaseHelper.instance.getDownload(
        nextChapterId,
      );

      if (downloadInfo != null) {
        final localPath = downloadInfo['localPath'] as String;
        final file = File(localPath);
        if (await file.exists()) {
          debugPrint('📂 Reading NEXT chapter from local: $localPath');
          try {
            fileBytes = await file.readAsBytes();
          } catch (e) {
            debugPrint('⚠️ Error reading local file: $e');
          }
        }
      }

      // 2. If not found local, download online
      if (fileBytes == null) {
        debugPrint('🌐 Downloading NEXT chapter from Drive');
        fileBytes = await DriveService.instance.downloadFile(nextChapterId);
      }

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

      // Increment View Count
      if (state.comicId != null && nextChapter != null) {
        InteractionService.instance.incrementChapterView(
          state.comicId!,
          nextChapter.id,
        );
      }
    } catch (e) {
      debugPrint('Error loading next chapter: $e');
      state = state.copyWith(isLoadingNextChapter: false);
    }
  }

  /// Reset the hasReachedEnd flag
  void resetEndReached() {
    state = state.copyWith(hasReachedEnd: false);
  }

  /// Tải chương trước đó một cách mượt mà không cần load lại trang
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
      // 1. Check Offline first & Download content
      Uint8List? fileBytes;
      final downloadInfo = await DatabaseHelper.instance.getDownload(
        prevChapterId,
      );

      if (downloadInfo != null) {
        final localPath = downloadInfo['localPath'] as String;
        final file = File(localPath);
        if (await file.exists()) {
          debugPrint('📂 Reading PREV chapter from local: $localPath');
          try {
            fileBytes = await file.readAsBytes();
          } catch (e) {
            debugPrint('⚠️ Error reading local file: $e');
          }
        }
      }

      // 2. If not found local, download online
      if (fileBytes == null) {
        debugPrint('🌐 Downloading PREV chapter from Drive');
        fileBytes = await DriveService.instance.downloadFile(prevChapterId);
      }

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

      // Increment View Count
      if (state.comicId != null && prevChapter != null) {
        InteractionService.instance.incrementChapterView(
          state.comicId!,
          prevChapter.id,
        );
      }
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
            await followService.unfollowManga(comicId);
            state = state.copyWith(isFollowed: false);
          } else {
            final comics = await DriveService.instance.getMangas();
            final comic = comics.firstWhereOrNull((c) => c.id == comicId);

            if (comic != null) {
              await followService.followManga(
                mangaId: comicId,
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
