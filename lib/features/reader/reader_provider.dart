import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdfx/pdfx.dart';
import '../../services/follow_service.dart';
import '../../services/interaction_service.dart';

import '../../core/utils/chapter_utils.dart';
import '../../core/utils/archive_image_extractor.dart';

import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../../data/database_helper.dart';
import '../../services/download_service.dart';
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
  final List<Uint8List> pages;
  final Uint8List? epubBytes; // Dữ liệu file EPUB cho truyện chữ
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

  const ReaderState({
    this.isLoading = true,
    this.isLoadingNextChapter = false,
    this.isLoadingPrevChapter = false,
    this.readingMode = ReadingMode.vertical,
    this.chapters = const [],
    this.currentChapter,
    this.pages = const [],
    this.epubBytes,
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
  });

  ReaderState copyWith({
    bool? isLoading,
    bool? isLoadingNextChapter,
    bool? isLoadingPrevChapter,
    ReadingMode? readingMode,
    List<CloudChapter>? chapters,
    CloudChapter? currentChapter,
    List<Uint8List>? pages,
    Uint8List? epubBytes,
    int? currentPageIndex,
    bool? showControls,
    String? errorMessage,
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
  }) {
    return ReaderState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingNextChapter: isLoadingNextChapter ?? this.isLoadingNextChapter,
      isLoadingPrevChapter: isLoadingPrevChapter ?? this.isLoadingPrevChapter,
      readingMode: readingMode ?? this.readingMode,
      chapters: chapters ?? this.chapters,
      currentChapter: currentChapter ?? this.currentChapter,
      pages: pages ?? this.pages,
      epubBytes: epubBytes ?? this.epubBytes,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      showControls: showControls ?? this.showControls,
      errorMessage: errorMessage ?? this.errorMessage,
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
    );
  }
}

final readerProvider =
    NotifierProvider.autoDispose<ReaderNotifier, ReaderState>(
      ReaderNotifier.new,
    );

class ReaderNotifier extends AutoDisposeNotifier<ReaderState> {
  /// Token dùng để huỷ render PDF cũ khi load chương mới.
  /// Mỗi lần load tăng lên 1 — background render kiểm tra token này trước khi emit.
  int _loadToken = 0;

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

  int _restorePageIndex(ReaderProgress? progress, int pageCount) {
    if (progress == null || pageCount <= 0) return 0;
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
          isNovel: true,
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
        // PDF: Hiển thị ngay từ trang 1, render phần còn lại ngầm
        final token = ++_loadToken;
        final completer = _PdfCompleter();

        // ignore: unawaited_futures
        _streamPdfPages(
          fileBytes,
          token,
          onFirstPage: (pages) {
            if (_loadToken != token) return;
            state = state.copyWith(
              isLoading: false,
              pages: pages,
              currentPageIndex: _restorePageIndex(savedProgress, pages.length),
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
            completer.complete();
          },
          onMorePages: (pages) {
            if (_loadToken == token) state = state.copyWith(pages: pages);
          },
          onDone: () => completer.complete(), // An toàn nếu trang đầu thất bại
        );
        await completer.future; // Chờ cho đến khi trang 1 hiển thị
      } else {
        // ZIP / CBZ: Trích xuất ảnh ngay
        final images = await _extractImagesFromZip(fileBytes);
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
              // Kiểm tra xem có nằm chung thư mục không (Kiểm tra chứa đơn giản)
              return path.contains(parentDir);
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
  void _preloadNextChapter(
    String currentChapterId,
    List<CloudChapter> allChapters,
    String mangaId,
    CloudManga? manga,
  ) {
    try {
      final currentIndex = allChapters.indexWhere(
        (c) => c.id == currentChapterId,
      );
      if (currentIndex != -1 && currentIndex > 0) {
        // Chương tiếp theo là chương có index nhỏ hơn (vì danh sách sắp xếp giảm dần theo thời gian/tên)
        // Lưu ý: Tùy theo cách sắp xếp của Waka, đôi khi chapter tiếp theo lại là currentIndex + 1.
        // Nhưng trong dự án này (Dựa theo nextChapter) nó là index - 1
        final nextChapter = allChapters[currentIndex - 1];

        // Kiểm tra xem đã tải chưa
        DatabaseHelper.instance.isChapterDownloaded(nextChapter.id).then((
          isDownloaded,
        ) {
          if (!isDownloaded) {
            debugPrint('📥 Preloading next chapter silently: ');
            DownloadService.instance.addToQueue(
              chapterId: nextChapter.id,
              mangaId: mangaId,
              mangaTitle: manga?.title ?? 'Unknown Manga',
              chapterTitle: nextChapter.title,
              fileType: nextChapter.fileType,
              mangaInfo: manga != null
                  ? Manga(
                      id: manga.id,
                      title: manga.title,
                      author: manga.author,
                      description: manga.description,
                      coverUrl: manga.coverFileId,
                      genres: const [],
                    )
                  : null,
              isSilent: true, // Ẩn notification
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Preload next chapter error: ');
    }
  }

  /// CHẾ ĐỘ TRỰC TUYẾN: Lấy từ Drive
  Future<void> _loadOnlineChapter(String chapterId, {String? mangaId}) async {
    // ========================================
    // TỐI ƯU HÓA: Gọi API song song (Parallel API Calls)
    // Chạy song song các tác vụ độc lập (~2s)
    // ========================================

    // Giai đoạn 1: Bắt đầu tải file ngay lập tức trong khi lấy metadata
    // Hai tác vụ này độc lập nên có thể chạy song song
    final downloadFuture = DriveService.instance.downloadFile(chapterId);
    final metaFuture = mangaId == null || mangaId.isEmpty
        ? DriveService.instance.getFile(chapterId)
        : Future<Map<String, dynamic>?>.value(null);

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

    // Giai đoạn 2: Sau khi có mangaId, tải danh sách chương và thông tin truyện song song
    // trong khi việc tải file vẫn đang chạy ngầm
    final chaptersFuture = DriveService.instance.getChapters(mangaId);
    final comicsFuture = DriveService.instance.getMangas();

    // Kiểm tra trạng thái theo dõi song song (không chặn)
    Future<bool> followFuture = Future.value(false);
    if (FirebaseAuth.instance.currentUser != null) {
      final followService = FollowService();
      followFuture = followService.isFollowing(mangaId).first;
    }

    // Chờ tất cả các tác vụ song song hoàn tất
    final chapters = await chaptersFuture;
    final comics = await comicsFuture;
    final fileBytes = await downloadFuture;
    final followed = await followFuture;

    // Tìm chương hiện tại trong danh sách
    final fileName = fileMeta == null ? '' : _readString(fileMeta, 'name');
    final currentChapter =
        chapters.firstWhereOrNull((c) => c.id == chapterId) ??
        CloudChapter(
          id: chapterId,
          title: fileName.isEmpty ? 'Chương hiện tại' : fileName,
          fileId: chapterId,
          fileType: _fileTypeFromName(fileName),
          sizeBytes: fileMeta == null ? 0 : _readInt(fileMeta, 'size'),
          uploadedAt: DateTime.now(),
        );

    // Kiểm tra file tải về
    if (fileBytes == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi tải nội dung chương truyện',
      );
      return;
    }

    // Giai đoạn 3: Xử lý nội dung theo loại file
    final fileType = currentChapter.fileType;
    final fetchedManga = comics.firstWhereOrNull((c) => c.id == mangaId);
    final savedProgress = await _loadSavedProgress(mangaId, chapterId);
    final baseState = state.copyWith(
      isLoading: false,
      chapters: chapters,
      currentChapter: currentChapter,
      currentPageIndex: 0,
      scrollOffset: savedProgress?.scrollOffset ?? 0,
      isFollowed: followed,
      isLiked: false,
      mangaId: mangaId,
      manga: fetchedManga,
    );

    // --- Trường hợp EPUB (Truyện chữ) ---
    if (fileType == 'epub') {
      state = baseState.copyWith(
        epubBytes: fileBytes,
        isNovel: true,
        pages: const [],
      );
      _saveProgress();
      _refreshBookmarkState();
      InteractionService.instance.incrementChapterView(mangaId, chapterId);

      // BẮT ĐẦU TÍNH NĂNG 3: PRELOAD NEXT CHAPTER
      _preloadNextChapter(chapterId, chapters, mangaId, fetchedManga);
      return;
    }

    // --- Trường hợp Manga (Truyện tranh: PDF / ZIP / CBZ) ---
    if (fileType == 'pdf') {
      // PDF: Hiển thị trang 1 ngay, render phần còn lại ngầm
      final token = ++_loadToken;
      final completer = _PdfCompleter();

      // ignore: unawaited_futures
      _streamPdfPages(
        fileBytes,
        token,
        onFirstPage: (pages) {
          if (_loadToken != token) return;
          state = baseState.copyWith(
            pages: pages,
            isNovel: false,
            epubBytes: null,
            currentPageIndex: _restorePageIndex(savedProgress, pages.length),
          );
          completer.complete();
        },
        onMorePages: (pages) {
          if (_loadToken == token) state = state.copyWith(pages: pages);
        },
        onDone: () => completer.complete(),
      );
      await completer.future;
    } else {
      final images = await _extractImagesFromZip(fileBytes);
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
        epubBytes: null,
        currentPageIndex: _restorePageIndex(savedProgress, images.length),
      );
    }

    // Lưu lịch sử đọc (chạy ngầm, không chặn UI)
    _saveProgress();
    _refreshBookmarkState();

    // Tăng lượt xem (chạy ngầm)
    InteractionService.instance.incrementChapterView(mangaId, chapterId);

    // Tải trước các chương liền kề (Prefetch) để chuyển trang mượt mà
    _prefetchAdjacentChapters();
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

  /// Tải trước chương trước và sau chạy ngầm để tăng tốc độ chuyển chương
  void _prefetchAdjacentChapters() {
    // Chạy trong microtask để không chặn luồng chính
    Future.microtask(() async {
      final nextId = getNextChapterId();
      final prevId = getPrevChapterId();

      // Tải và quên (Fire and forget) - kết quả sẽ được lưu vào bộ nhớ tạm bởi DriveService
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

  // Trích xuất ảnh từ tệp ZIP/CBZ — chạy trong isolate để không block UI thread.
  // CBZ lớn (50MB+) decode tốn CPU, dùng compute() tách sang isolate riêng.
  Future<List<Uint8List>> _extractImagesFromZip(Uint8List fileBytes) async {
    try {
      return await ArchiveImageExtractor.extract(fileBytes);
    } catch (e) {
      debugPrint('ZIP extraction error: $e');
      return [];
    }
  }

  /// Hiển thị trang 1 ngay, render phần còn lại của PDF ngầm trong background.
  /// [token]: nếu _loadToken thay đổi thì huỷ render — tránh memory leak khi thậ đọc.
  Future<void> _streamPdfPages(
    Uint8List fileBytes,
    int token, {
    required void Function(List<Uint8List> pages) onFirstPage,
    required void Function(List<Uint8List> pages) onMorePages,
    required void Function() onDone,
  }) async {
    PdfDocument? document;
    try {
      document = await PdfDocument.openData(fileBytes);
      final count = document.pagesCount;
      if (count == 0) {
        await document.close();
        onDone();
        return;
      }

      // Chuẩn bị mảng có đú số phần tử, bản đầu đều rỗng
      final pages = List<Uint8List>.generate(count, (_) => Uint8List(0));

      // Bước 1: Render trang 1 — gọi ngay, trả về cho UI
      final p1 = await document.getPage(1);
      final img1 = await p1.render(
        width: p1.width * 1.5,
        height: p1.height * 1.5,
        format: PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
        quality: 85,
      );
      await p1.close();

      if (img1 == null || _loadToken != token) {
        await document.close();
        onDone();
        return;
      }

      pages[0] = img1.bytes;
      onFirstPage(List<Uint8List>.from(pages)); // UI hiển thị ngay!
      debugPrint(
        '⚡ PDF trang 1 hiển thị (tổng $count trang, render ngầm phần còn lại)',
      );

      // Bước 2: Render các trang tiếp theo ngầm
      for (int i = 1; i < count; i++) {
        if (_loadToken != token) break; // Load mới đã được kích hoạt, dừng
        final page = await document.getPage(i + 1);
        final img = await page.render(
          width: page.width * 1.5,
          height: page.height * 1.5,
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
          quality: 85,
        );
        await page.close();
        if (img != null) pages[i] = img.bytes;

        // Cập nhật state mỗi 5 trang hoặc trang cuối — giảm rebuild
        if (((i + 1) % 5 == 0 || i == count - 1) && _loadToken == token) {
          onMorePages(List<Uint8List>.from(pages));
        }
      }

      await document.close();
      onDone();
      debugPrint('✅ PDF render xong $count trang');
    } catch (e) {
      debugPrint('PDF stream error: $e');
      try {
        await document?.close();
      } catch (_) {}
      onDone();
    }
  }

  // So sánh chuỗi đơn giản cho tên chương/trang — dùng _naturalSort trực tiếp
  // [Dead code đã xóa: _compareChapterNames, shortChapterSort]

  void toggleControls() {
    state = state.copyWith(showControls: !state.showControls);
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
    _saveProgress();
    _refreshBookmarkState();
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
      final pageCount = state.pages.isEmpty ? 1 : state.pages.length;
      final currentPage = state.currentPageIndex.clamp(0, pageCount - 1);
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
      // 1. Kiểm tra Ngoại tuyến trước và Tải nội dung
      Uint8List? fileBytes;
      final downloadInfo = await DatabaseHelper.instance.getDownload(
        targetChapterId,
      );

      if (downloadInfo != null) {
        final localPath = _readString(downloadInfo, 'localPath');
        if (localPath.isEmpty) {
          await DatabaseHelper.instance.deleteDownload(targetChapterId);
          resetLoadingState();
          return;
        }
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
          isNovel: true,
          pages: const [],
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
        final token = ++_loadToken;
        final completer = _PdfCompleter();
        // ignore: unawaited_futures
        _streamPdfPages(
          fileBytes,
          token,
          onFirstPage: (pages) {
            if (_loadToken != token) return;
            state = state.copyWith(
              currentChapter: targetChapter,
              pages: pages,
              isNovel: false,
              epubBytes: null,
              currentPageIndex: isNext ? 0 : pages.length - 1,
              scrollOffset: 0,
              hasReachedEnd: isNext ? false : state.hasReachedEnd,
              hasReachedStart: !isNext ? false : state.hasReachedStart,
            );
            resetLoadingState();
            completer.complete();
          },
          onMorePages: (pages) {
            if (_loadToken == token) {
              state = state.copyWith(
                pages: pages,
                currentPageIndex: isNext
                    ? state.currentPageIndex
                    : pages.length - 1,
              );
            }
          },
          onDone: () => completer.complete(),
        );
        await completer.future;
      } else {
        final images = await _extractImagesFromZip(fileBytes);
        if (images.isEmpty) {
          resetLoadingState();
          return;
        }
        state = state.copyWith(
          currentChapter: targetChapter,
          pages: images,
          isNovel: false,
          epubBytes: null,
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

  Future<void> toggleFollow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && state.currentChapter != null) {
      try {
        final fileMeta = await DriveService.instance.getFile(
          state.currentChapter!.id,
        );
        if (fileMeta != null &&
            fileMeta['parents'] != null &&
            _readFirstString(fileMeta, 'parents').isNotEmpty) {
          final mangaId = _readFirstString(fileMeta, 'parents');
          final followService = FollowService();

          // Lấy trạng thái hiện tại
          final isFollowed = await followService.isFollowing(mangaId).first;

          if (isFollowed) {
            await followService.unfollowManga(mangaId);
            state = state.copyWith(isFollowed: false);
          } else {
            // Ưu tiên lấy từ cache — không tốn network. Nếu cache rỗng mới gọi getMangas().
            final comic =
                DriveService.instance.getMangaById(mangaId) ??
                (await DriveService.instance.getMangas()).firstWhereOrNull(
                  (c) => c.id == mangaId,
                );

            if (comic != null) {
              await followService.followManga(
                mangaId: mangaId,
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

/// Helper: Completer an toàn — gọi complete() nhiều lần không throw.
/// Dùng cho _streamPdfPages để đảm bảo onFirstPage + onDone không xung đột.
class _PdfCompleter {
  final _c = Completer<void>();
  bool _done = false;

  Future<void> get future => _c.future;

  void complete() {
    if (!_done) {
      _done = true;
      _c.complete();
    }
  }
}
