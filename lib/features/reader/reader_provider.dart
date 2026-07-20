import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/follow_service.dart';
import '../../services/interaction_service.dart';
import '../../services/download_cache.dart';

import '../../core/utils/chapter_utils.dart';
import '../../core/utils/archive_image_extractor.dart';

import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../../data/database_helper.dart';

import '../../data/models.dart';

enum ReadingMode { vertical, horizontal }

enum ReaderImageFit { width, screen, original }

enum ReaderDirection { ltr, rtl }

enum ReaderBackground { black, gray, white }

class ReaderState {
  final bool isLoading;
  final bool isLoadingNextChapter;
  final bool isLoadingPrevChapter;
  final ReadingMode readingMode;
  final List<CloudChapter> chapters;
  final CloudChapter? currentChapter;
  final List<String> pages;
  final Uint8List? epubBytes; // Dữ liệu file EPUB cho truyện chữ
  final Uint8List? pdfBytes; // Dữ liệu file PDF gốc (không giải nén ngầm)
  final int pdfPageCount; // Số trang của file PDF
  final int currentPageIndex;
  final bool showControls;
  final String? errorMessage;
  final bool isLiked;
  final bool isFollowed;
  final bool isCurrentPageBookmarked;
  final String? mangaId;
  final CloudManga? manga;
  final double scrollOffset;
  final bool hasReachedEnd;
  final bool hasReachedStart;
  final ReaderImageFit imageFit;
  final ReaderDirection direction;
  final ReaderBackground background;
  final bool
  isNovel; // Cờ xác định đây là truyện chữ (EPUB) hay truyện tranh (Ảnh)
  final bool isPdf; // Cờ xác định đây là định dạng PDF

  const ReaderState({
    this.isLoading = true,
    this.isLoadingNextChapter = false,
    this.isLoadingPrevChapter = false,
    this.readingMode = ReadingMode.vertical,
    this.chapters = const [],
    this.currentChapter,
    this.pages = const [],
    this.epubBytes,
    this.pdfBytes,
    this.pdfPageCount = 0,
    this.currentPageIndex = 0,
    this.showControls = true,
    this.errorMessage,
    this.isLiked = false,
    this.isFollowed = false,
    this.isCurrentPageBookmarked = false,
    this.mangaId,
    this.manga,
    this.scrollOffset = 0,
    this.hasReachedEnd = false,
    this.hasReachedStart = false,
    this.imageFit = ReaderImageFit.width,
    this.direction = ReaderDirection.ltr,
    this.background = ReaderBackground.black,
    this.isNovel = false,
    this.isPdf = false,
  });

  ReaderState copyWith({
    bool? isLoading,
    bool? isLoadingNextChapter,
    bool? isLoadingPrevChapter,
    ReadingMode? readingMode,
    List<CloudChapter>? chapters,
    CloudChapter? currentChapter,
    List<String>? pages,
    Uint8List? epubBytes,
    bool clearEpubBytes = false,
    Uint8List? pdfBytes,
    bool clearPdfBytes = false,
    int? pdfPageCount,
    int? currentPageIndex,
    bool? showControls,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isLiked,
    bool? isFollowed,
    bool? isCurrentPageBookmarked,
    String? mangaId,
    CloudManga? manga,
    double? scrollOffset,
    bool? hasReachedEnd,
    bool? hasReachedStart,
    ReaderImageFit? imageFit,
    ReaderDirection? direction,
    ReaderBackground? background,
    bool? isNovel,
    bool? isPdf,
  }) {
    return ReaderState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingNextChapter: isLoadingNextChapter ?? this.isLoadingNextChapter,
      isLoadingPrevChapter: isLoadingPrevChapter ?? this.isLoadingPrevChapter,
      readingMode: readingMode ?? this.readingMode,
      chapters: chapters ?? this.chapters,
      currentChapter: currentChapter ?? this.currentChapter,
      pages: pages ?? this.pages,
      epubBytes: clearEpubBytes ? null : (epubBytes ?? this.epubBytes),
      pdfBytes: clearPdfBytes ? null : (pdfBytes ?? this.pdfBytes),
      pdfPageCount: pdfPageCount ?? this.pdfPageCount,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      showControls: showControls ?? this.showControls,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      isLiked: isLiked ?? this.isLiked,
      isFollowed: isFollowed ?? this.isFollowed,
      isCurrentPageBookmarked:
          isCurrentPageBookmarked ?? this.isCurrentPageBookmarked,
      mangaId: mangaId ?? this.mangaId,
      manga: manga ?? this.manga,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      hasReachedEnd: hasReachedEnd ?? this.hasReachedEnd,
      hasReachedStart: hasReachedStart ?? this.hasReachedStart,
      imageFit: imageFit ?? this.imageFit,
      direction: direction ?? this.direction,
      background: background ?? this.background,
      isNovel: isNovel ?? this.isNovel,
      isPdf: isPdf ?? this.isPdf,
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

  String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return '';
    return value.toString().trim();
  }

  int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _readFirstString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is List && value.isNotEmpty) {
      return value.first?.toString().trim() ?? '';
    }
    return '';
  }

  String _fileTypeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.epub')) return 'epub';
    if (lower.endsWith('.pdf')) return 'pdf';
    if (lower.endsWith('.cbz')) return 'cbz';
    return 'zip';
  }

  Future<ReaderProgress?> _loadSavedProgress(
    String mangaId,
    String chapterId,
  ) async {
    final progress = await DatabaseHelper.instance.getReaderProgress(mangaId);
    if (progress == null || progress.chapterId != chapterId) return null;
    return progress;
  }

  int _restorePageIndex(ReaderProgress? progress, int? pageCount) {
    if (progress == null) return 0;
    if (pageCount == null || pageCount <= 0) return progress.pageIndex;
    return progress.pageIndex.clamp(0, pageCount - 1);
  }

  Future<void> _refreshBookmarkState() async {
    final mangaId = state.mangaId;
    final chapter = state.currentChapter;
    if (mangaId == null || chapter == null) {
      state = state.copyWith(isCurrentPageBookmarked: false);
      return;
    }

    final bookmark = await DatabaseHelper.instance.getBookmarkForPage(
      mangaId: mangaId,
      chapterId: chapter.id,
      pageIndex: state.currentPageIndex,
    );
    state = state.copyWith(isCurrentPageBookmarked: bookmark != null);
  }

  Future<void> init(String chapterId, {String? mangaId}) async {
    state = ReaderState(
      isLoading: true,
      readingMode: state.readingMode,
      imageFit: state.imageFit,
      direction: state.direction,
      background: state.background,
    );

    // Load chế độ đọc đã lưu từ SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString('reading_mode');
    final savedImageFit = prefs.getString('reader_image_fit');
    final savedDirection = prefs.getString('reader_direction');
    final savedBackground = prefs.getString('reader_background');
    final mode =
        ReadingMode.values.firstWhereOrNull((m) => m.name == savedMode) ??
        ReadingMode.vertical;
    final imageFit =
        ReaderImageFit.values.firstWhereOrNull(
          (fit) => fit.name == savedImageFit,
        ) ??
        ReaderImageFit.width;
    final direction =
        ReaderDirection.values.firstWhereOrNull(
          (direction) => direction.name == savedDirection,
        ) ??
        ReaderDirection.ltr;
    final background =
        ReaderBackground.values.firstWhereOrNull(
          (background) => background.name == savedBackground,
        ) ??
        ReaderBackground.black;
    state = state.copyWith(
      readingMode: mode,
      imageFit: imageFit,
      direction: direction,
      background: background,
      clearErrorMessage: true,
    );

    try {
      // ========================================
      // KIỂM TRA CHẾ ĐỘ NGOẠI TUYẾN TRƯỚC
      // ========================================
      final isDownloaded = await DatabaseHelper.instance.isChapterDownloaded(
        chapterId,
      );

      if (isDownloaded) {
        debugPrint('📂 CHẾ ĐỘ NGOẠI TUYẾN: Đọc từ tệp cục bộ');
        await _loadOfflineChapter(chapterId, preferredMangaId: mangaId);
        return;
      }

      // ========================================
      // CHẾ ĐỘ TRỰC TUYẾN: Lấy từ Drive
      // ========================================
      debugPrint('🌐 CHẾ ĐỘ TRỰC TUYẾN: Tải từ Google Drive');
      await _loadOnlineChapter(chapterId, mangaId: mangaId);
    } catch (e) {
      debugPrint('Error loading reader: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Đã xảy ra lỗi: $e',
      );
    }
  }

  /// CHẾ ĐỘ NGOẠI TUYẾN: Đọc tệp cục bộ (NHANH!)
  Future<void> _loadOfflineChapter(
    String chapterId, {
    String? preferredMangaId,
  }) async {
    try {
      // 0. Kiểm tra Fast Cache (nếu người dùng vừa đọc và đã bung nén)
      final cachedPages = await ArchiveImageExtractor.getCachedExtractedPages(chapterId);
      if (cachedPages != null && cachedPages.isNotEmpty) {
        debugPrint('⚡ Fast load from extracted cache for offline chapter: $chapterId');
        final currentChapter = CloudChapter(
          id: chapterId,
          title: 'Chương tải xuống',
          fileId: chapterId,
          fileType: 'cbz',
          uploadedAt: DateTime.now(),
        );
        final savedProgress = await _loadSavedProgress(preferredMangaId ?? '', chapterId);
        
        state = state.copyWith(
          isLoading: false,
          currentChapter: currentChapter,
          currentPageIndex: _restorePageIndex(savedProgress, cachedPages.length),
          scrollOffset: savedProgress?.scrollOffset ?? 0,
          isLiked: false,
          mangaId: preferredMangaId,
          clearErrorMessage: true,
          pages: cachedPages,
          isNovel: false,
          isPdf: false,
          clearEpubBytes: true,
          clearPdfBytes: true,
          pdfPageCount: 0,
        );
        
        _saveProgress();
        _refreshBookmarkState();
        if (preferredMangaId != null) {
          _loadMetadataInBackground(preferredMangaId, chapterId);
        }
        return;
      }

      // 1. Lấy thông tin tải xuống từ cơ sở dữ liệu
      final downloadInfo = await DatabaseHelper.instance.getDownload(chapterId);

      if (downloadInfo == null) {
        debugPrint(
          '⚠️ Không tìm thấy thông tin tải xuống, dự phòng sang trực tuyến',
        );
        await _loadOnlineChapter(chapterId, mangaId: preferredMangaId);
        return;
      }

      final localPath = _readString(downloadInfo, 'localPath');
      final mangaId = _readString(downloadInfo, 'mangaId');
      final chapterTitle = _readString(downloadInfo, 'chapterTitle');

      if (localPath.isEmpty || mangaId.isEmpty) {
        await DatabaseHelper.instance.deleteDownload(chapterId);
        if (mangaId.isNotEmpty) {
          await DownloadCache.instance.removeChapter(chapterId, mangaId);
        }
        await _loadOnlineChapter(chapterId, mangaId: preferredMangaId);
        return;
      }

      debugPrint('📁 Local path: $localPath');

      // 2. Đọc tệp từ cục bộ
      final file = File(localPath);
      if (!await file.exists()) {
        debugPrint('⚠️ Không tìm thấy tệp, dự phòng sang trực tuyến');
        // Xóa bản ghi lỗi
        await DatabaseHelper.instance.deleteDownload(chapterId);
        await DownloadCache.instance.removeChapter(chapterId, mangaId);
        await _loadOnlineChapter(chapterId, mangaId: preferredMangaId);
        return;
      }

      final fileBytes = await file.readAsBytes();
      debugPrint('✅ Đọc file thành công (${fileBytes.length} bytes)');

      // 3. Phát hiện loại tệp từ phần mở rộng
      final ext = localPath.toLowerCase();
      final fileType = ext.endsWith('.pdf')
          ? 'pdf'
          : ext.endsWith('.epub')
          ? 'epub'
          : 'zip';
      final savedProgress = await _loadSavedProgress(mangaId, chapterId);

      // --- Trường hợp EPUB (Truyện chữ) ---
      if (fileType == 'epub') {
        state = state.copyWith(
          isLoading: false,
          pages: const [],
          epubBytes: fileBytes,
          clearPdfBytes: true,
          clearErrorMessage: true,
          isNovel: true,
          isPdf: false,
          mangaId: mangaId,
          scrollOffset: savedProgress?.scrollOffset ?? 0,
          currentChapter: CloudChapter(
            id: chapterId,
            title: chapterTitle.isEmpty ? 'Chapter' : chapterTitle,
            fileId: '',
            fileType: 'epub',
            uploadedAt: DateTime.now(),
          ),
        );
        debugPrint('✅ Reader hiển thị (OFFLINE EPUB MODE)');
        _saveProgress();
        _refreshBookmarkState();
        _loadMetadataInBackground(mangaId, chapterId);
        return;
      }

      // --- Trường hợp Manga (Truyện tranh) ---
      if (fileType == 'pdf') {
        state = state.copyWith(
          isLoading: false,
          pages: const [],
          pdfBytes: fileBytes,
          clearEpubBytes: true,
          clearErrorMessage: true,
          isNovel: false,
          isPdf: true,
          pdfPageCount: 0,
          currentPageIndex: _restorePageIndex(savedProgress, null),
          scrollOffset: savedProgress?.scrollOffset ?? 0,
          mangaId: mangaId,
          currentChapter: CloudChapter(
            id: chapterId,
            title: chapterTitle.isEmpty ? 'Chapter' : chapterTitle,
            fileId: '',
            fileType: fileType,
            uploadedAt: DateTime.now(),
            viewCount: 0,
          ),
        );
      } else {
        // ZIP / CBZ: Trích xuất ảnh ngay xuống ổ cứng thay vì RAM
        final images = await _extractImagesFromZip(fileBytes, chapterId);
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
          clearPdfBytes: true,
          clearEpubBytes: true,
          clearErrorMessage: true,
          isPdf: false,
          isNovel: false,
          pdfPageCount: 0,
          currentPageIndex: _restorePageIndex(savedProgress, images.length),
          scrollOffset: savedProgress?.scrollOffset ?? 0,
          mangaId: mangaId,
          currentChapter: CloudChapter(
            id: chapterId,
            title: chapterTitle.isEmpty ? 'Chapter' : chapterTitle,
            fileId: '',
            fileType: fileType,
            uploadedAt: DateTime.now(),
            viewCount: 0,
          ),
        );
      }

      debugPrint('✅ Reader hiển thị (OFFLINE MODE)');

      // [Điều hướng Ngoại tuyến] Tải danh sách chương cục bộ
      try {
        var downloadedMaps = await DatabaseHelper.instance.getDownloadsByManga(
          mangaId,
        );

        // [Dự phòng 1] Nếu truy vấn theo ID thất bại, tải tất cả và lọc (phòng lỗi SQL/ID)
        if (downloadedMaps.isEmpty) {
          final all = await DatabaseHelper.instance.getAllDownloads();
          downloadedMaps = all
              .where((d) => d['mangaId'].toString() == mangaId)
              .toList();
        }

        // [Dự phòng 2 ] Quét thư mục
        // Sửa lỗi khi ID trong Cơ sở dữ liệu bị sai lệch hoặc không khớp:
        // -> Gom tất cả các chương nằm cùng thư mục với chương hiện tại.
        if (downloadedMaps.length <= 1) {
          try {
            final currentFile = File(localPath);
            final parentDir = currentFile.parent.path;

            final all = await DatabaseHelper.instance.getAllDownloads();
            final siblingMaps = all.where((d) {
              final path = _readString(d, 'localPath');
              if (path.isEmpty) return false;
              // Chỉ gom các chương nằm đúng cùng folder, tránh bắt nhầm folder có tên tiền tố giống nhau.
              return File(path).parent.path == parentDir;
            }).toList();

            if (siblingMaps.length > downloadedMaps.length) {
              debugPrint(
                '📂 FS Scan found ${siblingMaps.length} chapters in $parentDir',
              );

              //  SỬA CHỮA NGẦM: Cập nhật bản ghi cơ sở dữ liệu để đồng nhất mangaId
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
        if (downloadedMaps.isEmpty) {
          downloadedMaps = [downloadInfo];
        }

        if (downloadedMaps.isNotEmpty) {
          final localChapters = downloadedMaps
              .map((d) {
                try {
                  final path = _readString(d, 'localPath');
                  final ext2 = path.toLowerCase();
                  final type = ext2.endsWith('.pdf')
                      ? 'pdf'
                      : ext2.endsWith('.epub')
                      ? 'epub'
                      : 'cbz';
                  return CloudChapter(
                    id: d['chapterId'].toString(),
                    title: _readString(d, 'chapterTitle').isEmpty
                        ? d['chapterId'].toString()
                        : _readString(d, 'chapterTitle'),
                    fileId: d['chapterId'].toString(),
                    fileType: type,
                    uploadedAt: DateTime.fromMillisecondsSinceEpoch(
                      _readInt(d, 'downloadDate'),
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

          // Xóa trùng lặp và Sắp xếp sử dụng ChapterUtils (danh sách sạch ngay lập tức)
          final sortedChapters = await ChapterUtils.mergeChapters(
            [], // Chưa có chương trực tuyến
            localChapters,
            mangaId,
          );
          state = state.copyWith(chapters: sortedChapters);

          // [DEBUG]
          if (kDebugMode) {
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
          }

          debugPrint(
            '✅ Loaded ${sortedChapters.length} offline chapters for navigation',
          );
        }
      } catch (e) {
        debugPrint('⚠️ Error loading offline chapters: $e');
      }

      _loadMetadataInBackground(mangaId, chapterId);

      // 6. Lưu lịch sử đọc
      _saveProgress();
      _refreshBookmarkState();
    } catch (e) {
      debugPrint('Error in offline mode: $e');
      // Fallback to online
      await _loadOnlineChapter(chapterId, mangaId: preferredMangaId);
    }
  }

  /// Tải ngầm chương tiếp theo để chuyển chương mượt mà

  /// CHẾ ĐỘ TRỰC TUYẾN: Lấy từ Drive
  Future<void> _loadOnlineChapter(String chapterId, {String? mangaId}) async {
    // ========================================
    // TỐI ƯU HÓA TỐC ĐỘ: Bỏ qua tải và bung file nếu đã có sẵn trong Cache
    // ========================================
    final cachedPages = await ArchiveImageExtractor.getCachedExtractedPages(chapterId);
    if (cachedPages != null && cachedPages.isNotEmpty) {
      debugPrint('⚡ Fast load from extracted cache for online chapter: $chapterId');
      final currentChapter = CloudChapter(
        id: chapterId,
        title: 'Chương hiện tại',
        fileId: chapterId,
        fileType: 'cbz', // Default for extracted images
        uploadedAt: DateTime.now(),
      );
      final savedProgress = await _loadSavedProgress(mangaId ?? '', chapterId);
      
      state = state.copyWith(
        isLoading: false,
        currentChapter: currentChapter,
        currentPageIndex: _restorePageIndex(savedProgress, cachedPages.length),
        scrollOffset: savedProgress?.scrollOffset ?? 0,
        isLiked: false,
        mangaId: mangaId,
        clearErrorMessage: true,
        pages: cachedPages,
        isNovel: false,
        isPdf: false,
        clearEpubBytes: true,
        clearPdfBytes: true,
        pdfPageCount: 0,
      );
      
      _saveProgress();
      _refreshBookmarkState();
      
      if (mangaId != null && mangaId.isNotEmpty) {
        _loadMetadataInBackground(mangaId, chapterId);
      } else {
        DriveService.instance.getFile(chapterId).then((fileMeta) {
           final resolvedMangaId = fileMeta == null ? '' : _readFirstString(fileMeta, 'parents');
           if (resolvedMangaId.isNotEmpty) {
             state = state.copyWith(mangaId: resolvedMangaId);
             _loadMetadataInBackground(resolvedMangaId, chapterId);
           }
        });
      }
      return;
    }

    // ========================================
    // TỐI ƯU HÓA: Gọi API song song (Parallel API Calls)
    // Chạy song song các tác vụ độc lập (~2s)
    // ========================================

    // Giai đoạn 1: Bắt đầu tải file ngay lập tức trong khi lấy metadata
    // Hai tác vụ này độc lập nên có thể chạy song song
    final downloadFuture = DriveService.instance.downloadFile(chapterId);
    final metaFuture = DriveService.instance.getFile(chapterId);

    // Chờ metadata trước (cần để lấy mangaId)
    final fileMeta = await metaFuture;
    final resolvedMangaId = mangaId != null && mangaId.isNotEmpty
        ? mangaId
        : fileMeta == null
        ? ''
        : _readFirstString(fileMeta, 'parents');
    if (resolvedMangaId.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Không tìm thấy thông tin chương truyện',
      );
      return;
    }

    mangaId = resolvedMangaId;

    // Giai đoạn 2: CHỈ chờ tải file hoàn tất để hiển thị sớm nhất có thể.
    // Việc tải danh sách chương (Metadata) sẽ được đẩy xuống chạy ngầm ở cuối hàm.
    final fileBytes = await downloadFuture;

    // Kiểm tra file tải về
    if (fileBytes == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi tải nội dung chương truyện',
      );
      return;
    }

    // Tạo thông tin chương tạm thời từ tên file
    final fileName = fileMeta == null ? '' : _readString(fileMeta, 'name');
    final currentChapter = CloudChapter(
      id: chapterId,
      title: fileName.isEmpty ? 'Chương hiện tại' : fileName,
      fileId: chapterId,
      fileType: _fileTypeFromName(fileName),
      sizeBytes: fileMeta == null ? 0 : _readInt(fileMeta, 'size'),
      uploadedAt: DateTime.now(),
    );

    // Giai đoạn 3: Xử lý nội dung theo loại file
    final fileType = currentChapter.fileType;
    final savedProgress = await _loadSavedProgress(mangaId, chapterId);

    // Cập nhật State NGAY LẬP TỨC để UI mở ra (không cần đợi Metadata)
    final baseState = state.copyWith(
      isLoading: false,
      currentChapter: currentChapter,
      currentPageIndex: 0,
      scrollOffset: savedProgress?.scrollOffset ?? 0,
      isLiked: false,
      mangaId: mangaId,
      clearErrorMessage: true,
      // Metadata (chapters, manga, followed) sẽ giữ nguyên tạm thời
      // và được cập nhật chính xác ở _loadMetadataInBackground
    );

    // --- Trường hợp EPUB (Truyện chữ) ---
    if (fileType == 'epub') {
      state = baseState.copyWith(
        epubBytes: fileBytes,
        clearPdfBytes: true,
        isPdf: false,
        isNovel: true,
        pages: const [],
        pdfPageCount: 0,
      );
    }
    // --- Trường hợp Manga (Truyện tranh: PDF / ZIP / CBZ) ---
    else if (fileType == 'pdf') {
      state = baseState.copyWith(
        pages: const [],
        isNovel: false,
        isPdf: true,
        clearEpubBytes: true,
        pdfBytes: fileBytes,
        pdfPageCount: 0,
        currentPageIndex: _restorePageIndex(savedProgress, null),
      );
    } else {
      final images = await _extractImagesFromZip(fileBytes, chapterId);
      if (images.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Không tìm thấy ảnh trong file truyện',
        );
        return;
      }
      state = baseState.copyWith(
        pages: images,
        isNovel: false,
        isPdf: false,
        clearEpubBytes: true,
        clearPdfBytes: true,
        pdfPageCount: 0,
        currentPageIndex: _restorePageIndex(savedProgress, images.length),
      );
    }

    // Lưu lịch sử đọc (chạy ngầm)
    _saveProgress();
    _refreshBookmarkState();

    // Khởi chạy việc tải danh sách chương & cập nhật lượt xem ngầm (không chặn UI)
    _loadMetadataInBackground(mangaId, chapterId);
  }

  /// Tải siêu dữ liệu chạy ngầm (không chặn UI)
  void _loadMetadataInBackground(String mangaId, String chapterId) {
    Future.microtask(() async {
      try {
        debugPrint('🔄 Loading metadata in background...');

        // Tải danh sách chương và thông tin truyện
        final chaptersFuture = DriveService.instance.getChapters(mangaId);
        final mangasFuture = DriveService.instance.getMangas();

        Future<bool> followFuture = Future.value(false);
        if (FirebaseAuth.instance.currentUser != null) {
          final followService = FollowService();
          followFuture = followService.isFollowing(mangaId).first;
        }

        final onlineChapters = await chaptersFuture;
        final mangas = await mangasFuture;
        final followed = await followFuture;

        final currentChapter = onlineChapters.firstWhereOrNull(
          (c) => c.id == chapterId,
        );
        final manga = mangas.firstWhereOrNull((m) => m.id == mangaId);

        if (state.mangaId != mangaId || state.currentChapter?.id != chapterId) {
          debugPrint('Skip stale reader metadata for chapter: $chapterId');
          return;
        }

        // 🔧 SỬA: Gộp chương trực tuyến + ngoại tuyến (giống manga_detail_page.dart)
        final mergedChapters = await ChapterUtils.mergeChapters(
          onlineChapters,
          state.chapters,
          mangaId,
        );

        // Cập nhật trạng thái với siêu dữ liệu đầy đủ
        state = state.copyWith(
          chapters: mergedChapters.isNotEmpty ? mergedChapters : onlineChapters,
          currentChapter: currentChapter,
          manga: manga,
          isFollowed: followed,
        );

        debugPrint('✅ Metadata loaded (${mergedChapters.length} chapters)');

        // Tăng lượt xem
        InteractionService.instance.incrementChapterView(mangaId, chapterId);

        // Tải trước các chương liền kề
        _prefetchAdjacentChapters();
      } catch (e) {
        debugPrint('⚠️ Error loading metadata: $e');
        // Không cần xử lý lỗi vì trình đọc đã hiển thị
      }
    });
  }

  /// Tải trước chương trước và sau chạy ngầm để tăng tốc độ chuyển chương.
  /// Chỉ prefetch tối đa 2 chương liền kề (kế tiếp + trước) để giới hạn cache disk.
  void _prefetchAdjacentChapters() {
    // Chạy trong microtask để không chặn luồng chính
    Future.microtask(() async {
      final nextId = getNextChapterId();
      final prevId = getPrevChapterId();

      // Tải và quên (Fire and forget) - kết quả sẽ được bung nén trực tiếp xuống ổ cứng
      if (nextId != null) {
        final nextChap = state.chapters.firstWhereOrNull((c) => c.id == nextId);
        if (nextChap?.fileType != 'pdf') {
          ArchiveImageExtractor.getCachedExtractedPages(nextId).then((cached) {
            if (cached == null || cached.isEmpty) {
              DriveService.instance.downloadFile(nextId).then((bytes) async {
                if (bytes != null) await _extractImagesFromZip(bytes, nextId);
                debugPrint('✅ Prefetched next chapter: $nextId');
              }).catchError((_) {});
            } else {
              debugPrint('✅ Next chapter already in fast cache: $nextId');
            }
          });
        } else {
          debugPrint('⏭️ Skip prefetch for PDF: $nextId');
        }
      }
      if (prevId != null) {
        final prevChap = state.chapters.firstWhereOrNull((c) => c.id == prevId);
        if (prevChap?.fileType != 'pdf') {
          ArchiveImageExtractor.getCachedExtractedPages(prevId).then((cached) {
            if (cached == null || cached.isEmpty) {
              DriveService.instance.downloadFile(prevId).then((bytes) async {
                if (bytes != null) await _extractImagesFromZip(bytes, prevId);
                debugPrint('✅ Prefetched prev chapter: $prevId');
              }).catchError((_) {});
            } else {
              debugPrint('✅ Prev chapter already in fast cache: $prevId');
            }
          });
        } else {
          debugPrint('⏭️ Skip prefetch for PDF: $prevId');
        }
      }
    });
  }

  // Trích xuất ảnh từ tệp ZIP/CBZ xuống ổ cứng (temp directory)
  Future<List<String>> _extractImagesFromZip(
    Uint8List fileBytes,
    String chapterId,
  ) async {
    try {
      return await ArchiveImageExtractor.extract(fileBytes, chapterId);
    } catch (e) {
      debugPrint('ZIP extraction error: $e');
      return [];
    }
  }

  // So sánh chuỗi đơn giản cho tên chương/trang — dùng _naturalSort trực tiếp
  // [Dead code đã xóa: _compareChapterNames, shortChapterSort]

  void toggleControls() {
    state = state.copyWith(showControls: !state.showControls);
  }

  void setPdfPageCount(int count) {
    if (state.isPdf) {
      state = state.copyWith(pdfPageCount: count);
    }
  }

  /// Cập nhật chế độ đọc và persist vào SharedPreferences để nhớ qua các lần mở app.
  void setReadingMode(ReadingMode mode) async {
    state = state.copyWith(readingMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reading_mode', mode.name);
  }

  void setImageFit(ReaderImageFit fit) async {
    state = state.copyWith(imageFit: fit);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reader_image_fit', fit.name);
  }

  void setDirection(ReaderDirection direction) async {
    state = state.copyWith(direction: direction);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reader_direction', direction.name);
  }

  void setBackground(ReaderBackground background) async {
    state = state.copyWith(background: background);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reader_background', background.name);
  }

  void onPageChanged(int index) {
    state = state.copyWith(currentPageIndex: index);
    unawaited(_saveProgress());
    _refreshBookmarkState();
  }

  void updateScrollPosition(double offset, int pageIndex) {
    if (pageIndex == state.currentPageIndex) return;
    state = state.copyWith(scrollOffset: offset, currentPageIndex: pageIndex);
    _refreshBookmarkState();
    unawaited(_saveProgress()); // Lưu tiến độ ngay khi cuộn để tránh mất data khi app crash
  }

  Future<void> saveScrollProgress(double offset, {int? pageIndex}) async {
    state = state.copyWith(
      scrollOffset: offset,
      currentPageIndex: pageIndex ?? state.currentPageIndex,
    );
    await _saveProgress(scrollOffset: offset);
    _refreshBookmarkState();
  }

  Future<void> _saveProgress({double? scrollOffset}) async {
    if (state.mangaId == null || state.currentChapter == null) return;

    try {
      final pageCount = state.isPdf
          ? state.pdfPageCount
          : (state.pages.isEmpty ? 1 : state.pages.length);
      final currentPage = (state.isPdf && state.pdfPageCount <= 0)
          ? state.currentPageIndex
          : state.currentPageIndex.clamp(0, pageCount > 0 ? pageCount - 1 : 0);
      final progressPercent = pageCount <= 1
          ? 0.0
          : currentPage / (pageCount - 1);
      final resolvedScrollOffset = scrollOffset ?? state.scrollOffset;
      final userId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
      final history = ReadingHistory(
        userId: userId,
        mangaId: state.mangaId!,
        chapterId: state.currentChapter!.id,
        chapterTitle: state.currentChapter?.title,
        lastPageIndex: currentPage,
        totalPages: pageCount,
        updatedAt: DateTime.now(),
      );
      // Chỉ ghi vào SQLite (isSynced=0).
      // SyncService.syncPendingHistory() sẽ push lên Firestore khi có mạng.
      // Không gọi Firestore trực tiếp ở đây — tránh double-write.
      await DatabaseHelper.instance.saveHistory(history);
      await DatabaseHelper.instance.saveReaderProgress(
        ReaderProgress(
          mangaId: state.mangaId!,
          chapterId: state.currentChapter!.id,
          pageIndex: currentPage,
          scrollOffset: resolvedScrollOffset,
          progressPercent: progressPercent,
          updatedAt: DateTime.now(),
        ),
      );
      await DatabaseHelper.instance.saveReadingActivity(
        ReadingActivity.create(
          userId: userId,
          mangaId: state.mangaId!,
          chapterId: state.currentChapter!.id,
          chapterTitle: state.currentChapter?.title,
          pageIndex: currentPage,
          totalPages: pageCount,
          progressPercent: progressPercent,
        ),
      );
    } catch (e) {
      debugPrint("Error saving history: $e");
    }
  }

  Future<bool> toggleBookmark() async {
    final mangaId = state.mangaId;
    final chapter = state.currentChapter;
    if (mangaId == null || chapter == null) return false;

    final existing = await DatabaseHelper.instance.getBookmarkForPage(
      mangaId: mangaId,
      chapterId: chapter.id,
      pageIndex: state.currentPageIndex,
    );

    if (existing != null) {
      await DatabaseHelper.instance.deleteBookmark(existing.id);
      state = state.copyWith(isCurrentPageBookmarked: false);
      return false;
    }

    final now = DateTime.now();
    await DatabaseHelper.instance.saveBookmark(
      ReaderBookmark(
        id: '$mangaId-${chapter.id}-${state.currentPageIndex}',
        mangaId: mangaId,
        chapterId: chapter.id,
        pageIndex: state.currentPageIndex,
        scrollOffset: state.scrollOffset,
        createdAt: now,
        updatedAt: now,
      ),
    );
    state = state.copyWith(isCurrentPageBookmarked: true);
    return true;
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

  /// Đặt lại cờ hasReachedEnd
  void resetEndReached() {
    state = state.copyWith(hasReachedEnd: false);
  }

  /// Đặt lại cờ hasReachedStart
  void resetStartReached() {
    state = state.copyWith(hasReachedStart: false);
  }

  /// Tải chương tiếp theo một cách mượt mà không cần load lại trang
  Future<void> loadNextChapter() async => _loadAdjacentChapter(isNext: true);

  /// Tải chương trước đó một cách mượt mà không cần load lại trang
  Future<void> loadPrevChapter() async => _loadAdjacentChapter(isNext: false);

  Future<void> _loadAdjacentChapter({required bool isNext}) async {
    // Ngăn chặn gọi nhiều lần
    if (isNext && state.isLoadingNextChapter) return;
    if (!isNext && state.isLoadingPrevChapter) return;

    final targetChapterId = isNext ? getNextChapterId() : getPrevChapterId();
    if (targetChapterId == null) {
      state = isNext
          ? state.copyWith(hasReachedEnd: true)
          : state.copyWith(hasReachedStart: true);
      return;
    }

    state = isNext
        ? state.copyWith(isLoadingNextChapter: true, hasReachedEnd: false)
        : state.copyWith(isLoadingPrevChapter: true, hasReachedStart: false);

    void resetLoadingState() {
      state = isNext
          ? state.copyWith(isLoadingNextChapter: false)
          : state.copyWith(isLoadingPrevChapter: false);
    }

    try {
      // 0. Kiểm tra Cache ổ cứng (Fast load nếu đã prefetch hoặc đọc trước đó)
      final cachedPages = await ArchiveImageExtractor.getCachedExtractedPages(targetChapterId);
      if (cachedPages != null && cachedPages.isNotEmpty) {
        debugPrint('⚡ Fast adjacent chapter load from extracted cache: $targetChapterId');
        final targetChapter = state.chapters.firstWhereOrNull((c) => c.id == targetChapterId);
        state = state.copyWith(
          currentChapter: targetChapter,
          pages: cachedPages,
          isNovel: false,
          isPdf: false,
          clearEpubBytes: true,
          clearPdfBytes: true,
          clearErrorMessage: true,
          pdfPageCount: 0,
          currentPageIndex: isNext ? 0 : cachedPages.length - 1,
          scrollOffset: 0,
          hasReachedEnd: isNext ? false : state.hasReachedEnd,
          hasReachedStart: !isNext ? false : state.hasReachedStart,
        );
        resetLoadingState();
        _saveProgress();
        _refreshBookmarkState();
        if (state.mangaId != null && targetChapter != null) {
          InteractionService.instance.incrementChapterView(state.mangaId!, targetChapter.id);
        }
        return;
      }

      // 1. Kiểm tra Ngoại tuyến trước và Tải nội dung
      Uint8List? fileBytes;
      final downloadInfo = await DatabaseHelper.instance.getDownload(
        targetChapterId,
      );

      if (downloadInfo != null) {
        final localPath = _readString(downloadInfo, 'localPath');
        final downloadMangaId = _readString(downloadInfo, 'mangaId');
        if (localPath.isEmpty) {
          await DatabaseHelper.instance.deleteDownload(targetChapterId);
          if (downloadMangaId.isNotEmpty) {
            await DownloadCache.instance.removeChapter(
              targetChapterId,
              downloadMangaId,
            );
          }
          fileBytes = null;
        } else {
          final file = File(localPath);
          if (await file.exists()) {
            if (kDebugMode) {
              debugPrint(
                '📂 Đọc chương ${isNext ? "TIẾP THEO" : "TRƯỚC"} từ cục bộ: $localPath',
              );
            }
            try {
              fileBytes = await file.readAsBytes();
            } catch (e) {
              if (kDebugMode) debugPrint('⚠️ Error reading local file: $e');
            }
          } else {
            await DatabaseHelper.instance.deleteDownload(targetChapterId);
            if (downloadMangaId.isNotEmpty) {
              await DownloadCache.instance.removeChapter(
                targetChapterId,
                downloadMangaId,
              );
            }
          }
        }
      }

      // 2. Nếu không tìm thấy cục bộ, hãy tải trực tuyến
      if (fileBytes == null) {
        if (kDebugMode) {
          debugPrint(
            '🌐 Tải chương ${isNext ? "TIẾP THEO" : "TRƯỚC"} từ Drive',
          );
        }
        fileBytes = await DriveService.instance.downloadFile(targetChapterId);
      }

      if (fileBytes == null) {
        resetLoadingState();
        return;
      }

      // Tìm siêu dữ liệu chương
      final targetChapter = state.chapters.firstWhereOrNull(
        (c) => c.id == targetChapterId,
      );

      // --- Trường hợp EPUB (Truyện chữ) ---
      final fileType = targetChapter?.fileType ?? 'zip';
      if (fileType == 'epub') {
        state = state.copyWith(
          currentChapter: targetChapter,
          epubBytes: fileBytes,
          clearPdfBytes: true,
          clearErrorMessage: true,
          isPdf: false,
          isNovel: true,
          pages: const [],
          pdfPageCount: 0,
          currentPageIndex: 0,
          scrollOffset: 0,
          hasReachedEnd: isNext ? false : state.hasReachedEnd,
          hasReachedStart: !isNext ? false : state.hasReachedStart,
        );
        resetLoadingState();
        _saveProgress();
        _refreshBookmarkState();
        if (state.mangaId != null && targetChapter != null) {
          InteractionService.instance.incrementChapterView(
            state.mangaId!,
            targetChapter.id,
          );
        }
        return;
      }

      // --- Trường hợp Manga (Truyện tranh: PDF / ZIP / CBZ) ---
      if (fileType == 'pdf') {
        state = state.copyWith(
          currentChapter: targetChapter,
          pages: const [],
          isNovel: false,
          isPdf: true,
          clearEpubBytes: true,
          clearErrorMessage: true,
          pdfBytes: fileBytes,
          pdfPageCount: 0,
          currentPageIndex: 0,
          scrollOffset: 0,
          hasReachedEnd: isNext ? false : state.hasReachedEnd,
          hasReachedStart: !isNext ? false : state.hasReachedStart,
        );
        resetLoadingState();
      } else {
        final images = await _extractImagesFromZip(fileBytes, targetChapterId);
        if (images.isEmpty) {
          resetLoadingState();
          return;
        }
        state = state.copyWith(
          currentChapter: targetChapter,
          pages: images,
          isNovel: false,
          isPdf: false,
          clearEpubBytes: true,
          clearPdfBytes: true,
          clearErrorMessage: true,
          pdfPageCount: 0,
          currentPageIndex: isNext ? 0 : images.length - 1,
          scrollOffset: 0,
          hasReachedEnd: isNext ? false : state.hasReachedEnd,
          hasReachedStart: !isNext ? false : state.hasReachedStart,
        );
        resetLoadingState();
      }

      // Lưu tiến trình cho chương mới
      _saveProgress();
      _refreshBookmarkState();

      // Tăng lượt xem
      if (state.mangaId != null && targetChapter != null) {
        InteractionService.instance.incrementChapterView(
          state.mangaId!,
          targetChapter.id,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading adjacent chapter: $e');
      resetLoadingState();
    }
  }

  Future<bool> toggleFollow() async {
    final user = FirebaseAuth.instance.currentUser;
    final mangaId = state.mangaId;
    if (user == null) {
      throw Exception('Bạn cần đăng nhập để theo dõi truyện');
    }
    if (mangaId == null || mangaId.isEmpty) {
      throw Exception('Không xác định được truyện');
    }

    final followService = FollowService();
    final isFollowed = await followService.isFollowing(mangaId).first;

    if (isFollowed) {
      await followService.unfollowManga(mangaId);
      state = state.copyWith(isFollowed: false);
      return false;
    }

    final comic =
        state.manga ??
        DriveService.instance.getMangaById(mangaId) ??
        (await DriveService.instance.getMangas()).firstWhereOrNull(
          (c) => c.id == mangaId,
        );
    if (comic == null) {
      throw Exception('Thiếu thông tin truyện để theo dõi');
    }

    await followService.followManga(
      mangaId: mangaId,
      title: comic.title,
      coverUrl: comic.coverFileId,
    );
    state = state.copyWith(isFollowed: true, manga: comic);
    return true;
  }

  Future<void> toggleLike() async {
    final mangaId = state.mangaId;
    if (mangaId == null || mangaId.isEmpty) return;
    final newIsLiked = !state.isLiked;
    // Cập nhật UI ngay lập tức
    state = state.copyWith(isLiked: newIsLiked);
    // Persist lên Firestore
    try {
      if (newIsLiked) {
        await InteractionService.instance.likeManga(mangaId);
      } else {
        await InteractionService.instance.unlikeManga(mangaId);
      }
    } catch (e) {
      // Rollback UI nếu Firestore lỗi
      state = state.copyWith(isLiked: !newIsLiked);
      debugPrint('toggleLike error: $e');
    }
  }
}
