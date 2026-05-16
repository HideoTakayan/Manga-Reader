import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../data/database_helper.dart';

/// Bộ nhớ đệm để theo dõi tải xuống từ hệ thống tệp
///
/// Thay vì truy vấn cơ sở dữ liệu liên tục, ta quét hệ thống tệp và lưu kết quả vào bộ nhớ đệm.
/// Cache được refresh mỗi 1 giờ hoặc khi có thay đổi.
class DownloadCache {
  static final DownloadCache instance = DownloadCache._init();
  DownloadCache._init();

  final Map<String, Set<String>> _cache = {};

  DateTime? _lastRefresh;

  static const _refreshInterval = Duration(hours: 1);

  bool _isRefreshing = false;

  final _changesController = StreamController<void>.broadcast();
  Stream<void> get changes => _changesController.stream;
  Future<bool> isChapterDownloaded(
    String chapterId,
    String mangaId, {
    bool skipCache = false,
  }) async {
    if (skipCache) {
      // Quét hệ thống tệp trực tiếp
      return await _checkFileSystemDirect(chapterId, mangaId);
    }

    // Làm mới bộ nhớ đệm nếu cần
    await _refreshCacheIfNeeded();

    // Kiểm tra bộ nhớ đệm
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

  /// Lấy danh sách chapterIds đã tải xuống của một truyện
  Future<Set<String>> getDownloadedChapterIds(String mangaId) async {
    await _refreshCacheIfNeeded();
    return _cache[mangaId] ?? {};
  }

  /// Thêm chương vào bộ nhớ đệm (khi tải xong)
  Future<void> addChapter(String chapterId, String mangaId) async {
    _cache.putIfAbsent(mangaId, () => {});
    _cache[mangaId]!.add(chapterId);
    _notifyChanges();
  }

  /// Xóa chương khỏi bộ nhớ đệm (khi xóa)
  Future<void> removeChapter(String chapterId, String mangaId) async {
    _cache[mangaId]?.remove(chapterId);
    if (_cache[mangaId]?.isEmpty ?? false) {
      _cache.remove(mangaId);
    }
    _notifyChanges();
  }

  /// Xóa tất cả các chương của một truyện khỏi bộ nhớ đệm
  Future<void> removeManga(String mangaId) async {
    _cache.remove(mangaId);
    _notifyChanges();
  }

  /// Bắt buộc làm mới bộ nhớ đệm (quét lại hệ thống tệp)
  Future<void> invalidateCache() async {
    _lastRefresh = null;
    await refreshCache();
  }

  /// Làm mới bộ nhớ đệm nếu đã quá thời gian
  Future<void> _refreshCacheIfNeeded() async {
    if (_lastRefresh == null ||
        DateTime.now().difference(_lastRefresh!) > _refreshInterval) {
      await refreshCache();
    }
  }

  /// Làm mới bộ nhớ đệm (quét hệ thống tệp)
  Future<void> refreshCache() async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      debugPrint('🔄 DownloadCache: Refreshing cache...');

      // Xóa bộ nhớ đệm cũ
      _cache.clear();

      // Lấy tất cả tải xuống từ cơ sở dữ liệu
      final downloads = await DatabaseHelper.instance.getAllDownloads();

      // Xác thực từng tải xuống (kiểm tra xem tệp có tồn tại không)
      final validDownloads = <Map<String, dynamic>>[];
      final invalidChapterIds = <String>[];

      for (final download in downloads) {
        final chapterId = _readString(download, 'chapterId');
        final mangaId = _readString(download, 'mangaId');
        final localPath = _readString(download, 'localPath');

        if (chapterId.isEmpty || mangaId.isEmpty || localPath.isEmpty) {
          _markInvalid(invalidChapterIds, chapterId);
          continue;
        }

        final file = File(localPath);
        if (await file.exists()) {
          validDownloads.add(download);

          // Thêm vào bộ nhớ đệm
          _cache.putIfAbsent(mangaId, () => {});
          _cache[mangaId]!.add(chapterId);
        } else {
          // Tệp không tồn tại -> không hợp lệ
          _markInvalid(invalidChapterIds, chapterId);
        }
      }

      // Dọn dẹp các mục không hợp lệ từ cơ sở dữ liệu
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

  Future<bool> _checkFileSystemDirect(String chapterId, String mangaId) async {
    try {
      final downloadInfo = await DatabaseHelper.instance.getDownload(chapterId);
      if (downloadInfo == null) return false;

      final localPath = _readString(downloadInfo, 'localPath');
      if (localPath.isEmpty) return false;

      final file = File(localPath);
      final exists = await file.exists();

      // Nếu tệp không tồn tại, dọn dẹp cơ sở dữ liệu
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

  /// Lập chỉ mục lại tải xuống (quét hệ thống tệp và đồng bộ với cơ sở dữ liệu)
  Future<ReindexResult> reindexDownloads() async {
    debugPrint('🔄 DownloadCache: Starting reindex...');

    int foundInDb = 0;
    int foundInFs = 0;
    int removed = 0;
    int added = 0;

    try {
      // 1. Lấy tất cả thông tin tải xuống từ cơ sở dữ liệu
      final dbDownloads = await DatabaseHelper.instance.getAllDownloads();
      foundInDb = dbDownloads.length;

      // 2. Xác thực từng mục
      final invalidChapterIds = <String>[];
      for (final download in dbDownloads) {
        final chapterId = _readString(download, 'chapterId');
        final localPath = _readString(download, 'localPath');

        if (chapterId.isEmpty || localPath.isEmpty) {
          _markInvalid(invalidChapterIds, chapterId);
          continue;
        }

        final file = File(localPath);
        if (!await file.exists()) {
          _markInvalid(invalidChapterIds, chapterId);
        }
      }

      // 3. Xóa các mục không hợp lệ
      for (final chapterId in invalidChapterIds) {
        await DatabaseHelper.instance.deleteDownload(chapterId);
        removed++;
      }
      // 4. Làm mới bộ nhớ đệm
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

  String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return '';
    return value.toString().trim();
  }

  void _markInvalid(List<String> invalidChapterIds, String chapterId) {
    if (chapterId.isNotEmpty) {
      invalidChapterIds.add(chapterId);
    }
  }

  void dispose() {
    _changesController.close();
  }
}

/// Kết quả của thao tác lập chỉ mục lại
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
