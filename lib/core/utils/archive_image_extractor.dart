import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ArchiveImageExtractor {
  ArchiveImageExtractor._();

  static Future<List<String>> extract(String filePath, String chapterId) async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory(p.join(tempDir.path, 'reader_cache', chapterId));

    if (await cacheDir.exists()) {
      final files = cacheDir.listSync().whereType<File>().toList();
      if (files.isNotEmpty) {
        final paths = files.map((f) => f.path).toList();
        paths.sort((a, b) => _naturalCompare(p.basename(a), p.basename(b)));
        debugPrint('✅ Reusing extracted cache for chapter $chapterId');
        return paths;
      }
      await cacheDir.delete(recursive: true);
    }
    await cacheDir.create(recursive: true);

    final args = {'filePath': filePath, 'outPath': cacheDir.path};

    return compute(_extractZipImagesToDisk, args);
  }

  static Future<List<String>?> getCachedExtractedPages(String chapterId) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tempDir.path, 'reader_cache', chapterId));
      if (await cacheDir.exists()) {
        final files = cacheDir.listSync().whereType<File>().toList();
        if (files.isNotEmpty) {
          final paths = files.map((f) => f.path).toList();
          paths.sort((a, b) => _naturalCompare(p.basename(a), p.basename(b)));
          return paths;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error reading cached extracted pages: $e');
    }
    return null;
  }

  static Future<void> clearCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tempDir.path, 'reader_cache'));
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error clearing reader cache: $e');
      }
    }
  }

  static Future<void> cleanUpOldCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      
      // 1. Dọn thư mục reader_cache (ảnh giải nén)
      final cacheDir = Directory(p.join(tempDir.path, 'reader_cache'));
      if (await cacheDir.exists()) {
        final now = DateTime.now();
        final entities = cacheDir.listSync();
        for (final entity in entities) {
          if (entity is Directory) {
            final stat = await entity.stat();
            if (now.difference(stat.modified).inDays >= 7) {
              await entity.delete(recursive: true);
              debugPrint('🧹 Cleaned old extracted cache: ${entity.path}');
            }
          }
        }
      }

      // 2. Dọn file temp_online_*
      final tempFiles = tempDir.listSync().whereType<File>().where(
        (f) => p.basename(f.path).startsWith('temp_online_')
      );
      final now = DateTime.now();
      for (final file in tempFiles) {
        final stat = await file.stat();
        if (now.difference(stat.modified).inDays >= 7) {
          await file.delete();
          debugPrint('🧹 Cleaned old temp online file: ${file.path}');
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up old cache: $e');
    }
  }
}

List<String> _extractZipImagesToDisk(Map<String, dynamic> args) {
  final filePath = args['filePath'] as String;
  final outPath = args['outPath'] as String;
  final imagePaths = <String>[];

  InputFileStream? inputStream;
  try {
    inputStream = InputFileStream(filePath);
    final archive = ZipDecoder().decodeBuffer(inputStream);
    final sortedFiles = archive.files.toList()
      ..sort((a, b) => _naturalCompare(a.name, b.name));

    int index = 0;
    for (final file in sortedFiles) {
      if (!file.isFile) continue;
      final name = file.name.toLowerCase();
      if (!_isSupportedImage(name)) continue;

      final content = file.content;
      // Guard null và kiểu không hợp lệ (content có thể null khi ZIP entry bị corrupt)
      if (content == null) continue;
      Uint8List fileBytes;
      if (content is Uint8List) {
        fileBytes = content;
      } else if (content is List<int>) {
        fileBytes = Uint8List.fromList(content);
      } else {
        continue;
      }

      final ext = p.extension(name);
      // Đặt tên file theo thứ tự index để dễ quản lý, tránh lỗi tên file chứa ký tự lạ
      final fileName = 'page_${index.toString().padLeft(4, '0')}$ext';
      final outFile = File(p.join(outPath, fileName));
      outFile.writeAsBytesSync(fileBytes);
      imagePaths.add(outFile.path);
      index++;
    }
  } catch (e) {
    debugPrint('Lỗi giải nén: $e');
  } finally {
    inputStream?.close();
  }

  return imagePaths;
}

bool _isSupportedImage(String name) {
  return name.endsWith('.jpg') ||
      name.endsWith('.jpeg') ||
      name.endsWith('.png') ||
      name.endsWith('.webp');
}

int _naturalCompare(String a, String b) {
  final regExp = RegExp(r'(\d+)|(\D+)');
  final am = regExp.allMatches(a.toLowerCase()).toList();
  final bm = regExp.allMatches(b.toLowerCase()).toList();

  for (int i = 0; i < am.length && i < bm.length; i++) {
    final ap = am[i].group(0)!;
    final bp = bm[i].group(0)!;
    if (ap == bp) continue;

    final ai = int.tryParse(ap);
    final bi = int.tryParse(bp);
    if (ai != null && bi != null) return ai.compareTo(bi);
    return ap.compareTo(bp);
  }

  return a.length.compareTo(b.length);
}
