import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../data/database_helper.dart';
import '../data/models.dart';
import 'folder_service.dart';
import 'library_service.dart';

class LocalScanService {
  static final LocalScanService instance = LocalScanService._();
  LocalScanService._();

  /// Quét toàn bộ thư mục MangaReader và nhập dữ liệu vào Database
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
      debugPrint('✅ Scan Complete. Imported $importedCount mangas.');
    } catch (e) {
      debugPrint('❌ Scan Error: $e');
    }
    return importedCount;
  }

  Future<void> _importMangaFromFolder(Directory folder) async {
    final folderName = p.basename(folder.path);
    // Ignore cache folder and hidden folders
    if (folderName == 'temp_cache' || folderName.startsWith('.')) return;

    // 1. Parse details.json
    final detailFile = File('${folder.path}/details.json');
    Manga? manga;

    if (await detailFile.exists()) {
      try {
        final content = await detailFile.readAsString();
        final map = jsonDecode(content);
        manga = Manga.fromJson(map);
      } catch (e) {
        debugPrint('⚠️ Error parsing details.json for $folderName: $e');
      }
    }

    // 2. Fallback if no details (or parsing failed)
    if (manga == null) {
      manga = Manga(
        id: 'local_${folderName.hashCode}',
        title: folderName,
        coverUrl: '', // Will update below
        author: 'Local Source',
        description: 'Được nhập từ bộ nhớ máy',
        genres: [],
      );
    }

    // 3. Check Local Cover
    final coverFile = File('${folder.path}/cover.jpg');
    if (await coverFile.exists()) {
      // Update coverUrl to local path
      manga = manga.copyWith(coverUrl: coverFile.path);
    }

    // 4. Save Manga to DB
    await DatabaseHelper.instance.saveLocalManga(manga);

    // 4b. Add to Default Category (So it shows up in Library)
    try {
      await LibraryService.instance.addToCategory(manga.id, 'Mặc định');
    } catch (_) {}

    // 5. Scan Chapters
    final files = folder.listSync();
    for (var f in files) {
      if (f is File) {
        final ext = p.extension(f.path).toLowerCase();
        if (['.cbz', '.zip', '.epub', '.pdf'].contains(ext)) {
          final chapterTitle = p.basenameWithoutExtension(f.path);
          final fileName = p.basename(f.path);

          // Generate stable ID specific to local file
          // Note: If DB already has Cloud ID, this might create duplicate chapter entries in logic,
          // but 'downloaded_chapters' table uses chapterId as PK.
          // This is acceptable for Local Import mode.
          final chapterId = 'local_${manga.id}_${fileName.hashCode}';
          final size = await f.length();

          // Only insert if not exists (to preserve original Cloud IDs if present?)
          // Or upsert?
          // DatabaseHelper.saveDownload does upsert (replace).

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
