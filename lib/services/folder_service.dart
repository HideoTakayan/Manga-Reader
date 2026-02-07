import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../data/models.dart';

/// Service quản lý cấu trúc thư mục lưu trữ truyện offline
class FolderService {
  static String? _rootPath;
  static String? _downloadPath;
  static String? _cachePath;

  /// Khởi tạo cấu trúc thư mục khi app khởi động
  static Future<void> init() async {
    try {
      // 1. Thử dùng External Storage trước (giống Mihon)
      _rootPath = '/storage/emulated/0/MangaReader';
      _downloadPath = '$_rootPath/downloads';
      _cachePath = '$_rootPath/temp_cache';

      await Directory(_downloadPath!).create(recursive: true);
      await Directory(_cachePath!).create(recursive: true);

      print('📂 Using External Storage: $_rootPath');
    } catch (e) {
      print('⚠️ Failed to use External Storage (Permission Denied): $e');
      print('🔄 Falling back to Internal App Storage');

      // Fallback: Dùng Internal App Storage nếu không có quyền
      final appDocDir = await getApplicationDocumentsDirectory();
      _rootPath = '${appDocDir.path}/MangaReader';
      _downloadPath = '$_rootPath/downloads';
      _cachePath = '$_rootPath/temp_cache';

      await Directory(_downloadPath!).create(recursive: true);
      await Directory(_cachePath!).create(recursive: true);
    }

    // Tạo file .nomedia
    if (Platform.isAndroid && _downloadPath != null) {
      try {
        final nomediaFile = File('$_downloadPath/.nomedia');
        if (!await nomediaFile.exists()) {
          await nomediaFile.create();
        }
      } catch (_) {}
    }

    print('📂 Folder System Initialized: $_rootPath');
  }

  /// Lấy đường dẫn thư mục downloads
  static String get downloadPath {
    if (_downloadPath == null) {
      throw Exception('FolderService chưa được khởi tạo. Gọi init() trước.');
    }
    return _downloadPath!;
  }

  /// Lấy đường dẫn thư mục cache tạm
  static String get cachePath {
    if (_cachePath == null) {
      throw Exception('FolderService chưa được khởi tạo. Gọi init() trước.');
    }
    return _cachePath!;
  }

  /// Lấy đường dẫn thư mục của một manga cụ thể
  static String getMangaPath(String mangaId) {
    return '$downloadPath/$mangaId';
  }

  static String sanitize(String input) {
    return input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  static Future<String> getMangaPathByTitle(String title) async {
    final safeTitle = sanitize(title);
    final path = '$downloadPath/$safeTitle';
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  /// Lấy đường dẫn thư mục của một chapter cụ thể
  static String getChapterPath(String mangaId, String chapterId) {
    return '${getMangaPath(mangaId)}/$chapterId';
  }

  /// Tạo thư mục cho manga nếu chưa có
  static Future<void> createMangaFolder(String mangaId) async {
    final path = getMangaPath(mangaId);
    await Directory(path).create(recursive: true);
  }

  /// Tạo thư mục cho chapter nếu chưa có
  static Future<void> createChapterFolder(
    String mangaId,
    String chapterId,
  ) async {
    final path = getChapterPath(mangaId, chapterId);
    await Directory(path).create(recursive: true);
  }

  /// Xóa thư mục của một chapter
  static Future<void> deleteChapterFolder(
    String mangaId,
    String chapterId,
  ) async {
    final path = getChapterPath(mangaId, chapterId);
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Xóa toàn bộ thư mục của một manga
  static Future<void> deleteMangaFolder(String mangaId) async {
    final path = getMangaPath(mangaId);
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Xóa toàn bộ cache tạm
  static Future<void> clearCache() async {
    final dir = Directory(_cachePath!);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create();
      print('🗑️ Cache cleared');
    }
  }

  /// Tính tổng dung lượng thư mục downloads
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

  /// Chuyển đổi bytes sang định dạng dễ đọc (MB, GB)
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Check if cover exists
  static Future<bool> hasCover(String mangaTitle) async {
    final path = await getMangaPathByTitle(mangaTitle);
    return File('$path/cover.jpg').exists();
  }

  /// Save details.json (Mihon style)
  static Future<void> saveMangaDetails(Manga manga) async {
    try {
      final path = await getMangaPathByTitle(manga.title);
      final file = File('$path/details.json');
      await file.writeAsString(jsonEncode(manga.toJson()));
    } catch (e) {
      print('⚠️ Failed to save details.json: $e');
    }
  }

  /// Get cover path
  static Future<String> getCoverPath(String mangaTitle) async {
    final path = await getMangaPathByTitle(mangaTitle);
    return '$path/cover.jpg';
  }
}
