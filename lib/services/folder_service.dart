import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../data/models.dart';

// FolderService: quản lý cấu trúc thư mục lưu trữ truyện offline.
class FolderService {
  static String? _rootPath;
  static String? _downloadPath;
  static String? _cachePath;
  static String? get rootPath => _rootPath;

  static Future<void> init() async {
    try {
      if (Platform.isAndroid) {
        _rootPath = await _resolveAndroidRootPath();
      } else {
        final appDocDir = await getApplicationDocumentsDirectory();
        _rootPath = '${appDocDir.path}/MangaReader';
      }

      _downloadPath = '$_rootPath/downloads';
      _cachePath = '$_rootPath/temp_cache';

      await Directory(_downloadPath!).create(recursive: true);
      await Directory(_cachePath!).create(recursive: true);
      debugPrint('📂 Using Storage: $_rootPath');
    } catch (e) {
      debugPrint('⚠️ Failed to initialize storage: $e');
      final appDocDir = await getApplicationDocumentsDirectory();
      _rootPath = '${appDocDir.path}/MangaReader_Fallback';
      _downloadPath = '$_rootPath/downloads';
      _cachePath = '$_rootPath/temp_cache';
      await Directory(_downloadPath!).create(recursive: true);
      await Directory(_cachePath!).create(recursive: true);
    }

    // .nomedia: file rỗng báo cho Gallery/Media Scanner không index thư mục downloads
    // Tránh ảnh manga hiện trong Gallery của điện thoại
    if (Platform.isAndroid && _downloadPath != null) {
      try {
        final nomediaFile = File('$_downloadPath/.nomedia');
        if (!await nomediaFile.exists()) await nomediaFile.create();
      } catch (_) {}
    }
    debugPrint('📂 Folder System Initialized: $_rootPath');
  }

  static Future<String> _resolveAndroidRootPath() async {
    const publicRoot = '/storage/emulated/0/MangaReader';
    try {
      final publicDir = Directory(publicRoot);
      await publicDir.create(recursive: true);
      final probe = File('$publicRoot/.probe');
      await probe.writeAsString('ok');
      if (await probe.exists()) await probe.delete();
      return publicRoot;
    } catch (e) {
      debugPrint('⚠️ Cannot use public MangaReader folder: $e');
    }

    final extDir = await getExternalStorageDirectory();
    if (extDir != null) {
      return '${extDir.path}/MangaReader';
    }

    final appDocDir = await getApplicationDocumentsDirectory();
    return '${appDocDir.path}/MangaReader';
  }

  static String get downloadPath {
    if (_downloadPath == null) {
      throw Exception('FolderService chưa được khởi tạo. Gọi init() trước.');
    }
    return _downloadPath!;
  }

  static String get cachePath {
    if (_cachePath == null) {
      throw Exception('FolderService chưa được khởi tạo. Gọi init() trước.');
    }
    return _cachePath!;
  }

  static String getMangaPath(String mangaId) => '$downloadPath/$mangaId';
  static String getChapterPath(String mangaId, String chapterId) =>
      '${getMangaPath(mangaId)}/$chapterId';

  /// Xóa ký tự không hợp lệ trong tên file/folder trên các hệ điều hành
  static String sanitize(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final result = cleaned.replaceAll(RegExp(r'^_+|_+$'), '').trim();
    return result.isEmpty ? 'Untitled' : result;
  }

  /// Title-based path — tạo folder nếu chưa tồn tại (mkdir -p)
  static Future<String> getMangaPathByTitle(String title) async {
    final safeTitle = sanitize(title);
    final path = '$downloadPath/$safeTitle';
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  static Future<void> createMangaFolder(String mangaId) async {
    if (mangaId.trim().isEmpty) return;
    final path = getMangaPath(mangaId);
    if (path == downloadPath) return;
    await Directory(path).create(recursive: true);
  }

  static Future<void> createChapterFolder(
    String mangaId,
    String chapterId,
  ) async {
    if (mangaId.trim().isEmpty || chapterId.trim().isEmpty) return;
    final path = getChapterPath(mangaId, chapterId);
    if (path == downloadPath) return;
    await Directory(path).create(recursive: true);
  }

  static Future<void> deleteChapterFolder(
    String mangaId,
    String chapterId,
  ) async {
    if (mangaId.trim().isEmpty || chapterId.trim().isEmpty) return;
    final path = getChapterPath(mangaId, chapterId);
    if (path == downloadPath) return;
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  static Future<void> deleteMangaFolder(
    String mangaId, {
    String? mangaTitle,
  }) async {
    if (mangaId.trim().isNotEmpty) {
      final mangaPath = getMangaPath(mangaId);
      if (mangaPath != downloadPath) {
        final dirById = Directory(mangaPath);
        if (await dirById.exists()) {
          await dirById.delete(recursive: true);
        }
      }
    }
    if (mangaTitle != null && mangaTitle.trim().isNotEmpty) {
      final safeTitle = sanitize(mangaTitle);
      if (safeTitle.isNotEmpty && safeTitle != 'Untitled') {
        final titlePath = '$downloadPath/$safeTitle';
        if (titlePath != downloadPath) {
          final dirByTitle = Directory(titlePath);
          if (await dirByTitle.exists()) {
            await dirByTitle.delete(recursive: true);
          }
        }
      }
    }
  }

  static Future<void> clearCache() async {
    final dir = Directory(_cachePath!);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create(); // Tạo lại thư mục rỗng thay vì để null
      debugPrint('🗑️ Cache cleared');
    }
  }

  /// Tính tổng dung lượng downloads — stream entity recursively để đếm byte
  static Future<int> getTotalDownloadSize() async {
    final dir = Directory(_downloadPath!);
    if (!await dir.exists()) return 0;
    int totalSize = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static Future<bool> hasCover(String mangaTitle) async {
    final path = await getMangaPathByTitle(mangaTitle);
    return File('$path/cover.jpg').exists();
  }

  /// Lưu details.json — Manga.toJson() → jsonEncode → file
  /// Dùng khi tải chapter để LocalScanService có thể import lại khi cần
  static Future<void> saveMangaDetails(Manga manga) async {
    try {
      final path = await getMangaPathByTitle(manga.title);
      await File(
        '$path/details.json',
      ).writeAsString(jsonEncode(manga.toJson()));
    } catch (e) {
      debugPrint('⚠️ Failed to save details.json: $e');
    }
  }

  static Future<String> getCoverPath(String mangaTitle) async {
    final path = await getMangaPathByTitle(mangaTitle);
    return '$path/cover.jpg';
  }

  static Future<String> getNovelsPath() async {
    final path = '$downloadPath/_novels';
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  static Future<String> getNovelFolderByTitle(String title) async {
    final safeTitle = sanitize(title).replaceAll(RegExp(r'\s+'), '_');
    final path = '${await getNovelsPath()}/$safeTitle';
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  static Future<String> getNovelFilePath(String title) async {
    final safeTitle = sanitize(title);
    final finalTitle = safeTitle.isEmpty ? 'Truyen chu' : safeTitle;
    return '${await getNovelsPath()}/$finalTitle.epub';
  }

  static Future<String> getNovelCoverPath(String title) async {
    final safeTitle = sanitize(title);
    final finalTitle = safeTitle.isEmpty ? 'Truyen chu' : safeTitle;
    return '${await getNovelsPath()}/$finalTitle.cover.jpg';
  }

  /// Lưu ảnh trang truyện hiện tại vào Thư mục ảnh công khai (Pictures/MangaReader)
  /// Trả về đường dẫn file đã lưu hoặc null nếu lỗi
  static Future<String?> savePageImageToGallery({
    required String sourceImagePath,
    required String mangaTitle,
    required String chapterTitle,
    required int pageIndex,
  }) async {
    try {
      final sourceFile = File(sourceImagePath);
      if (!await sourceFile.exists()) {
        debugPrint('⚠️ Source image file does not exist: $sourceImagePath');
        return null;
      }

      // 1. Xác định thư mục Pictures/MangaReader
      Directory targetDir;
      if (Platform.isAndroid) {
        final picturesDir = Directory('/storage/emulated/0/Pictures/MangaReader');
        if (await picturesDir.exists()) {
          targetDir = picturesDir;
        } else {
          try {
            await picturesDir.create(recursive: true);
            targetDir = picturesDir;
          } catch (_) {
            // Fallback sang rootPath/SavedImages nếu không truy cập được public Pictures
            targetDir = Directory('${rootPath ?? "/storage/emulated/0/MangaReader"}/SavedImages');
            if (!await targetDir.exists()) await targetDir.create(recursive: true);
          }
        }
      } else {
        final appDocDir = await getApplicationDocumentsDirectory();
        targetDir = Directory('${appDocDir.path}/MangaReader/SavedImages');
        if (!await targetDir.exists()) await targetDir.create(recursive: true);
      }

      // Đảm bảo không có file .nomedia trong thư mục SavedImages / Pictures để Gallery quét được
      final nomediaFile = File('${targetDir.path}/.nomedia');
      if (await nomediaFile.exists()) {
        try {
          await nomediaFile.delete();
        } catch (_) {}
      }

      // 2. Tạo tên file hợp lệ & thời gian
      final ext = sourceImagePath.contains('.')
          ? sourceImagePath.split('.').last.toLowerCase()
          : 'jpg';
      final safeManga = sanitize(mangaTitle).replaceAll(' ', '_');
      final safeChapter = sanitize(chapterTitle).replaceAll(' ', '_');
      final timeStamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${safeManga}_${safeChapter}_p${pageIndex + 1}_$timeStamp.$ext';
      final destFile = File('${targetDir.path}/$fileName');

      // 3. Copy file
      await sourceFile.copy(destFile.path);
      debugPrint('🖼️ Saved page image to gallery: ${destFile.path}');
      return destFile.path;
    } catch (e) {
      debugPrint('⚠️ Error saving image to gallery: $e');
      return null;
    }
  }
}
