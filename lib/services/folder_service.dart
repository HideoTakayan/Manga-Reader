import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../data/models.dart';

// FolderService: quản lý cấu trúc thư mục lưu trữ truyện offline.
class FolderService {
  static String? _rootPath;
  static String? _downloadPath;
  static String? _cachePath;

  static Future<void> init() async {
    try {
      // Android: /storage/emulated/0/MangaReader — user thấy được trong File Manager
      _rootPath = '/storage/emulated/0/MangaReader';
      _downloadPath = '$_rootPath/downloads';
      _cachePath = '$_rootPath/temp_cache';
      await Directory(
        _downloadPath!,
      ).create(recursive: true); // recursive: tạo cả parent dir
      await Directory(_cachePath!).create(recursive: true);
      print('📂 Using External Storage: $_rootPath');
    } catch (e) {
      print('⚠️ Failed to use External Storage (Permission Denied): $e');
      final appDocDir = await getApplicationDocumentsDirectory();
      _rootPath = '${appDocDir.path}/MangaReader';
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
    print('📂 Folder System Initialized: $_rootPath');
  }

  static String get downloadPath {
    if (_downloadPath == null)
      throw Exception('FolderService chưa được khởi tạo. Gọi init() trước.');
    return _downloadPath!;
  }

  static String get cachePath {
    if (_cachePath == null)
      throw Exception('FolderService chưa được khởi tạo. Gọi init() trước.');
    return _cachePath!;
  }

  static String getMangaPath(String mangaId) => '$downloadPath/$mangaId';
  static String getChapterPath(String mangaId, String chapterId) =>
      '${getMangaPath(mangaId)}/$chapterId';

  /// Xóa ký tự không hợp lệ trong tên file/folder trên các hệ điều hành
  static String sanitize(String input) {
    return input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  /// Title-based path — tạo folder nếu chưa tồn tại (mkdir -p)
  static Future<String> getMangaPathByTitle(String title) async {
    final safeTitle = sanitize(title);
    final path = '$downloadPath/$safeTitle';
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return path;
  }

  static Future<void> createMangaFolder(String mangaId) async =>
      Directory(getMangaPath(mangaId)).create(recursive: true);
  static Future<void> createChapterFolder(
    String mangaId,
    String chapterId,
  ) async =>
      Directory(getChapterPath(mangaId, chapterId)).create(recursive: true);

  static Future<void> deleteChapterFolder(
    String mangaId,
    String chapterId,
  ) async {
    final dir = Directory(getChapterPath(mangaId, chapterId));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static Future<void> deleteMangaFolder(String mangaId) async {
    final dir = Directory(getMangaPath(mangaId));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static Future<void> clearCache() async {
    final dir = Directory(_cachePath!);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create(); // Tạo lại thư mục rỗng thay vì để null
      print('🗑️ Cache cleared');
    }
  }

  /// Tính tổng dung lượng downloads — stream entity recursively để đếm byte
  static Future<int> getTotalDownloadSize() async {
    final dir = Directory(_downloadPath!);
    if (!await dir.exists()) return 0;
    int totalSize = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) totalSize += await entity.length();
    }
    return totalSize;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
      print('⚠️ Failed to save details.json: $e');
    }
  }

  static Future<String> getCoverPath(String mangaTitle) async {
    final path = await getMangaPathByTitle(mangaTitle);
    return '$path/cover.jpg';
  }
}
