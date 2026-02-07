import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../data/database_helper.dart';
import '../data/drive_service.dart'; // Maybe needed
import '../data/models.dart';
import 'folder_service.dart';
import 'download_cache.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'notification_service.dart';
import 'background_service.dart';

/// Trạng thái download của một chapter
enum DownloadStatus {
  idle, // Chưa tải
  queued, // Đang chờ trong hàng đợi
  downloading, // Đang tải
  paused, // Tạm dừng
  completed, // Đã hoàn thành
  failed, // Lỗi
  cancelled, // Đã hủy
}

/// Model chứa thông tin download
class DownloadTask {
  final String chapterId;
  final String mangaId;
  final String mangaTitle;
  final String chapterTitle;
  final String fileType; // 'cbz', 'pdf', 'zip'

  DownloadStatus status;
  double progress; // 0.0 - 1.0
  String? errorMessage;
  int? totalBytes;
  int? downloadedBytes;

  DownloadTask({
    required this.chapterId,
    required this.mangaId,
    required this.mangaTitle,
    required this.chapterTitle,
    required this.fileType,
    this.status = DownloadStatus.idle,
    this.progress = 0.0,
    this.errorMessage,
    this.totalBytes,
    this.downloadedBytes,
  });

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    String? errorMessage,
    int? totalBytes,
    int? downloadedBytes,
  }) {
    return DownloadTask(
      chapterId: chapterId,
      mangaId: mangaId,
      mangaTitle: mangaTitle,
      chapterTitle: chapterTitle,
      fileType: fileType,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chapterId': chapterId,
      'mangaId': mangaId,
      'mangaTitle': mangaTitle,
      'chapterTitle': chapterTitle,
      'fileType': fileType,
      'status': status.index,
      'progress': progress,
      'errorMessage': errorMessage,
      'totalBytes': totalBytes,
      'downloadedBytes': downloadedBytes,
    };
  }

  factory DownloadTask.fromJson(Map<String, dynamic> map) {
    return DownloadTask(
      chapterId: map['chapterId'] ?? '',
      mangaId: map['mangaId'] ?? '',
      mangaTitle: map['mangaTitle'] ?? '',
      chapterTitle: map['chapterTitle'] ?? '',
      fileType: map['fileType'] ?? 'zip',
      status: DownloadStatus.values[map['status'] ?? 0],
      progress: map['progress'] ?? 0.0,
      errorMessage: map['errorMessage'],
      totalBytes: map['totalBytes'],
      downloadedBytes: map['downloadedBytes'],
    );
  }
}

/// Service quản lý download truyện
class DownloadService {
  static final DownloadService instance = DownloadService._internal();
  DownloadService._internal() {
    _activeDownloads = 0;
    restoreQueue(); // Restore queue on init
  }

  // Hàng đợi download
  final Map<String, DownloadTask> _downloadQueue = {};

  // Stream controller để UI lắng nghe
  final _downloadController =
      StreamController<Map<String, DownloadTask>>.broadcast();

  Stream<Map<String, DownloadTask>> get downloadStream =>
      _downloadController.stream;

  // Số lượng download đồng thời tối đa
  static const int _maxConcurrentDownloads = 2;
  int _activeDownloads = 0;

  /// Thêm chapter vào hàng đợi download
  Future<void> addToQueue({
    required String chapterId,
    required String mangaId,
    required String mangaTitle,
    required String chapterTitle,
    String fileType = 'cbz',
    Manga? mangaInfo,
  }) async {
    // Save info for Offline mode (Detail Page)
    if (mangaInfo != null) {
      DatabaseHelper.instance.saveLocalManga(mangaInfo);
    }

    // Kiểm tra đã tải chưa
    final isDownloaded = await DatabaseHelper.instance.isChapterDownloaded(
      chapterId,
    );
    if (isDownloaded) {
      debugPrint('⚠️ Chapter $chapterId đã được tải rồi');
      return;
    }

    // Kiểm tra đã có trong queue chưa
    if (_downloadQueue.containsKey(chapterId)) {
      debugPrint('⚠️ Chapter $chapterId đã có trong hàng đợi');
      return;
    }

    // Tạo task mới
    final task = DownloadTask(
      chapterId: chapterId,
      mangaId: mangaId,
      mangaTitle: mangaTitle,
      chapterTitle: chapterTitle,
      fileType: fileType,
      status: DownloadStatus.queued,
    );

    _downloadQueue[chapterId] = task;
    _notifyListeners();

    // Bắt đầu tải nếu còn slot
    _processQueue();
  }

  /// Xử lý hàng đợi download
  void _processQueue() {
    if (_activeDownloads == 0 && _downloadQueue.isEmpty) {
      WakelockPlus.disable();
      BackgroundService.stop();
    } else {
      WakelockPlus.enable();
      BackgroundService.start();
    }

    debugPrint(
      '🔄 Queue Check: Active=$_activeDownloads/${_maxConcurrentDownloads}, Queue=${_downloadQueue.length}',
    );

    if (_activeDownloads >= _maxConcurrentDownloads) return;

    // Tìm task đầu tiên đang queued
    final queuedTask = _downloadQueue.values.firstWhere(
      (task) => task.status == DownloadStatus.queued,
      orElse: () => DownloadTask(
        chapterId: '',
        mangaId: '',
        mangaTitle: '',
        chapterTitle: '',
        fileType: '',
      ),
    );

    if (queuedTask.chapterId.isEmpty) return;

    // Bắt đầu tải
    _downloadChapter(queuedTask);
  }

  /// Tải một chapter
  Future<void> _downloadChapter(DownloadTask task) async {
    _activeDownloads++;
    task.status = DownloadStatus.downloading;
    _notifyListeners();

    // Init notification (just in case)
    await NotificationService.instance.initLocalNotifications();

    final notifId = task.chapterId.hashCode;
    await NotificationService.instance.showDownloadProgress(
      notifId,
      0,
      'Đang chuẩn bị...',
      task.chapterTitle,
    );

    try {
      debugPrint('📥 Bắt đầu tải: ${task.chapterTitle}');

      // 1. Tạo thư mục đích (Theo tên truyện)
      final mangaFolderPath = await FolderService.getMangaPathByTitle(
        task.mangaTitle,
      );

      // --- Metadata & Cover (Local Source Support) ---
      try {
        final manga = await DatabaseHelper.instance.getLocalManga(task.mangaId);
        if (manga != null) {
          await FolderService.saveMangaDetails(manga);

          if (!await FolderService.hasCover(task.mangaTitle) &&
              manga.coverUrl.isNotEmpty) {
            final coverBytes = await DriveService.instance
                .downloadFileWithProgress(
                  manga.coverUrl,
                  onProgress: (_, __) {},
                );
            if (coverBytes != null) {
              final coverPath = await FolderService.getCoverPath(
                task.mangaTitle,
              );
              await File(coverPath).writeAsBytes(coverBytes);
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ Local Metadata Error: $e');
      }
      // -----------------------------------------------

      // 2. Tải file từ Google Drive (có progress + notify)
      DateTime lastNotifTime = DateTime.now();

      final fileBytes = await DriveService.instance.downloadFileWithProgress(
        task.chapterId,
        onProgress: (received, total) async {
          if (total <= 0) return;
          final progress = received / total;

          task.progress = progress;
          task.downloadedBytes = received;
          task.totalBytes = total;
          _notifyListeners(); // Update App UI

          // Update Notification (Throttle: 800ms để tránh lag UI System)
          if (DateTime.now().difference(lastNotifTime).inMilliseconds > 800) {
            await NotificationService.instance.showDownloadProgress(
              notifId,
              (progress * 100).toInt(),
              'Đang tải: ${task.chapterTitle}',
              '${_formatBytes(received)} / ${_formatBytes(total)}',
            );
            lastNotifTime = DateTime.now();
          }
        },
      );

      if (fileBytes == null) {
        throw Exception('Không thể tải file từ Google Drive');
      }

      // 3. Lưu file vào máy (Tên chương sanitized)
      final safeChapterTitle = FolderService.sanitize(task.chapterTitle);
      String fileName = safeChapterTitle;
      if (!fileName.toLowerCase().endsWith('.${task.fileType}')) {
        fileName = '$fileName.${task.fileType}';
      }
      final filePath = '$mangaFolderPath/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(fileBytes);

      // 4. Lưu thông tin vào database
      await DatabaseHelper.instance.saveDownload(
        chapterId: task.chapterId,
        mangaId: task.mangaId,
        mangaTitle: task.mangaTitle,
        chapterTitle: task.chapterTitle,
        localPath: filePath,
        fileSize: fileBytes.length,
      );

      // 4.5. Update cache
      await DownloadCache.instance.addChapter(task.chapterId, task.mangaId);

      // 5. Cập nhật trạng thái
      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      debugPrint(
        '✅ Tải xong: ${task.chapterTitle} (${_formatBytes(fileBytes.length)})',
      );

      // Notify Success
      await NotificationService.instance.showDownloadComplete(
        notifId,
        'Tải xong',
        task.chapterTitle,
      );

      // 6. Auto remove khỏi queue sau khi completed
      // Delay 1 giây để user thấy "completed" trước khi ẩn
      Future.delayed(const Duration(seconds: 1), () {
        _downloadQueue.remove(task.chapterId);
        _notifyListeners();
        debugPrint('🗑️ Đã xóa khỏi queue: ${task.chapterTitle}');
      });
    } catch (e) {
      debugPrint('❌ Lỗi tải ${task.chapterTitle}: $e');
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();

      // Notify Error
      await NotificationService.instance.showDownloadComplete(
        notifId,
        'Lỗi tải',
        task.chapterTitle,
        isError: true,
      );
    } finally {
      _activeDownloads--;
      _notifyListeners();

      // Tiếp tục xử lý queue
      _processQueue();
    }
  }

  /// Hủy download
  Future<void> cancelDownload(String chapterId) async {
    if (!_downloadQueue.containsKey(chapterId)) return;

    final task = _downloadQueue[chapterId]!;

    if (task.status == DownloadStatus.downloading) {
      // TODO: Implement cancel logic (cần dùng dio để có thể cancel)
      task.status = DownloadStatus.cancelled;
    }

    _downloadQueue.remove(chapterId);
    _notifyListeners();
  }

  /// Tạm dừng download
  void pauseDownload(String chapterId) {
    if (!_downloadQueue.containsKey(chapterId)) return;

    final task = _downloadQueue[chapterId]!;
    if (task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.queued) {
      task.status = DownloadStatus.paused;
      _notifyListeners();
      debugPrint('⏸️ Tạm dừng: ${task.chapterTitle}');
    }
  }

  /// Tiếp tục download
  void resumeDownload(String chapterId) {
    if (!_downloadQueue.containsKey(chapterId)) return;

    final task = _downloadQueue[chapterId]!;
    if (task.status == DownloadStatus.paused) {
      task.status = DownloadStatus.queued;
      task.progress = 0.0; // Reset progress
      _notifyListeners();
      _processQueue();
      debugPrint('▶️ Tiếp tục: ${task.chapterTitle}');
    }
  }

  /// Thử lại download (khi failed)
  void retryDownload(String chapterId) {
    if (!_downloadQueue.containsKey(chapterId)) return;

    final task = _downloadQueue[chapterId]!;
    if (task.status == DownloadStatus.failed) {
      task.status = DownloadStatus.queued;
      task.progress = 0.0;
      task.errorMessage = null;
      _notifyListeners();
      _processQueue();
      debugPrint('🔄 Thử lại: ${task.chapterTitle}');
    }
  }

  /// Tạm dừng tất cả downloads
  void pauseAll() {
    for (final task in _downloadQueue.values) {
      if (task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.queued) {
        task.status = DownloadStatus.paused;
      }
    }
    _notifyListeners();
    debugPrint('⏸️ Tạm dừng tất cả downloads');
  }

  /// Tiếp tục tất cả downloads
  void resumeAll() {
    for (final task in _downloadQueue.values) {
      if (task.status == DownloadStatus.paused) {
        task.status = DownloadStatus.queued;
      }
    }
    _notifyListeners();
    _processQueue();
    debugPrint('▶️ Tiếp tục tất cả downloads');
  }

  /// Xóa toàn bộ hàng đợi
  void clearQueue() {
    _downloadQueue.clear();
    _activeDownloads = 0;
    _notifyListeners();
    debugPrint('🗑️ Đã xóa hàng đợi');
  }

  /// Xóa chapter đã tải
  Future<void> deleteDownload(String chapterId) async {
    try {
      // 1. Lấy thông tin download
      final downloadInfo = await DatabaseHelper.instance.getDownload(chapterId);
      if (downloadInfo == null) return;

      final mangaId = downloadInfo['mangaId'] as String;

      // 2. Xóa file
      final filePath = downloadInfo['localPath'] as String;
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      // 3. Xóa khỏi database
      await DatabaseHelper.instance.deleteDownload(chapterId);

      // 4. Update cache
      await DownloadCache.instance.removeChapter(chapterId, mangaId);

      debugPrint('🗑️ Đã xóa download: $chapterId');

      // 5. Kiểm tra xem còn chương nào của truyện này không
      final remaining = await DatabaseHelper.instance.getDownloadsByManga(
        mangaId,
      );
      if (remaining.isEmpty) {
        debugPrint('🧹 Không còn chương nào, tiến hành xóa folder truyện...');
        final mangaTitle = downloadInfo['mangaTitle'] as String;
        final folderPath = await FolderService.getMangaPathByTitle(mangaTitle);
        final dir = Directory(folderPath);
        if (await dir.exists()) {
          // Xóa toàn bộ folder bao gồm cover.jpg, details.json
          await dir.delete(recursive: true);
          debugPrint('✅ Đã xóa sạch folder: $folderPath');
        }

        // Clear cache entry hoàn toàn
        await DownloadCache.instance.removeManga(mangaId);
      }
    } catch (e) {
      debugPrint('❌ Lỗi xóa download: $e');
    }
  }

  /// Kiểm tra chapter đã tải chưa
  ///
  /// Sử dụng DownloadCache để check nhanh hơn
  Future<bool> isDownloaded(String chapterId, {String? mangaId}) async {
    if (mangaId != null) {
      // Sử dụng cache (nhanh)
      return await DownloadCache.instance.isChapterDownloaded(
        chapterId,
        mangaId,
      );
    }

    // Fallback: query database trực tiếp
    return await DatabaseHelper.instance.isChapterDownloaded(chapterId);
  }

  /// Lấy trạng thái download của chapter
  DownloadStatus getDownloadStatus(String chapterId) {
    if (_downloadQueue.containsKey(chapterId)) {
      return _downloadQueue[chapterId]!.status;
    }
    return DownloadStatus.idle;
  }

  /// Lấy progress của chapter đang tải
  double getDownloadProgress(String chapterId) {
    if (_downloadQueue.containsKey(chapterId)) {
      return _downloadQueue[chapterId]!.progress;
    }
    return 0.0;
  }

  /// Thông báo listeners & Persist Queue
  void _notifyListeners() {
    _downloadController.add(Map.from(_downloadQueue));
    _saveQueue();
  }

  // Persistent Queue Storage
  static const String _queuePrefsKey = 'download_queue_prefs';

  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> jsonList = _downloadQueue.values
          .where(
            (task) =>
                task.status != DownloadStatus.completed &&
                task.status != DownloadStatus.cancelled,
          )
          .map((task) => jsonEncode(task.toJson()))
          .toList();
      await prefs.setStringList(_queuePrefsKey, jsonList);
    } catch (e) {
      debugPrint('⚠️ Failed to save download queue: $e');
    }
  }

  Future<void> restoreQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? jsonList = prefs.getStringList(_queuePrefsKey);

      if (jsonList != null && jsonList.isNotEmpty) {
        debugPrint('📥 Restoring ${jsonList.length} tasks from queue...');
        for (final jsonStr in jsonList) {
          try {
            final task = DownloadTask.fromJson(jsonDecode(jsonStr));
            // Reset status processing -> queued
            if (task.status == DownloadStatus.downloading) {
              task.status = DownloadStatus.queued;
            }
            // Skip completed/cancelled tasks if any remain
            if (task.status == DownloadStatus.completed ||
                task.status == DownloadStatus.cancelled) {
              continue;
            }
            _downloadQueue[task.chapterId] = task;
          } catch (e) {
            debugPrint('⚠️ Error parsing task: $e');
          }
        }

        _notifyListeners();
        // Auto-resume if queue not empty
        if (_downloadQueue.isNotEmpty) {
          // Wait a bit for other services to init
          Future.delayed(const Duration(seconds: 2), () {
            _processQueue();
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to restore download queue: $e');
    }
  }

  /// Format bytes thành string dễ đọc
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Xóa toàn bộ download của một manga (file, folder, db, cache)
  Future<void> deleteMangaDownloads(String mangaId, String mangaTitle) async {
    try {
      debugPrint('🗑️ Đang xóa toàn bộ download manga: $mangaTitle');

      // 1. Xóa khỏi Database
      await DatabaseHelper.instance.deleteDownloadsByManga(mangaId);

      // 2. Xóa Folder
      final folderPath = await FolderService.getMangaPathByTitle(mangaTitle);
      final dir = Directory(folderPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        debugPrint('✅ Đã xóa folder: $folderPath');
      }

      // 3. Xóa cache
      await DownloadCache.instance.removeManga(mangaId);
    } catch (e) {
      debugPrint('❌ Lỗi xóa manga downloads: $e');
    }
  }

  /// Dispose
  void dispose() {
    _downloadController.close();
  }
}
