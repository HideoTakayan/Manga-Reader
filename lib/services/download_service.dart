import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../data/database_helper.dart';
import '../data/drive_service.dart';
import '../data/models.dart';
import 'folder_service.dart';
import 'download_cache.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'notification_service.dart';
import 'background_service.dart';

/// Trạng thái tải của một chương
enum DownloadStatus {
  idle, // Chưa tải
  queued, // Đang chờ trong hàng đợi
  downloading, // Đang tải
  paused, // Tạm dừng
  completed, // Đã hoàn thành
  failed, // Lỗi
  cancelled, // Đã hủy
}

/// Mô hình chứa thông tin tải xuống
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

class DownloadService {
  static final DownloadService instance = DownloadService._internal();
  DownloadService._internal() {
    _activeDownloads = 0;
    restoreQueue(); 
  }
  // Hàng đợi tải xuống
  final Map<String, DownloadTask> _downloadQueue = {};

  // Bộ điều khiển luồng để giao diện người dùng (UI) lắng nghe
  final _downloadController =
      StreamController<Map<String, DownloadTask>>.broadcast();

  Stream<Map<String, DownloadTask>> get downloadStream =>
      _downloadController.stream;

  // Số lượng tải xuống đồng thời tối đa
  static const int _maxConcurrentDownloads = 2;
  int _activeDownloads = 0;

  /// Thêm chương vào hàng đợi tải xuống
  Future<void> addToQueue({
    required String chapterId,
    required String mangaId,
    required String mangaTitle,
    required String chapterTitle,
    String fileType = 'cbz',
    Manga? mangaInfo,
  }) async {
    // Lưu thông tin cho chế độ Ngoại tuyến (Trang Chi tiết)
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

    // Kiểm tra đã có trong hàng đợi chưa
    if (_downloadQueue.containsKey(chapterId)) {
      debugPrint('⚠️ Chapter $chapterId đã có trong hàng đợi');
      return;
    }

    // Tạo tác vụ mới
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

  /// Xử lý hàng đợi tải xuống
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

    // Tìm tác vụ đầu tiên đang chờ trong hàng đợi
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

  /// Tải một chương
  Future<void> _downloadChapter(DownloadTask task) async {
    _activeDownloads++;
    task.status = DownloadStatus.downloading;
    _notifyListeners();

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
      // --- Siêu dữ liệu & Ảnh bìa (Hỗ trợ nguồn cục bộ) ---
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

      // 2. Tải tệp từ Google Drive (có tiến trình + thông báo)
      DateTime lastNotifTime = DateTime.now();

      final fileBytes = await DriveService.instance.downloadFileWithProgress(
        task.chapterId,
        onProgress: (received, total) async {
          if (total <= 0) return;
          final progress = received / total;

          task.progress = progress;
          task.downloadedBytes = received;
          task.totalBytes = total;
          _notifyListeners();

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

      // 3. Lưu tệp vào máy (Tên chương đã được làm sạch)
      final safeChapterTitle = FolderService.sanitize(task.chapterTitle);
      String fileName = safeChapterTitle;
      if (!fileName.toLowerCase().endsWith('.${task.fileType}')) {
        fileName = '$fileName.${task.fileType}';
      }
      final filePath = '$mangaFolderPath/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(fileBytes);

      // 4. Lưu thông tin vào cơ sở dữ liệu
      await DatabaseHelper.instance.saveDownload(
        chapterId: task.chapterId,
        mangaId: task.mangaId,
        mangaTitle: task.mangaTitle,
        chapterTitle: task.chapterTitle,
        localPath: filePath,
        fileSize: fileBytes.length,
      );

      await DownloadCache.instance.addChapter(task.chapterId, task.mangaId);

      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      debugPrint(
        '✅ Tải xong: ${task.chapterTitle} (${_formatBytes(fileBytes.length)})',
      );

      await NotificationService.instance.showDownloadComplete(
        notifId,
        'Tải xong',
        task.chapterTitle,
      );

      Future.delayed(const Duration(seconds: 1), () {
        _downloadQueue.remove(task.chapterId);
        _notifyListeners();
        debugPrint('🗑️ Đã xóa khỏi queue: ${task.chapterTitle}');
      });
    } catch (e) {
      debugPrint('❌ Lỗi tải ${task.chapterTitle}: $e');
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();

      await NotificationService.instance.showDownloadComplete(
        notifId,
        'Lỗi tải',
        task.chapterTitle,
        isError: true,
      );
    } finally {
      _activeDownloads--;
      _notifyListeners();

      _processQueue();
    }
  }

  Future<void> cancelDownload(String chapterId) async {
    if (!_downloadQueue.containsKey(chapterId)) return;

    final task = _downloadQueue[chapterId]!;

    if (task.status == DownloadStatus.downloading) {
      task.status = DownloadStatus.cancelled;
    }

    _downloadQueue.remove(chapterId);
    _notifyListeners();
  }

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

  /// Tiếp tục tải xuống
  void resumeDownload(String chapterId) {
    if (!_downloadQueue.containsKey(chapterId)) return;

    final task = _downloadQueue[chapterId]!;
    if (task.status == DownloadStatus.paused) {
      task.status = DownloadStatus.queued;
      task.progress = 0.0; // Đặt lại tiến trình
      _notifyListeners();
      _processQueue();
      debugPrint('▶️ Tiếp tục: ${task.chapterTitle}');
    }
  }

  /// Thử lại quá trình tải (khi bị lỗi)
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

  /// Tạm dừng tất cả tải xuống
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

  /// Tiếp tục tất cả tải xuống
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

  /// Xóa chương đã tải
  Future<void> deleteDownload(String chapterId) async {
    try {
      // 1. Lấy thông tin tải xuống
      final downloadInfo = await DatabaseHelper.instance.getDownload(chapterId);
      if (downloadInfo == null) return;

      final mangaId = downloadInfo['mangaId'] as String;

      // 2. Xóa tệp
      final filePath = downloadInfo['localPath'] as String;
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      // 3. Xóa khỏi cơ sở dữ liệu
      await DatabaseHelper.instance.deleteDownload(chapterId);

      // 4. Cập nhật bộ nhớ đệm
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
          // Xóa toàn bộ thư mục bao gồm cover.jpg, details.json
          await dir.delete(recursive: true);
          debugPrint('✅ Đã xóa sạch folder: $folderPath');
        }

        // Xóa hoàn toàn mục nhập trong bộ nhớ đệm
        await DownloadCache.instance.removeManga(mangaId);
      }
    } catch (e) {
      debugPrint('❌ Lỗi xóa download: $e');
    }
  }

  /// Kiểm tra chương đã tải chưa
  ///
  /// Sử dụng DownloadCache để kiểm tra nhanh hơn
  Future<bool> isDownloaded(String chapterId, {String? mangaId}) async {
    if (mangaId != null) {
      // Sử dụng bộ nhớ đệm (nhanh)
      return await DownloadCache.instance.isChapterDownloaded(
        chapterId,
        mangaId,
      );
    }

    // Dự phòng: truy vấn cơ sở dữ liệu trực tiếp
    return await DatabaseHelper.instance.isChapterDownloaded(chapterId);
  }

  /// Lấy trạng thái tải của chương
  DownloadStatus getDownloadStatus(String chapterId) {
    if (_downloadQueue.containsKey(chapterId)) {
      return _downloadQueue[chapterId]!.status;
    }
    return DownloadStatus.idle;
  }

  /// Lấy tiến trình của chương đang tải
  double getDownloadProgress(String chapterId) {
    if (_downloadQueue.containsKey(chapterId)) {
      return _downloadQueue[chapterId]!.progress;
    }
    return 0.0;
  }

  /// Thông báo cho các trình lắng nghe & Lưu trữ hàng đợi
  void _notifyListeners() {
    _downloadController.add(Map.from(_downloadQueue));
    _saveQueue();
  }

  // Lưu trữ hàng đợi bền bỉ
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
            // Đặt lại trạng thái đang xử lý -> đang chờ trong hàng đợi
            if (task.status == DownloadStatus.downloading) {
              task.status = DownloadStatus.queued;
            }
            // Bỏ qua các tác vụ đã hoàn thành/bị hủy nếu còn lại
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
        // Tự động tiếp tục nếu hàng đợi không trống
        if (_downloadQueue.isNotEmpty) {
          // Chờ một chút để các dịch vụ khác khởi tạo
          Future.delayed(const Duration(seconds: 2), () {
            _processQueue();
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to restore download queue: $e');
    }
  }

  /// Định dạng byte thành chuỗi dễ đọc
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

  /// Xóa toàn bộ tệp tải xuống của một truyện (tệp, thư mục, cơ sở dữ liệu, bộ nhớ đệm)
  Future<void> deleteMangaDownloads(String mangaId, String mangaTitle) async {
    try {
      debugPrint('🗑️ Đang xóa toàn bộ download manga: $mangaTitle');

      // 1. Xóa khỏi Cơ sở dữ liệu
      await DatabaseHelper.instance.deleteDownloadsByManga(mangaId);

      // 2. Xóa Thư mục
      final folderPath = await FolderService.getMangaPathByTitle(mangaTitle);
      final dir = Directory(folderPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        debugPrint('✅ Đã xóa folder: $folderPath');
      }

      // 3. Xóa bộ nhớ đệm
      await DownloadCache.instance.removeManga(mangaId);
    } catch (e) {
      debugPrint('❌ Lỗi xóa manga downloads: $e');
    }
  }

  /// Hủy
  void dispose() {
    _downloadController.close();
  }
}
