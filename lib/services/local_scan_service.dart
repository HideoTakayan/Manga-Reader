import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../data/database_helper.dart';
import '../data/models.dart';
import 'folder_service.dart';
import 'library_service.dart';

// LocalScanService: quét thư mục MangaReader và import truyện vào SQLite.
// Dùng khi user cài app mới hoặc chuyển thiết bị — khôi phục lại truyện đã tải.
// Logic: Mỗi subfolder trong downloads/ = 1 manga → đọc details.json → import.
class LocalScanService {
  static final LocalScanService instance = LocalScanService._();
  LocalScanService._();

  /// Quét và import tất cả mangas từ filesystem — trả về số manga đã import
  Future<int> scanAndImport() async {
    int importedCount = 0;
    try {
      final downloadPath = FolderService.downloadPath;
      final rootDir = Directory(downloadPath);
      if (!await rootDir.exists()) return 0;

      debugPrint('🔍 Scanning Local Library: $downloadPath');
      final entities = rootDir.listSync();
      for (var entity in entities) {
        if (entity is Directory) {
          await _importMangaFromFolder(entity);
          importedCount++;
        }
      }
      debugPrint('✅ Scan Hoàn Tất. Đã nhập $importedCount truyện.');
    } catch (e) {
      debugPrint('❌ Scan Lỗi: $e');
    }
    return importedCount;
  }

  Future<void> _importMangaFromFolder(Directory folder) async {
    final folderName = p.basename(folder.path);
    if (folderName == 'temp_cache' || folderName.startsWith('.')) return;

    // 1. Đọc details.json nếu có — FolderService.saveMangaDetails() đã ghi khi tải
    final detailFile = File('${folder.path}/details.json');
    Manga? manga;
    if (await detailFile.exists()) {
      try {
        final content = await detailFile.readAsString();
        manga = Manga.fromJson(jsonDecode(content));
      } catch (e) {
        debugPrint('⚠️ Error parsing details.json for $folderName: $e');
      }
    }

    // 2. Fallback: tạo Manga giả từ tên folder nếu không có/parse lỗi details.json
    manga ??= Manga(
        id: 'local_${folderName.hashCode}', // Hash ổn định để ID không đổi giữa các lần scan
        title: folderName,
        coverUrl: '',
        author: 'Local Source',
        description: 'Được nhập từ bộ nhớ máy',
        genres: [],
      );

    // 3. Dùng cover.jpg local thay vì URL nếu tồn tại
    final coverFile = File('${folder.path}/cover.jpg');
    if (await coverFile.exists()) {
      manga = manga.copyWith(coverUrl: coverFile.path);
    }

    // 4. Lưu vào SQLite
    await DatabaseHelper.instance.saveLocalManga(manga);

    // 4b. Thêm vào category "Mặc định" để xuất hiện trong Library tab
    try {
      await LibraryService.instance.addToCategory(manga.id, 'Mặc định');
    } catch (_) {}

    // 5. Quét chapters: các file .cbz/.zip/.epub/.pdf trong folder
    final files = folder.listSync();
    for (var f in files) {
      if (f is File) {
        final ext = p.extension(f.path).toLowerCase();
        if (['.cbz', '.zip', '.epub', '.pdf'].contains(ext)) {
          final chapterTitle = p.basenameWithoutExtension(f.path);
          final fileName = p.basename(f.path);
          // ID ổn định: kết hợp mangaId + fileName.hashCode
          // Nếu DB đã có chapter với cloud ID → saveDownload() sẽ replace (upsert)
          final chapterId = 'local_${manga.id}_${fileName.hashCode}';
          final size = await f.length();
          await DatabaseHelper.instance.saveDownload(
            chapterId: chapterId,
            mangaId: manga.id,
            mangaTitle: manga.title,
            chapterTitle: chapterTitle,
            localPath: f.path,
            fileSize: size,
          );
        }
      }
    }
  }
}
