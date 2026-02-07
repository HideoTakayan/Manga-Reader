import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../data/database_helper.dart';

/// Cache để track downloads từ file system (Mihon style)
///
/// Thay vì query database liên tục, ta scan file system và cache kết quả.
/// Cache được refresh mỗi 1 giờ hoặc khi có thay đổi.
class DownloadCache {
  static final DownloadCache instance = DownloadCache._init();
  DownloadCache._init();

  // Cache structure: mangaId -> Set<chapterId>
  final Map<String, Set<String>> _cache = {};

  // Timestamp của lần refresh cuối
  DateTime? _lastRefresh;

  // Refresh interval (1 giờ như Mihon)
  static const _refreshInterval = Duration(hours: 1);

  // Lock để tránh concurrent refresh
  bool _isRefreshing = false;

  // Stream để notify changes
  final _changesController = StreamController<void>.broadcast();
  Stream<void> get changes => _changesController.stream;

  /// Kiểm tra chapter đã download chưa
  ///
  /// [skipCache] = true: Scan file system trực tiếp (chậm nhưng chính xác)
  /// [skipCache] = false: Check cache (nhanh nhưng có thể outdated)
  Future<bool> isChapterDownloaded(
    String chapterId,
    String mangaId, {
    bool skipCache = false,
  }) async {
    if (skipCache) {
      // Scan file system trực tiếp
      return await _checkFileSystemDirect(chapterId, mangaId);
    }

    // Refresh cache nếu cần
    await _refreshCacheIfNeeded();

    // Check cache
    return _cache[mangaId]?.contains(chapterId) ?? false;
  }

  /// Lấy số lượng chapters đã download của một manga
  Future<int> getDownloadCount(String mangaId) async {
    await _refreshCacheIfNeeded();
    return _cache[mangaId]?.length ?? 0;
  }

  /// Lấy tổng số chapters đã download
  Future<int> getTotalDownloadCount() async {
    await _refreshCacheIfNeeded();
    int total = 0;
    for (final set in _cache.values) {
      total += set.length;
    }
    return total;
  }

  /// Lấy danh sách chapterIds đã download của một manga
  Future<Set<String>> getDownloadedChapterIds(String mangaId) async {
    await _refreshCacheIfNeeded();
    return _cache[mangaId] ?? {};
  }

  /// Thêm chapter vào cache (khi download xong)
  Future<void> addChapter(String chapterId, String mangaId) async {
    _cache.putIfAbsent(mangaId, () => {});
    _cache[mangaId]!.add(chapterId);
    _notifyChanges();
  }

  /// Xóa chapter khỏi cache (khi delete)
  Future<void> removeChapter(String chapterId, String mangaId) async {
    _cache[mangaId]?.remove(chapterId);
    if (_cache[mangaId]?.isEmpty ?? false) {
      _cache.remove(mangaId);
    }
    _notifyChanges();
  }

  /// Xóa tất cả chapters của một manga khỏi cache
  Future<void> removeManga(String mangaId) async {
    _cache.remove(mangaId);
    _notifyChanges();
  }

  /// Force refresh cache (scan lại file system)
  Future<void> invalidateCache() async {
    _lastRefresh = null;
    await refreshCache();
  }

  /// Refresh cache nếu đã quá thời gian
  Future<void> _refreshCacheIfNeeded() async {
    if (_lastRefresh == null ||
        DateTime.now().difference(_lastRefresh!) > _refreshInterval) {
      await refreshCache();
    }
  }

  /// Refresh cache (scan file system)
  Future<void> refreshCache() async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      debugPrint('🔄 DownloadCache: Refreshing cache...');

      // Clear cache cũ
      _cache.clear();

      // Lấy tất cả downloads từ database
      final downloads = await DatabaseHelper.instance.getAllDownloads();

      // Validate từng download (check file exists)
      final validDownloads = <Map<String, dynamic>>[];
      final invalidChapterIds = <String>[];

      for (final download in downloads) {
        final chapterId = download['chapterId'] as String;
        final mangaId = download['mangaId'] as String;
        final localPath = download['localPath'] as String?;

        if (localPath == null || localPath.isEmpty) {
          invalidChapterIds.add(chapterId);
          continue;
        }

        final file = File(localPath);
        if (await file.exists()) {
          validDownloads.add(download);

          // Add to cache
          _cache.putIfAbsent(mangaId, () => {});
          _cache[mangaId]!.add(chapterId);
        } else {
          // File không tồn tại -> invalid
          invalidChapterIds.add(chapterId);
        }
      }

      // Clean up invalid entries từ database
      if (invalidChapterIds.isNotEmpty) {
        debugPrint(
          '🧹 DownloadCache: Cleaning ${invalidChapterIds.length} invalid entries',
        );
        for (final chapterId in invalidChapterIds) {
          await DatabaseHelper.instance.deleteDownload(chapterId);
        }
      }

      _lastRefresh = DateTime.now();
      debugPrint(
        '✅ DownloadCache: Refreshed (${validDownloads.length} chapters)',
      );

      _notifyChanges();
    } catch (e) {
      debugPrint('❌ DownloadCache: Error refreshing cache: $e');
    } finally {
      _isRefreshing = false;
    }
  }

  /// Check file system trực tiếp (không dùng cache)
  Future<bool> _checkFileSystemDirect(String chapterId, String mangaId) async {
    try {
      final downloadInfo = await DatabaseHelper.instance.getDownload(chapterId);
      if (downloadInfo == null) return false;

      final localPath = downloadInfo['localPath'] as String?;
      if (localPath == null || localPath.isEmpty) return false;

      final file = File(localPath);
      final exists = await file.exists();

      // Nếu file không tồn tại, clean up database
      if (!exists) {
        await DatabaseHelper.instance.deleteDownload(chapterId);
        _cache[mangaId]?.remove(chapterId);
        _notifyChanges();
      }

      return exists;
    } catch (e) {
      debugPrint('❌ DownloadCache: Error checking file system: $e');
      return false;
    }
  }

  /// Reindex downloads (scan file system và sync với database)
  ///
  /// Tính năng này giống Mihon's "Reindex Downloads"
  /// Sử dụng khi:
  /// - User xóa/move files thủ công
  /// - Database bị out-of-sync
  /// - Sau khi restore backup
  Future<ReindexResult> reindexDownloads() async {
    debugPrint('🔄 DownloadCache: Starting reindex...');

    int foundInDb = 0;
    int foundInFs = 0;
    int removed = 0;
    int added = 0;

    try {
      // 1. Get all downloads from database
      final dbDownloads = await DatabaseHelper.instance.getAllDownloads();
      foundInDb = dbDownloads.length;

      // 2. Validate each entry
      final invalidChapterIds = <String>[];
      for (final download in dbDownloads) {
        final chapterId = download['chapterId'] as String;
        final localPath = download['localPath'] as String?;

        if (localPath == null || localPath.isEmpty) {
          invalidChapterIds.add(chapterId);
          continue;
        }

        final file = File(localPath);
        if (!await file.exists()) {
          invalidChapterIds.add(chapterId);
        }
      }

      // 3. Remove invalid entries
      for (final chapterId in invalidChapterIds) {
        await DatabaseHelper.instance.deleteDownload(chapterId);
        removed++;
      }

      // 4. Scan file system để tìm files mà database không có
      // (Tính năng này phức tạp hơn, có thể implement sau)
      // Hiện tại chỉ validate database entries

      // 5. Refresh cache
      await invalidateCache();

      debugPrint('✅ DownloadCache: Reindex complete');
      debugPrint('   - Found in DB: $foundInDb');
      debugPrint('   - Removed: $removed');

      return ReindexResult(
        foundInDb: foundInDb,
        foundInFs: foundInFs,
        removed: removed,
        added: added,
      );
    } catch (e) {
      debugPrint('❌ DownloadCache: Error during reindex: $e');
      rethrow;
    }
  }

  void _notifyChanges() {
    _changesController.add(null);
  }

  void dispose() {
    _changesController.close();
  }
}

/// Kết quả của reindex operation
class ReindexResult {
  final int foundInDb;
  final int foundInFs;
  final int removed;
  final int added;

  ReindexResult({
    required this.foundInDb,
    required this.foundInFs,
    required this.removed,
    required this.added,
  });

  @override
  String toString() {
    return 'ReindexResult(foundInDb: $foundInDb, foundInFs: $foundInFs, '
        'removed: $removed, added: $added)';
  }
}
