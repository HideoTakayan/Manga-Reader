import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
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
import '../../services/level_service.dart';

import '../../core/utils/chapter_utils.dart';
import '../../core/utils/chapter_sort_helper.dart';
import '../../core/utils/archive_image_extractor.dart';

import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../../data/database_helper.dart';
import '../../data/models.dart';
import '../catalog/catalog_cache_service.dart';
import 'package:manga_reader/services/auth_service.dart';

enum ReadingMode { vertical, verticalGap, horizontal }

enum ReaderImageFit { width, height, screen, original, smart }

enum ReaderDirection { ltr, rtl }

enum ReaderBackground { black, gray, sepia, white }

/// Sơ đồ vùng chạm lật trang công thái học trong Reader
enum ReaderTapZone {
  default3Cols, // Mặc định: Trái lùi, Giữa menu, Phải tiến (hoặc ngược lại nếu RTL)
  oneHanded,    // Đọc 1 tay (L-Shape): 70% vùng dưới tiến, đỉnh lùi, tâm menu
  leftHanded,   // Thuận tay trái: Trái tiến, Phải lùi, Giữa menu
  kindle,       // Kindle-style: Nửa phải tiến, Nửa trái lùi (chạm 2 nửa, không cần vùng menu)
  swipeOnly,    // Chỉ vuốt: Chạm chỉ mở menu, chuyển trang bằng cách vuốt
}

/// Tuỳ chọn đảo ngược vùng chạm lật trang
enum ReaderTapZoneInvert {
  none,
  horizontal,
  vertical,
  both,
}

/// Chế độ đọc 2 trang song song (Dual-Page Spread) khi đọc ngang / màn hình tablet
enum ReaderDualPageMode {
  off,        // Trang đơn (Mặc định)
  dual,       // Trang đôi (Ghép Trang 1+2, 3+4, ...)
  dualCover,  // Trang đôi với Trang 1 làm bìa đơn (Trang 1, 2+3, 4+5, ...)
}

/// Khóa xoay màn hình
enum ReaderOrientation {
  auto,           // Tự do xoay theo thiết bị
  portrait,       // Khóa dọc
  landscape,      // Khóa ngang
  reversePortrait,// Khóa dọc ngược
}

/// Vị trí bắt đầu phóng to
enum ReaderZoomStart {
  auto,
  left,
  center,
  right,
}

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
  final ReaderTapZone tapZone;
  final ReaderTapZoneInvert tapZoneInvert;
  final ReaderDualPageMode dualPageMode;
  final bool
  isNovel; // Cờ xác định đây là truyện chữ (EPUB) hay truyện tranh (Ảnh)
  final bool isPdf; // Cờ xác định đây là định dạng PDF
  final ReaderOrientation orientation;
  final ReaderZoomStart zoomStart;

  // ===== BỘ LỌC ẢNH BAN ĐÊM =====
  /// Mức giảm sáng: 0.0 (tắt) → 0.85 (rất tối)
  final double dimLevel;
  /// Lọc ánh sáng xanh (bluelight): 0.0 (tắt) → 0.5 (vàng ấm mạnh)
  final double tintLevel;
  /// Đảo màu ảnh (Invert): hữu ích cho manga nền trắng khi đọc đêm
  final bool invertColors;
  /// Tự động cắt viền trắng thừa xung quanh trang truyện tranh (Smart Margin Crop)
  final bool cropBorders;
  /// Hiển thị thời gian thực và thông tin trang ở góc màn hình khi đọc toàn màn hình (Mini HUD)
  final bool showBatteryAndClock;
  /// Chế độ đọc ẩn danh (Incognito): Không lưu lịch sử, tiến trình đọc và không đồng bộ Cloud
  final bool isIncognito;
  /// Cho phép dùng phím Âm lượng (Volume Up/Down) để lật trang hoặc cuộn đọc
  final bool volumePageTurn;
  /// Đảo ngược chiều phím Âm lượng (Volume Up: tiếp theo, Volume Down: quay lại)
  final bool invertVolumeKeys;
  /// Xoay ảnh ngang 90 độ
  final bool rotateLandscapeImages;
  /// Áp dụng cài đặt riêng cho truyện hiện tại thay vì cài đặt chung
  final bool isPerMangaSettings;

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
    this.tapZone = ReaderTapZone.default3Cols,
    this.tapZoneInvert = ReaderTapZoneInvert.none,
    this.dualPageMode = ReaderDualPageMode.off,
    this.isNovel = false,
    this.isPdf = false,
    this.dimLevel = 0.0,
    this.tintLevel = 0.0,
    this.invertColors = false,
    this.cropBorders = false,
    this.showBatteryAndClock = true,
    this.isIncognito = false,
    this.volumePageTurn = true,
    this.invertVolumeKeys = false,
    this.rotateLandscapeImages = false,
    this.orientation = ReaderOrientation.auto,
    this.zoomStart = ReaderZoomStart.auto,
    this.isPerMangaSettings = false,
  });

  bool get isVerticalMode => readingMode == ReadingMode.vertical || readingMode == ReadingMode.verticalGap;
  bool get isGapMode => readingMode == ReadingMode.verticalGap;

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
    ReaderTapZone? tapZone,
    ReaderTapZoneInvert? tapZoneInvert,
    ReaderDualPageMode? dualPageMode,
    bool? isNovel,
    bool? isPdf,
    double? dimLevel,
    double? tintLevel,
    bool? invertColors,
    bool? cropBorders,
    bool? showBatteryAndClock,
    bool? isIncognito,
    bool? volumePageTurn,
    bool? invertVolumeKeys,
    bool? rotateLandscapeImages,
    ReaderOrientation? orientation,
    ReaderZoomStart? zoomStart,
    bool? isPerMangaSettings,
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
      tapZone: tapZone ?? this.tapZone,
      tapZoneInvert: tapZoneInvert ?? this.tapZoneInvert,
      dualPageMode: dualPageMode ?? this.dualPageMode,
      isNovel: isNovel ?? this.isNovel,
      isPdf: isPdf ?? this.isPdf,
      dimLevel: dimLevel ?? this.dimLevel,
      tintLevel: tintLevel ?? this.tintLevel,
      invertColors: invertColors ?? this.invertColors,
      cropBorders: cropBorders ?? this.cropBorders,
      showBatteryAndClock: showBatteryAndClock ?? this.showBatteryAndClock,
      isIncognito: isIncognito ?? this.isIncognito,
      volumePageTurn: volumePageTurn ?? this.volumePageTurn,
      invertVolumeKeys: invertVolumeKeys ?? this.invertVolumeKeys,
      rotateLandscapeImages: rotateLandscapeImages ?? this.rotateLandscapeImages,
      orientation: orientation ?? this.orientation,
      zoomStart: zoomStart ?? this.zoomStart,
      isPerMangaSettings: isPerMangaSettings ?? this.isPerMangaSettings,
    );
  }
}

final readerProvider =
    NotifierProvider.autoDispose<ReaderNotifier, ReaderState>(
      ReaderNotifier.new,
    );

class ReaderNotifier extends AutoDisposeNotifier<ReaderState> {
  SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> _getPrefs() async {
    return _cachedPrefs ??= await SharedPreferences.getInstance();
  }

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
    if (lower.endsWith('.cbt') || lower.endsWith('.tar')) return 'cbt';
    if (lower.endsWith('.cbr')) return 'cbr';
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

  int _restorePageIndex(
    ReaderProgress? progress,
    int? pageCount, {
    int? initialPageIndex,
  }) {
    if (initialPageIndex != null) {
      if (pageCount == null || pageCount <= 0) return initialPageIndex;
      return initialPageIndex.clamp(0, pageCount - 1);
    }
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

  Future<void> init(
    String chapterId, {
    String? mangaId,
    int? initialPageIndex,
  }) async {
    state = ReaderState(
      isLoading: true,
      readingMode: state.readingMode,
      imageFit: state.imageFit,
      direction: state.direction,
      background: state.background,
      tapZone: state.tapZone,
      tapZoneInvert: state.tapZoneInvert,
      dualPageMode: state.dualPageMode,
      dimLevel: state.dimLevel,
      tintLevel: state.tintLevel,
      invertColors: state.invertColors,
      cropBorders: state.cropBorders,
      showBatteryAndClock: state.showBatteryAndClock,
      volumePageTurn: state.volumePageTurn,
      invertVolumeKeys: state.invertVolumeKeys,
      rotateLandscapeImages: state.rotateLandscapeImages,
      orientation: state.orientation,
      zoomStart: state.zoomStart,
      isPerMangaSettings: state.isPerMangaSettings,
      isIncognito: state.isIncognito, // Giữ lại trạng thái Ẩn danh khi chuyển chương
    );

    // Load chế độ đọc đã lưu từ SharedPreferences
    final prefs = await _getPrefs();
    
    // Kiểm tra xem manga này có dùng cài đặt riêng không
    final isPerManga = mangaId != null && (prefs.getBool('manga_setting_${mangaId}_is_per_manga') ?? false);
    final prefix = isPerManga ? 'manga_setting_${mangaId}_' : 'reader_';

    final savedMode = prefs.getString('${prefix}reading_mode') ?? prefs.getString('reader_reading_mode') ?? prefs.getString('reading_mode');
    final savedImageFit = prefs.getString('${prefix}image_fit') ?? prefs.getString('reader_image_fit');
    final savedDirection = prefs.getString('${prefix}direction') ?? prefs.getString('reader_direction');
    final savedBackground = prefs.getString('${prefix}background') ?? prefs.getString('reader_background');
    final savedTapZone = prefs.getString('${prefix}tap_zone') ?? prefs.getString('reader_tap_zone');
    final savedTapZoneInvert = prefs.getString('${prefix}tap_zone_invert') ?? prefs.getString('reader_tap_zone_invert');
    final savedDimLevel = prefs.getDouble('${prefix}dim_level') ?? prefs.getDouble('reader_dim_level') ?? 0.0;
    final savedTintLevel = prefs.getDouble('${prefix}tint_level') ?? prefs.getDouble('reader_tint_level') ?? 0.0;
    final savedInvertColors = prefs.getBool('${prefix}invert_colors') ?? prefs.getBool('reader_invert_colors') ?? false;
    final savedCropBorders = prefs.getBool('${prefix}crop_borders') ?? prefs.getBool('reader_crop_borders') ?? false;
    final savedShowBatteryAndClock = prefs.getBool('${prefix}show_battery_and_clock') ?? prefs.getBool('reader_show_battery_and_clock') ?? true;
    final savedVolumePageTurn = prefs.getBool('${prefix}volume_page_turn') ?? prefs.getBool('reader_volume_page_turn') ?? true;
    final savedInvertVolumeKeys = prefs.getBool('${prefix}invert_volume_keys') ?? prefs.getBool('reader_invert_volume_keys') ?? false;
    final savedRotateLandscapeImages = prefs.getBool('${prefix}rotate_landscape_images') ?? prefs.getBool('reader_rotate_landscape_images') ?? false;
    final savedDualPageMode = prefs.getString('${prefix}dual_page_mode') ?? prefs.getString('reader_dual_page_mode');
    final savedOrientation = prefs.getString('${prefix}orientation') ?? prefs.getString('reader_orientation');
    final savedZoomStart = prefs.getString('${prefix}zoom_start') ?? prefs.getString('reader_zoom_start');

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
    final tapZone =
        ReaderTapZone.values.firstWhereOrNull(
          (zone) => zone.name == savedTapZone,
        ) ??
        ReaderTapZone.default3Cols;
    final tapZoneInvert =
        ReaderTapZoneInvert.values.firstWhereOrNull(
          (zone) => zone.name == savedTapZoneInvert,
        ) ??
        ReaderTapZoneInvert.none;
    final dualPageMode =
        ReaderDualPageMode.values.firstWhereOrNull(
          (m) => m.name == savedDualPageMode,
        ) ??
        ReaderDualPageMode.off;
    final orientation =
        ReaderOrientation.values.firstWhereOrNull(
          (o) => o.name == savedOrientation,
        ) ??
        ReaderOrientation.auto;
    final zoomStart =
        ReaderZoomStart.values.firstWhereOrNull(
          (z) => z.name == savedZoomStart,
        ) ??
        ReaderZoomStart.auto;
    state = state.copyWith(
      readingMode: mode,
      imageFit: imageFit,
      direction: direction,
      background: background,
      tapZone: tapZone,
      tapZoneInvert: tapZoneInvert,
      dualPageMode: dualPageMode,
      dimLevel: savedDimLevel,
      tintLevel: savedTintLevel,
      invertColors: savedInvertColors,
      cropBorders: savedCropBorders,
      showBatteryAndClock: savedShowBatteryAndClock,
      volumePageTurn: savedVolumePageTurn,
      invertVolumeKeys: savedInvertVolumeKeys,
      rotateLandscapeImages: savedRotateLandscapeImages,
      orientation: orientation,
      zoomStart: zoomStart,
      isPerMangaSettings: isPerManga,
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
        await _loadOfflineChapter(
          chapterId,
          preferredMangaId: mangaId,
          initialPageIndex: initialPageIndex,
        );
        return;
      }

      // ========================================
      // CHẾ ĐỘ TRỰC TUYẾN: Lấy từ Drive
      // ========================================
      debugPrint('🌐 CHẾ ĐỘ TRỰC TUYẾN: Tải từ Google Drive');
      await _loadOnlineChapter(
        chapterId,
        mangaId: mangaId,
        initialPageIndex: initialPageIndex,
      );
    } catch (e) {
      debugPrint('Error loading reader: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Đã xảy ra lỗi: $e',
      );
    }
  }

  /// Lấy danh sách tất cả các chương đã tải xuống của bộ truyện từ SQLite
  Future<List<CloudChapter>> _fetchLocalChapters(String mangaId) async {
    if (mangaId.isEmpty) return [];
    try {
      var downloadedMaps = await DatabaseHelper.instance.getDownloadsByManga(mangaId);
      if (downloadedMaps.isEmpty) {
        final all = await DatabaseHelper.instance.getAllDownloads();
        downloadedMaps = all.where((d) => _readString(d, 'mangaId') == mangaId).toList();
      }

      final Map<String, Map<String, dynamic>> uniqueDownloads = {};
      for (final d in downloadedMaps) {
        final chapterId = _readString(d, 'chapterId');
        if (chapterId.isEmpty) continue;
        if (!uniqueDownloads.containsKey(chapterId) ||
            _readInt(d, 'downloadDate') > _readInt(uniqueDownloads[chapterId]!, 'downloadDate')) {
          uniqueDownloads[chapterId] = d;
        }
      }

      final chapters = uniqueDownloads.values.map((d) {
        final chapterId = _readString(d, 'chapterId');
        final chapterTitle = _readString(d, 'chapterTitle');
        final localPath = _readString(d, 'localPath');
        final ext = localPath.toLowerCase();
        final fileType = _fileTypeFromName(ext);
        return CloudChapter(
          id: chapterId,
          title: chapterTitle.isEmpty ? chapterId : chapterTitle,
          fileId: chapterId,
          fileType: fileType,
          uploadedAt: DateTime.fromMillisecondsSinceEpoch(
            _readInt(d, 'downloadDate'),
          ),
          viewCount: 0,
        );
      }).toList();

      return ChapterSortHelper.sort(chapters);
    } catch (e) {
      debugPrint('⚠️ Error fetching local chapters: $e');
      return [];
    }
  }

  /// CHẾ ĐỘ NGOẠI TUYẾN: Đọc tệp cục bộ (NHANH!)
  Future<void> _loadOfflineChapter(
    String chapterId, {
    String? preferredMangaId,
    int? initialPageIndex,
  }) async {
    try {
      // 0. Kiểm tra Fast Cache (nếu người dùng vừa đọc và đã bung nén)
      final cachedPages = await ArchiveImageExtractor.getCachedExtractedPages(chapterId);
      if (cachedPages != null && cachedPages.isNotEmpty) {
        debugPrint('⚡ Fast load from extracted cache for offline chapter: $chapterId');
        String chapterTitle = 'Chương tải xuống';
        String resolvedMangaId = preferredMangaId ?? '';
        final downloadInfo = await DatabaseHelper.instance.getDownload(chapterId);
        if (downloadInfo != null) {
          chapterTitle = _readString(downloadInfo, 'chapterTitle');
          if (resolvedMangaId.isEmpty) {
            resolvedMangaId = _readString(downloadInfo, 'mangaId');
          }
        }

        final localChapters = await _fetchLocalChapters(resolvedMangaId);
        final localManga = await DatabaseHelper.instance.getLocalManga(resolvedMangaId);

        final currentChapter = localChapters.firstWhereOrNull((c) => c.id == chapterId) ??
            CloudChapter(
              id: chapterId,
              title: chapterTitle.isEmpty ? 'Chương tải xuống' : chapterTitle,
              fileId: chapterId,
              fileType: 'cbz',
              uploadedAt: DateTime.now(),
            );
        final savedProgress = await _loadSavedProgress(resolvedMangaId, chapterId);
        
        state = state.copyWith(
          isLoading: false,
          currentChapter: currentChapter,
          chapters: localChapters,
          manga: localManga != null
              ? CloudManga(
                  id: localManga.id,
                  title: localManga.title,
                  coverFileId: localManga.coverUrl,
                  author: localManga.author,
                  description: localManga.description,
                  updatedAt: DateTime.now(),
                  genres: localManga.genres,
                  status: 'Offline',
                  chapterOrder: [],
                  contentType: localManga.contentType,
                )
              : state.manga,
          currentPageIndex: _restorePageIndex(
            savedProgress,
            cachedPages.length,
            initialPageIndex: initialPageIndex,
          ),
          currentBlockIndex: _restoreBlockIndex(savedProgress),
          scrollOffset: savedProgress?.scrollOffset ?? 0,
          isLiked: false,
          mangaId: resolvedMangaId.isNotEmpty ? resolvedMangaId : preferredMangaId,
          clearErrorMessage: true,
          pages: cachedPages,
          isNovel: false,
          isPdf: false,
          clearLocalFilePath: true,
          pdfPageCount: 0,
        );
        
        _saveProgress();
        _refreshBookmarkState();
        _prefetchAdjacentChapters();
        if (resolvedMangaId.isNotEmpty) {
          _loadMetadataInBackground(resolvedMangaId, chapterId);
        }
        return;
      }

      // 1. Lấy thông tin tải xuống từ cơ sở dữ liệu
      final downloadInfo = await DatabaseHelper.instance.getDownload(chapterId);

      if (downloadInfo == null) {
        debugPrint(
          '⚠️ Không tìm thấy thông tin tải xuống, dự phòng sang trực tuyến',
        );
        await _loadOnlineChapter(chapterId, mangaId: preferredMangaId, initialPageIndex: initialPageIndex);
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
        await _loadOnlineChapter(chapterId, mangaId: preferredMangaId, initialPageIndex: initialPageIndex);
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
        await _loadOnlineChapter(chapterId, mangaId: preferredMangaId, initialPageIndex: initialPageIndex);
        return;
      }

      debugPrint('✅ Đã đọc file đường dẫn ($localPath)');

      // 3. Phát hiện loại tệp từ phần mở rộng + Magic Bytes
      final ext = localPath.toLowerCase();
      var fileType = _fileTypeFromName(ext);

      // Magic Bytes check để đảm bảo 100% chính xác kể cả khi tên file bị sai
      if (fileType == 'cbz' || fileType == 'zip' || fileType.isEmpty) {
        try {
          final headerBytes = await file.openRead(0, 8).first;
          if (headerBytes.length >= 4) {
            if (headerBytes[0] == 0x25 && headerBytes[1] == 0x50 &&
                headerBytes[2] == 0x44 && headerBytes[3] == 0x46) {
              fileType = 'pdf';
              debugPrint('🔍 Offline: Auto-detected PDF from magic bytes: $chapterId');
            } else if (headerBytes[0] == 0x50 && headerBytes[1] == 0x4B) {
              try {
                final zipBytes = await file.readAsBytes();
                final archive = ZipDecoder().decodeBytes(zipBytes);
                final mimeEntry = archive.findFile('mimetype');
                if (mimeEntry != null) {
                  final mimeContent = utf8.decode(
                    mimeEntry.content is List<int>
                        ? Uint8List.fromList(mimeEntry.content as List<int>)
                        : mimeEntry.content as Uint8List,
                    allowMalformed: true,
                  ).trim();
                  if (mimeContent.contains('epub')) {
                    fileType = 'epub';
                    debugPrint('🔍 Offline: Auto-detected EPUB from mimetype: $chapterId');
                  }
                }
              } catch (_) {}
            }
          }
        } catch (_) {}
      }

      final savedProgress = await _loadSavedProgress(mangaId, chapterId);

      // 3. Tải thông tin các chương offline và metadata truyện
      final localChapters = await _fetchLocalChapters(mangaId);
      final localManga = await DatabaseHelper.instance.getLocalManga(mangaId);

      final currentChapter = localChapters.firstWhereOrNull((c) => c.id == chapterId) ??
          CloudChapter(
            id: chapterId,
            title: chapterTitle.isEmpty ? 'Chapter' : chapterTitle,
            fileId: chapterId,
            fileType: fileType,
            uploadedAt: DateTime.now(),
            viewCount: 0,
          );

      final baseOfflineState = state.copyWith(
        isLoading: false,
        mangaId: mangaId,
        chapters: localChapters,
        currentChapter: currentChapter,
        manga: localManga != null
            ? CloudManga(
                id: localManga.id,
                title: localManga.title,
                coverFileId: localManga.coverUrl,
                author: localManga.author,
                description: localManga.description,
                updatedAt: DateTime.now(),
                genres: localManga.genres,
                status: 'Offline',
                chapterOrder: [],
                contentType: localManga.contentType,
              )
            : state.manga,
        clearErrorMessage: true,
      );

      // --- Trường hợp EPUB (Truyện chữ) ---
      if (fileType == 'epub') {
        state = baseOfflineState.copyWith(
          pages: const [],
          localFilePath: localPath,
          clearLocalFilePath: false,
          isNovel: true,
          isPdf: false,
          scrollOffset: savedProgress?.scrollOffset ?? 0,
        );
        debugPrint('✅ Reader hiển thị (OFFLINE EPUB MODE)');
        _saveProgress();
        _refreshBookmarkState();
        _prefetchAdjacentChapters();
        _loadMetadataInBackground(mangaId, chapterId);
        return;
      }

      // --- Trường hợp PDF ---
      if (fileType == 'pdf') {
        int restoredPage = _restorePageIndex(
          savedProgress,
          null,
          initialPageIndex: initialPageIndex,
        );
        if (restoredPage == 0 && initialPageIndex == null) {
          final prefs = await SharedPreferences.getInstance();
          restoredPage = prefs.getInt('pdf_page_$chapterId') ?? 0;
        }
        state = baseOfflineState.copyWith(
          pages: const [],
          localFilePath: localPath,
          clearLocalFilePath: false,
          isNovel: false,
          isPdf: true,
          pdfPageCount: 0,
          currentPageIndex: restoredPage,
          currentBlockIndex: _restoreBlockIndex(savedProgress),
          scrollOffset: savedProgress?.scrollOffset ?? 0,
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
        state = baseOfflineState.copyWith(
          pages: images,
          clearLocalFilePath: true,
          isPdf: false,
          isNovel: false,
          pdfPageCount: 0,
          currentPageIndex: _restorePageIndex(
            savedProgress,
            images.length,
            initialPageIndex: initialPageIndex,
          ),
          currentBlockIndex: _restoreBlockIndex(savedProgress),
          scrollOffset: savedProgress?.scrollOffset ?? 0,
        );
      }

      debugPrint('✅ Reader hiển thị (OFFLINE MODE)');
      _loadMetadataInBackground(mangaId, chapterId);
      _prefetchAdjacentChapters();

      // 6. Lưu lịch sử đọc
      _saveProgress();
      _refreshBookmarkState();
    } catch (e) {
      debugPrint('Error in offline mode: $e');
      // Fallback to online
      await _loadOnlineChapter(chapterId, mangaId: preferredMangaId, initialPageIndex: initialPageIndex);
    }
  }

  /// Tải ngầm chương tiếp theo để chuyển chương mượt mà

  /// CHẾ ĐỘ TRỰC TUYẾN: Lấy từ Drive
  Future<void> _loadOnlineChapter(
    String chapterId, {
    String? mangaId,
    int? initialPageIndex,
  }) async {
    // ========================================
    // TỐI ƯU HÓA TỐC ĐỘ: Bỏ qua tải và bung file nếu đã có sẵn trong Cache
    // ========================================
    final cachedPages = await ArchiveImageExtractor.getCachedExtractedPages(chapterId);
    if (cachedPages != null && cachedPages.isNotEmpty) {
      debugPrint('⚡ Fast load from extracted cache for online chapter: $chapterId');
      CloudChapter? knownChapter = state.chapters.firstWhereOrNull((c) => c.id == chapterId);
      if (knownChapter == null && mangaId != null && mangaId.isNotEmpty) {
        final chapters = await DriveService.instance.getChapters(mangaId);
        knownChapter = chapters.firstWhereOrNull((c) => c.id == chapterId);
      }

      final currentChapter = knownChapter ?? CloudChapter(
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
        currentPageIndex: _restorePageIndex(
          savedProgress,
          cachedPages.length,
          initialPageIndex: initialPageIndex,
        ),
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
    // TỐI ƯU HÓA: Tra cứu metadata từ RAM cache & Tải file trực tiếp
    // ========================================
    CloudChapter? knownChapter = state.chapters.firstWhereOrNull((c) => c.id == chapterId);
    if (knownChapter == null && mangaId != null && mangaId.isNotEmpty) {
      final chapters = await DriveService.instance.getChapters(mangaId);
      knownChapter = chapters.firstWhereOrNull((c) => c.id == chapterId);
    }

    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/temp_online_$chapterId');

    // Khởi chạy song song việc tải file và lấy metadata (nếu chưa có trong RAM)
    final hasTempCache = await tempFile.exists() && await tempFile.length() > 0;
    if (hasTempCache) {
      debugPrint('✅ Reusing smart temp cache for online chapter: $chapterId');
    }

    final downloadFuture = hasTempCache
        ? Future.value(true)
        : DriveService.instance.downloadFileToFile(chapterId, tempFile).catchError((e) {
            debugPrint('⚠️ Error downloading chapter to temp: $e');
            return false;
          });

    final metaFuture = knownChapter != null
        ? Future<Map<String, dynamic>?>.value(null)
        : DriveService.instance.getFile(chapterId).catchError((e) {
            debugPrint('⚠️ Error getting file metadata: $e');
            return null;
          });

    final results = await Future.wait([downloadFuture, metaFuture]);
    final downloadSuccess = results[0] as bool;
    final fileMeta = results[1] as Map<String, dynamic>?;

    final resolvedMangaId = mangaId != null && mangaId.isNotEmpty
        ? mangaId
        : fileMeta == null
        ? ''
        : _readFirstString(fileMeta, 'parents');

    if (resolvedMangaId.isEmpty && !downloadSuccess && knownChapter == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Không tìm thấy thông tin chương truyện',
      );
      return;
    }

    mangaId = resolvedMangaId.isNotEmpty ? resolvedMangaId : mangaId;

    // Kiểm tra file tải về
    if (!downloadSuccess || !await tempFile.exists()) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi tải nội dung chương truyện',
      );
      return;
    }
    final localPath = tempFile.path;

    // Tạo thông tin chương và nhận diện định dạng chuẩn xác
    final fileName = fileMeta == null ? '' : _readString(fileMeta, 'name');
    String detectedType = knownChapter?.fileType ?? '';
    if (detectedType.isEmpty || detectedType == 'zip' || detectedType == 'cbz') {
      final fromName = _fileTypeFromName(fileName);
      if (fromName != 'zip') {
        detectedType = fromName;
      } else if (knownChapter != null) {
        final fromTitle = _fileTypeFromName(knownChapter.title);
        if (fromTitle != 'zip') {
          detectedType = fromTitle;
        }
      }
    }
    if (detectedType.isEmpty) detectedType = 'zip';

    // Kiểm tra Magic Bytes nhị phân đầu file để đảm bảo 100% không nhầm lẫn PDF/EPUB thành CBZ/ZIP
    if (detectedType == 'cbz' || detectedType == 'zip') {
      try {
        final headerBytes = await tempFile.openRead(0, 8).first;
        if (headerBytes.length >= 4) {
          // %PDF -> % (0x25), P (0x50), D (0x44), F (0x46)
          if (headerBytes[0] == 0x25 &&
              headerBytes[1] == 0x50 &&
              headerBytes[2] == 0x44 &&
              headerBytes[3] == 0x46) {
            detectedType = 'pdf';
            debugPrint('🔍 Auto-detected PDF from magic bytes for chapter: $chapterId');
          } else if (headerBytes[0] == 0x50 && headerBytes[1] == 0x4B) {
            // PK header -> đây là ZIP-based format (có thể là EPUB)
            // Kiểm tra entry 'mimetype' để phân biệt EPUB với CBZ
            try {
              final zipBytes = await tempFile.readAsBytes();
              final archive = ZipDecoder().decodeBytes(zipBytes);
              final mimeEntry = archive.findFile('mimetype');
              if (mimeEntry != null) {
                final mimeContent = utf8.decode(
                  mimeEntry.content is List<int>
                      ? Uint8List.fromList(mimeEntry.content as List<int>)
                      : mimeEntry.content as Uint8List,
                  allowMalformed: true,
                ).trim();
                if (mimeContent.contains('epub')) {
                  detectedType = 'epub';
                  debugPrint('🔍 Auto-detected EPUB from mimetype entry for chapter: $chapterId');
                }
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    final currentChapter = knownChapter?.copyWith(fileType: detectedType) ??
        CloudChapter(
          id: chapterId,
          title: fileName.isEmpty ? 'Chương hiện tại' : fileName,
          fileId: chapterId,
          fileType: detectedType,
          sizeBytes: fileMeta == null ? 0 : _readInt(fileMeta, 'size'),
          uploadedAt: DateTime.now(),
        );

    // Giai đoạn 3: Xử lý nội dung theo loại file
    final fileType = detectedType;
    final savedProgress = await _loadSavedProgress(mangaId ?? '', chapterId);

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
      int restoredPage = _restorePageIndex(savedProgress, null);
      if (restoredPage == 0) {
        final prefs = await SharedPreferences.getInstance();
        restoredPage = prefs.getInt('pdf_page_$chapterId') ?? 0;
      }
      state = baseState.copyWith(
        pages: const [],
        isNovel: false,
        isPdf: true,
        clearLocalFilePath: false,
        localFilePath: localPath,
        pdfPageCount: 0,
        currentPageIndex: restoredPage,
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
        currentPageIndex: _restorePageIndex(
          savedProgress,
          images.length,
          initialPageIndex: initialPageIndex,
        ),
        currentBlockIndex: _restoreBlockIndex(savedProgress),
      );
    }

    // Lưu lịch sử đọc (chạy ngầm)
    _saveProgress();
    _refreshBookmarkState();

    // Khởi chạy việc tải danh sách chương & cập nhật lượt xem ngầm (không chặn UI)
    if (mangaId != null && mangaId.isNotEmpty) {
      _loadMetadataInBackground(mangaId, chapterId);
    }
  }

  /// Tải siêu dữ liệu chạy ngầm (không chặn UI)
  void _loadMetadataInBackground(String mangaId, String chapterId) {
    Future.microtask(() async {
      try {
        debugPrint('🔄 Loading metadata in background...');

        // 1. Tải thông tin truyện từ cache/local/Drive
        Future<CloudManga?> fetchManga() async {
          if (state.manga != null && state.manga!.id == mangaId) {
            return state.manga;
          }
          try {
            final cachedCatalog = await CatalogCacheService.instance.getCachedCatalog();
            final found = cachedCatalog.firstWhereOrNull((m) => m.id == mangaId);
            if (found != null) return found;
          } catch (_) {}

          final localManga = await DatabaseHelper.instance.getLocalManga(mangaId);
          if (localManga != null) {
            return CloudManga(
              id: localManga.id,
              title: localManga.title,
              coverFileId: localManga.coverUrl,
              author: localManga.author,
              description: localManga.description,
              updatedAt: DateTime.now(),
              genres: localManga.genres,
              status: 'Offline',
              chapterOrder: [],
              contentType: localManga.contentType,
            );
          }

          final mangas = await DriveService.instance.getMangas();
          return mangas.firstWhereOrNull((m) => m.id == mangaId);
        }

        final chaptersFuture = DriveService.instance.getChapters(mangaId);
        final mangaFuture = fetchManga();

        Future<bool> followFuture = Future.value(false);
        if (FirebaseAuth.instance.currentUser != null) {
          followFuture = FollowService.instance
              .isFollowing(mangaId)
              .first
              .timeout(const Duration(seconds: 3), onTimeout: () => false);
        }

        final results = await Future.wait([
          chaptersFuture,
          mangaFuture,
          followFuture,
        ]);

        final onlineChapters = results[0] as List<CloudChapter>;
        final manga = (results[1] as CloudManga?) ?? state.manga;
        final followed = results[2] as bool;

        // Gộp chương trực tuyến + ngoại tuyến
        final localChapters = await _fetchLocalChapters(mangaId);
        final mergedChapters = await ChapterUtils.mergeChapters(
          onlineChapters,
          localChapters,
          mangaId,
        );

        final finalChapters = mergedChapters.isNotEmpty
            ? mergedChapters
            : (onlineChapters.isNotEmpty
                ? onlineChapters
                : (state.chapters.isNotEmpty ? state.chapters : localChapters));

        final currentChapter = finalChapters.firstWhereOrNull(
              (c) => c.id == chapterId,
            ) ??
            state.currentChapter;

        // Cập nhật trạng thái với siêu dữ liệu đầy đủ
        state = state.copyWith(
          chapters: finalChapters,
          currentChapter: currentChapter,
          manga: manga,
          isFollowed: followed,
        );

        debugPrint('✅ Metadata loaded (${finalChapters.length} chapters)');

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
    
    // BUG-05 fix: skip EPUB prefetch — temp file path is not reused by the
    // EPUB reader flow, so downloading it here wastes bandwidth with no benefit.
    if (fileType == 'epub') return;
    
    if (fileType == 'pdf') {
      getTemporaryDirectory().then((tempDir) async {
        final tempFile = File('${tempDir.path}/temp_online_$chapterId');
        if (await tempFile.exists() && await tempFile.length() > 0) {
          debugPrint('✅ pdf chapter already in fast cache: $chapterId');
        } else {
          DriveService.instance.downloadFileToFile(chapterId, tempFile).then((success) {
            if (success) debugPrint('✅ Prefetched pdf chapter: $chapterId');
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
      unawaited(_saveProgress());
    }
  }

  Future<void> _saveSetting(String baseKey, dynamic value) async {
    final prefs = await _getPrefs();
    final String key;
    if (state.isPerMangaSettings && state.mangaId != null) {
      // Tạo per-manga key bằng cách strip prefix 'reader_' nếu có
      final stripped = baseKey.startsWith('reader_') ? baseKey.substring(7) : baseKey;
      key = 'manga_setting_${state.mangaId}_$stripped';
    } else {
      key = baseKey;
    }

    if (value is String) {
      await prefs.setString(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    }
  }

  void setPerMangaSettings(bool isPerManga) async {
    state = state.copyWith(isPerMangaSettings: isPerManga);
    if (state.mangaId != null) {
      final prefs = await _getPrefs();
      await prefs.setBool('manga_setting_${state.mangaId}_is_per_manga', isPerManga);
      if (isPerManga) {
        // Copy current global settings to per-manga
        await _saveSetting('reader_reading_mode', state.readingMode.name);
        await _saveSetting('reader_image_fit', state.imageFit.name);
        await _saveSetting('reader_direction', state.direction.name);
        await _saveSetting('reader_orientation', state.orientation.name);
        await _saveSetting('reader_zoom_start', state.zoomStart.name);
        await _saveSetting('reader_background', state.background.name);
        await _saveSetting('reader_tap_zone', state.tapZone.name);
        await _saveSetting('reader_tap_zone_invert', state.tapZoneInvert.name);
        await _saveSetting('reader_dual_page_mode', state.dualPageMode.name);
        await _saveSetting('reader_dim_level', state.dimLevel);
        await _saveSetting('reader_tint_level', state.tintLevel);
        await _saveSetting('reader_invert_colors', state.invertColors);
        await _saveSetting('reader_crop_borders', state.cropBorders);
        // NOTE: showBatteryAndClock, volumePageTurn, invertVolumeKeys cũng cần copy
        await _saveSetting('reader_show_battery_and_clock', state.showBatteryAndClock);
        await _saveSetting('reader_volume_page_turn', state.volumePageTurn);
        await _saveSetting('reader_invert_volume_keys', state.invertVolumeKeys);
        await _saveSetting('reader_rotate_landscape_images', state.rotateLandscapeImages);
      } else {
        // Clear all per-manga keys for this manga to avoid bloat
        final keys = prefs.getKeys().where((k) => k.startsWith('manga_setting_${state.mangaId}_'));
        for (final k in keys) {
          if (k != 'manga_setting_${state.mangaId}_is_per_manga') await prefs.remove(k);
        }
        // Restore global settings by calling init again
        if (state.currentChapter != null) {
          await init(state.currentChapter!.id, mangaId: state.mangaId, initialPageIndex: state.currentPageIndex);
        }
      }
    }
  }

  /// Cập nhật chế độ đọc và persist vào SharedPreferences để nhớ qua các lần mở app.
  void setReadingMode(ReadingMode mode) async {
    state = state.copyWith(readingMode: mode);
    await _saveSetting('reader_reading_mode', mode.name);
  }

  void setImageFit(ReaderImageFit fit) async {
    state = state.copyWith(imageFit: fit);
    await _saveSetting('reader_image_fit', fit.name);
  }

  void setDirection(ReaderDirection direction) async {
    state = state.copyWith(direction: direction);
    await _saveSetting('reader_direction', direction.name);
  }

  void setOrientation(ReaderOrientation orientation) async {
    state = state.copyWith(orientation: orientation);
    await _saveSetting('reader_orientation', orientation.name);
  }

  void setZoomStart(ReaderZoomStart zoomStart) async {
    state = state.copyWith(zoomStart: zoomStart);
    await _saveSetting('reader_zoom_start', zoomStart.name);
  }

  void setBackground(ReaderBackground background) async {
    state = state.copyWith(background: background);
    await _saveSetting('reader_background', background.name);
  }

  /// Giảm sáng tổng thể: 0.0 (tắt) → 0.85 (rất tối)
  void setDimLevel(double level) async {
    final clamped = level.clamp(0.0, 0.85);
    state = state.copyWith(dimLevel: clamped);
    await _saveSetting('reader_dim_level', clamped);
  }

  /// Lọc ánh sáng xanh: 0.0 (tắt) → 0.5 (vàng ấm mạnh)
  void setTintLevel(double level) async {
    final clamped = level.clamp(0.0, 0.5);
    state = state.copyWith(tintLevel: clamped);
    await _saveSetting('reader_tint_level', clamped);
  }

  /// Đảo màu ảnh – hữu ích cho manga nền trắng khi đọc ban đêm
  void setInvertColors(bool value) async {
    state = state.copyWith(invertColors: value);
    await _saveSetting('reader_invert_colors', value);
  }

  /// Tùy chỉnh sơ đồ vùng chạm lật trang
  void setTapZone(ReaderTapZone zone) async {
    state = state.copyWith(tapZone: zone);
    await _saveSetting('reader_tap_zone', zone.name);
  }

  void setTapZoneInvert(ReaderTapZoneInvert invert) async {
    state = state.copyWith(tapZoneInvert: invert);
    await _saveSetting('reader_tap_zone_invert', invert.name);
  }

  /// Tùy chỉnh chế độ đọc 2 trang song song (Dual-Page Spread)
  void setDualPageMode(ReaderDualPageMode mode) async {
    state = state.copyWith(dualPageMode: mode);
    await _saveSetting('reader_dual_page_mode', mode.name);
  }

  /// Tự động cắt viền trắng/khoảng lề thừa của trang truyện tranh
  Future<void> setCropBorders(bool crop) async {
    state = state.copyWith(cropBorders: crop);
    await _saveSetting('reader_crop_borders', crop);
  }

  Future<void> setShowBatteryAndClock(bool show) async {
    state = state.copyWith(showBatteryAndClock: show);
    await _saveSetting('reader_show_battery_and_clock', show);
  }

  Future<void> setVolumePageTurn(bool enabled) async {
    state = state.copyWith(volumePageTurn: enabled);
    await _saveSetting('reader_volume_page_turn', enabled);
  }

  Future<void> setInvertVolumeKeys(bool invert) async {
    state = state.copyWith(invertVolumeKeys: invert);
    await _saveSetting('reader_invert_volume_keys', invert);
  }

  Future<void> setRotateLandscapeImages(bool rotate) async {
    state = state.copyWith(rotateLandscapeImages: rotate);
    await _saveSetting('reader_rotate_landscape_images', rotate);
  }

  void toggleIncognito() {
    setIncognito(!state.isIncognito);
  }

  void setIncognito(bool value) {
    state = state.copyWith(isIncognito: value);
  }

  void onPageChanged(int index) {
    state = state.copyWith(currentPageIndex: index);
    unawaited(_saveProgress());
    _refreshBookmarkState();
    if (!state.isIncognito && state.isPdf && state.currentChapter != null) {
      _getPrefs().then((prefs) {
        prefs.setInt('pdf_page_${state.currentChapter!.id}', index);
      });
    }
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
    if (state.isIncognito) return;
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
      final userId = AuthService.safeUid;

      final futures = <Future<dynamic>>[];

      if (!state.mangaId!.startsWith('local_')) {
        final history = ReadingHistory(
          userId: userId,
          mangaId: state.mangaId!,
          chapterId: state.currentChapter!.id,
          chapterTitle: state.currentChapter?.title,
          lastPageIndex: currentPage,
          totalPages: pageCount,
          updatedAt: DateTime.now(),
        );
        futures.add(DatabaseHelper.instance.saveHistory(history));
      }

      // Tặng +10 EXP khi đọc đến cuối hoặc gần hết chap (chống spam)
      if (progressPercent >= 0.75 || currentPage >= pageCount - 1) {
        LevelService.instance.claimChapterExp(
          state.mangaId!,
          state.currentChapter!.id,
          chapterTitle: state.currentChapter?.title,
          genres: state.manga?.genres,
        );
      }

      futures.add(
        DatabaseHelper.instance.saveReaderProgress(
          ReaderProgress(
            mangaId: state.mangaId!,
            chapterId: state.currentChapter!.id,
            pageIndex: currentPage,
            blockIndex: state.currentBlockIndex,
            scrollOffset: resolvedScrollOffset,
            progressPercent: progressPercent,
            updatedAt: DateTime.now(),
          ),
        ),
      );

      futures.add(
        DatabaseHelper.instance.saveReadingActivity(
          ReadingActivity.create(
            userId: userId,
            mangaId: state.mangaId!,
            chapterId: state.currentChapter!.id,
            chapterTitle: state.currentChapter?.title,
            pageIndex: currentPage,
            totalPages: pageCount,
            progressPercent: progressPercent,
          ),
        ),
      );

      // Tự động đánh dấu chương đã đọc khi đọc đến trang cuối hoặc đạt >= 90%
      if (progressPercent >= 0.90 || (pageCount > 0 && currentPage >= pageCount - 1)) {
        futures.add(
          DatabaseHelper.instance.markChapterAsRead(
            mangaId: state.mangaId!,
            chapterId: state.currentChapter!.id,
            userId: userId,
          ),
        );
      }

      await Future.wait(futures);
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

  Future<ReaderBookmark?> getCurrentPageBookmark() async {
    final mangaId = state.mangaId;
    final chapter = state.currentChapter;
    if (mangaId == null || chapter == null) return null;

    return await DatabaseHelper.instance.getBookmarkForPage(
      mangaId: mangaId,
      chapterId: chapter.id,
      pageIndex: state.currentPageIndex,
    );
  }

  Future<void> saveBookmarkWithNote(String? note) async {
    final mangaId = state.mangaId;
    final chapter = state.currentChapter;
    if (mangaId == null || chapter == null) return;

    final existing = await DatabaseHelper.instance.getBookmarkForPage(
      mangaId: mangaId,
      chapterId: chapter.id,
      pageIndex: state.currentPageIndex,
    );

    final cleanNote = (note == null || note.trim().isEmpty) ? null : note.trim();
    final now = DateTime.now();

    if (existing != null) {
      await DatabaseHelper.instance.updateBookmarkNote(existing.id, cleanNote);
      state = state.copyWith(isCurrentPageBookmarked: true);
    } else {
      await DatabaseHelper.instance.saveBookmark(
        ReaderBookmark(
          id: '$mangaId-${chapter.id}-${state.currentPageIndex}',
          mangaId: mangaId,
          chapterId: chapter.id,
          pageIndex: state.currentPageIndex,
          scrollOffset: state.scrollOffset,
          note: cleanNote,
          createdAt: now,
          updatedAt: now,
        ),
      );
      state = state.copyWith(isCurrentPageBookmarked: true);
    }
  }

  Future<void> deleteBookmark(String id) async {
    await DatabaseHelper.instance.deleteBookmark(id);
    await _refreshBookmarkState();
  }

  Future<void> restoreBookmark(ReaderBookmark bookmark) async {
    await DatabaseHelper.instance.saveBookmark(bookmark);
    await _refreshBookmarkState();
  }

  Future<void> updateBookmarkNote(String id, String? note) async {
    final cleanNote = (note == null || note.trim().isEmpty) ? null : note.trim();
    await DatabaseHelper.instance.updateBookmarkNote(id, cleanNote);
    await _refreshBookmarkState();
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
    if (chapter.fileType != 'zip' &&
        chapter.fileType != 'cbz' &&
        chapter.fileType != 'cbt' &&
        chapter.fileType != 'cbr' &&
        chapter.fileType != 'tar') {
      return; // Chỉ auto-save truyện tranh
    }

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
        _prefetchAdjacentChapters();
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

      // Nhận diện định dạng chương chuẩn xác cho chương liền kề
      var detectedFileType = targetChapter?.fileType ?? 'zip';
      if (targetChapter != null) {
        final lowerTitle = targetChapter.title.toLowerCase();
        if (lowerTitle.endsWith('.epub')) {
          detectedFileType = 'epub';
        } else if (lowerTitle.endsWith('.pdf')) {
          detectedFileType = 'pdf';
        }
      }

      // Kiểm tra Magic Bytes nhị phân đầu file nếu chưa xác định chắc chắn
      if (detectedFileType == 'cbz' || detectedFileType == 'zip' || detectedFileType.isEmpty) {
        try {
          final headerBytes = await File(localPath).openRead(0, 8).first;
          if (headerBytes.length >= 4) {
            // %PDF -> % (0x25), P (0x50), D (0x44), F (0x46)
            if (headerBytes[0] == 0x25 &&
                headerBytes[1] == 0x50 &&
                headerBytes[2] == 0x44 &&
                headerBytes[3] == 0x46) {
              detectedFileType = 'pdf';
              debugPrint('🔍 Auto-detected PDF from magic bytes for adjacent chapter: $targetChapterId');
            } else if (headerBytes[0] == 0x50 && headerBytes[1] == 0x4B) {
              // PK header -> đây là ZIP-based format (có thể là EPUB)
              try {
                final zipBytes = await File(localPath).readAsBytes();
                final archive = ZipDecoder().decodeBytes(zipBytes);
                final mimeEntry = archive.findFile('mimetype');
                if (mimeEntry != null) {
                  final mimeContent = utf8.decode(
                    mimeEntry.content is List<int>
                        ? Uint8List.fromList(mimeEntry.content as List<int>)
                        : mimeEntry.content as Uint8List,
                    allowMalformed: true,
                  ).trim();
                  if (mimeContent.contains('epub')) {
                    detectedFileType = 'epub';
                    debugPrint('🔍 Auto-detected EPUB from mimetype for adjacent chapter: $targetChapterId');
                  }
                }
              } catch (_) {}
            }
          }
        } catch (_) {}
      }

      final resolvedTargetChapter = targetChapter?.copyWith(fileType: detectedFileType);

      // --- Trường hợp EPUB (Truyện chữ) ---
      if (detectedFileType == 'epub') {
        state = state.copyWith(
          currentChapter: resolvedTargetChapter,
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
        if (state.mangaId != null && resolvedTargetChapter != null) {
          InteractionService.instance.incrementChapterView(
            state.mangaId!,
            resolvedTargetChapter.id,
          );
        }
        return;
      }

      // --- Trường hợp Manga (Truyện tranh: PDF / ZIP / CBZ) ---
      if (detectedFileType == 'pdf') {
        state = state.copyWith(
          currentChapter: resolvedTargetChapter,
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
        // fall through to shared: _saveProgress / _refreshBookmarkState /
        // _prefetchAdjacentChapters / incrementChapterView
      } else {
        final images = await ArchiveImageExtractor.extract(localPath, targetChapterId);
        if (images.isEmpty) {
          resetLoadingState();
          return;
        }
        state = state.copyWith(
          currentChapter: resolvedTargetChapter,
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
      _prefetchAdjacentChapters();

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
    final isFollowed = await followService
        .isFollowing(mangaId)
        .first
        .timeout(const Duration(seconds: 4), onTimeout: () => state.isFollowed);

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
