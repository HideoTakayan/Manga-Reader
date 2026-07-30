import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/follow_service.dart';
import '../../services/interaction_service.dart';
import '../../services/download_cache.dart';
import '../../services/download_service.dart';

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
  final String? localFilePath; // Thay thế cho epubBytes và pdfBytes
  final int pdfPageCount; // Số trang của file PDF
  final int currentPageIndex;
  final int currentBlockIndex;
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
    this.localFilePath,
    this.pdfPageCount = 0,
    this.currentPageIndex = 0,
    this.currentBlockIndex = 0,
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
    String? localFilePath,
    bool clearLocalFilePath = false,
    int? pdfPageCount,
    int? currentPageIndex,
    int? currentBlockIndex,
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
      localFilePath: clearLocalFilePath ? null : (localFilePath ?? this.localFilePath),
      pdfPageCount: pdfPageCount ?? this.pdfPageCount,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      currentBlockIndex: currentBlockIndex ?? this.currentBlockIndex,
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

  int _restoreBlockIndex(ReaderProgress? progress) {
    if (progress == null) return 0;
    return progress.blockIndex;
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
          currentBlockIndex: _restoreBlockIndex(savedProgress),
          scrollOffset: savedProgress?.scrollOffset ?? 0,
          isLiked: false,
          mangaId: preferredMangaId,
          clearErrorMessage: true,
          pages: cachedPages,
          isNovel: false,
          isPdf: false,
          clearLocalFilePath: true,
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

      debugPrint('✅ Đã đọc file đường dẫn ($localPath)');

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
          localFilePath: localPath,
          clearLocalFilePath: false,
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
          localFilePath: localPath,
          clearLocalFilePath: false,
          clearErrorMessage: true,
          isNovel: false,
          isPdf: true,
          pdfPageCount: 0,
          currentPageIndex: _restorePageIndex(savedProgress, null),
          currentBlockIndex: _restoreBlockIndex(savedProgress),
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
        final images = await ArchiveImageExtractor.extract(localPath, chapterId);
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
          clearLocalFilePath: true,
          clearErrorMessage: true,
          isPdf: false,
          isNovel: false,
          pdfPageCount: 0,
          currentPageIndex: _restorePageIndex(savedProgress, images.length),
          currentBlockIndex: _restoreBlockIndex(savedProgress),
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
        currentBlockIndex: _restoreBlockIndex(savedProgress),
        scrollOffset: savedProgress?.scrollOffset ?? 0,
        isLiked: false,
        mangaId: mangaId,
        clearErrorMessage: true,
        pages: cachedPages,
        isNovel: false,
        isPdf: false,
        clearLocalFilePath: true,
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

    // Giai đoạn 1: Lấy metadata để biết mangaId (Nên làm trước khi download vào disk vì cần check lỗi sớm)
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

    // Giai đoạn 2: Tải file thẳng xuống đĩa cứng thay vì nhét vào RAM
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/temp_online_$chapterId');
    
    bool downloadSuccess = true;
    if (await tempFile.exists() && await tempFile.length() > 0) {
      debugPrint('✅ Reusing smart temp cache for online chapter: $chapterId');
    } else {
      downloadSuccess = await DriveService.instance.downloadFileToFile(
        chapterId, 
        tempFile
      );
    }

    // Kiểm tra file tải về
    if (!downloadSuccess || !await tempFile.exists()) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi tải nội dung chương truyện',
      );
      return;
    }
    final localPath = tempFile.path;

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
      currentBlockIndex: 0,
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
        localFilePath: localPath,
        clearLocalFilePath: false,
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
        clearLocalFilePath: false,
        localFilePath: localPath,
        pdfPageCount: 0,
        currentPageIndex: _restorePageIndex(savedProgress, null),
        currentBlockIndex: _restoreBlockIndex(savedProgress),
      );
    } else {
      final images = await ArchiveImageExtractor.extract(localPath, chapterId);
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
        clearLocalFilePath: true,
        pdfPageCount: 0,
        currentPageIndex: _restorePageIndex(savedProgress, images.length),
        currentBlockIndex: _restoreBlockIndex(savedProgress),
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

      if (nextId != null) _prefetchChapter(nextId);
      if (prevId != null) _prefetchChapter(prevId);
    });
  }

  void _prefetchChapter(String chapterId) {
    final chapter = state.chapters.firstWhereOrNull((c) => c.id == chapterId);
    if (chapter == null) return;
    
    final fileType = chapter.fileType;
    
    if (fileType == 'pdf' || fileType == 'epub') {
      getTemporaryDirectory().then((tempDir) async {
        final tempFile = File('${tempDir.path}/temp_online_$chapterId');
        if (await tempFile.exists() && await tempFile.length() > 0) {
          debugPrint('✅ $fileType chapter already in fast cache: $chapterId');
        } else {
          DriveService.instance.downloadFileToFile(chapterId, tempFile).then((success) {
            if (success) debugPrint('✅ Prefetched $fileType chapter: $chapterId');
          }).catchError((_) {});
        }
      });
    } else {
      ArchiveImageExtractor.getCachedExtractedPages(chapterId).then((cached) async {
        if (cached == null || cached.isEmpty) {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/temp_online_$chapterId');
          bool hasFile = await tempFile.exists() && await tempFile.length() > 0;
          if (!hasFile) {
            hasFile = await DriveService.instance.downloadFileToFile(chapterId, tempFile);
          }
          if (hasFile) {
            await _extractImagesFromZip(tempFile.path, chapterId);
            debugPrint('✅ Prefetched zip/cbz chapter: $chapterId');
          }
        } else {
          debugPrint('✅ Zip/cbz chapter already in fast cache: $chapterId');
        }
      }).catchError((_) {});
    }
  }

  // Trích xuất ảnh từ tệp ZIP/CBZ xuống ổ cứng (temp directory)
  Future<List<String>> _extractImagesFromZip(
    String localPath,
    String chapterId,
  ) async {
    try {
      return await ArchiveImageExtractor.extract(localPath, chapterId);
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

  void updateScrollPosition(double offset, int pageIndex, {int blockIndex = 0}) {
    if (pageIndex == state.currentPageIndex && blockIndex == state.currentBlockIndex) return;
    state = state.copyWith(scrollOffset: offset, currentPageIndex: pageIndex, currentBlockIndex: blockIndex);
    _refreshBookmarkState();
    unawaited(_saveProgress()); // Lưu tiến độ ngay khi cuộn để tránh mất data khi app crash
  }

  Future<void> saveScrollProgress(double offset, {int? pageIndex, int? blockIndex}) async {
    state = state.copyWith(
      scrollOffset: offset,
      currentPageIndex: pageIndex ?? state.currentPageIndex,
      currentBlockIndex: blockIndex ?? state.currentBlockIndex,
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
          blockIndex: state.currentBlockIndex,
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
  Future<void> loadNextChapter() async {
    await _autoSaveCurrentChapterOffline();
    await _loadAdjacentChapter(isNext: true);
  }

  /// Tải chương trước đó một cách mượt mà không cần load lại trang
  Future<void> loadPrevChapter() async => _loadAdjacentChapter(isNext: false);

  Future<void> _autoSaveCurrentChapterOffline() async {
    final chapter = state.currentChapter;
    final mangaId = state.mangaId;
    if (chapter == null || mangaId == null) return;
    if (state.localFilePath != null) return; // Đã là file offline
    if (chapter.fileType != 'zip' && chapter.fileType != 'cbz') return; // Chỉ auto-save truyện tranh

    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_online_${chapter.id}');
      if (await tempFile.exists() && await tempFile.length() > 0) {
        final manga = await DatabaseHelper.instance.getLocalManga(mangaId);
        if (manga != null) {
          await DownloadService.instance.saveTempAsOffline(
            chapterId: chapter.id,
            mangaId: mangaId,
            mangaTitle: manga.title,
            chapterTitle: chapter.title,
            fileType: chapter.fileType,
            tempFile: tempFile,
            mangaInfo: manga,
          );
        }
      }
    } catch (e) {
      debugPrint('Lỗi auto-save offline: $e');
    }
  }

  Future<void> _loadAdjacentChapter({required bool isNext}) async {
    // Ngăn chặn gọi nhiều lần
    if (isNext && state.isLoadingNextChapter) return;
    if (!isNext && state.isLoadingPrevChapter) return;

    final targetChapterId = isNext ? getNextChapterId() : getPrevChapterId();
    if (targetChapterId == null) {
      if (isNext) {
        state = state.copyWith(hasReachedEnd: true);
        await _autoSaveCurrentChapterOffline();
      } else {
        state = state.copyWith(hasReachedStart: true);
      }
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
          clearLocalFilePath: true,
          clearErrorMessage: true,
          pdfPageCount: 0,
          currentPageIndex: isNext ? 0 : cachedPages.length - 1,
          currentBlockIndex: 0,
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
      String? localPath;
      final downloadInfo = await DatabaseHelper.instance.getDownload(
        targetChapterId,
      );

      if (downloadInfo != null) {
        final path = _readString(downloadInfo, 'localPath');
        final downloadMangaId = _readString(downloadInfo, 'mangaId');
        if (path.isEmpty) {
          await DatabaseHelper.instance.deleteDownload(targetChapterId);
          if (downloadMangaId.isNotEmpty) {
            await DownloadCache.instance.removeChapter(
              targetChapterId,
              downloadMangaId,
            );
          }
          localPath = null;
        } else {
          final file = File(path);
          if (await file.exists()) {
            if (kDebugMode) {
              debugPrint(
                '📂 Đọc chương ${isNext ? "TIẾP THEO" : "TRƯỚC"} từ cục bộ: $path',
              );
            }
            localPath = path;
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
      if (localPath == null) {
        if (kDebugMode) {
          debugPrint(
            '🌐 Tải chương ${isNext ? "TIẾP THEO" : "TRƯỚC"} từ Drive',
          );
        }
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/temp_online_$targetChapterId');
        if (await tempFile.exists() && await tempFile.length() > 0) {
          debugPrint('✅ Reusing smart temp cache for adjacent chapter: $targetChapterId');
          localPath = tempFile.path;
        } else {
          final success = await DriveService.instance.downloadFileToFile(targetChapterId, tempFile);
          if (success) localPath = tempFile.path;
        }
      }

      if (localPath == null) {
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
          localFilePath: localPath,
          clearLocalFilePath: false,
          clearErrorMessage: true,
          isPdf: false,
          isNovel: true,
          pages: const [],
          pdfPageCount: 0,
          currentPageIndex: 0,
          currentBlockIndex: 0,
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
          clearLocalFilePath: false,
          clearErrorMessage: true,
          localFilePath: localPath,
          pdfPageCount: 0,
          currentPageIndex: 0,
          currentBlockIndex: 0,
          scrollOffset: 0,
          hasReachedEnd: isNext ? false : state.hasReachedEnd,
          hasReachedStart: !isNext ? false : state.hasReachedStart,
        );
        resetLoadingState();
      } else {
        final images = await _extractImagesFromZip(localPath, targetChapterId);
        if (images.isEmpty) {
          resetLoadingState();
          return;
        }
        state = state.copyWith(
          currentChapter: targetChapter,
          pages: images,
          isNovel: false,
          isPdf: false,
          clearLocalFilePath: true,
          localFilePath: null,
          clearErrorMessage: true,
          pdfPageCount: 0,
          currentPageIndex: isNext ? 0 : images.length - 1,
          currentBlockIndex: 0,
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
