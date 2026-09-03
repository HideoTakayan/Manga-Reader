import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database_helper.dart';
import 'achievement_service.dart';
import 'folder_service.dart';
import 'library_service.dart';

class BackupService {
  BackupService._();

  static final BackupService instance = BackupService._();

  static const int currentSchemaVersion = 3;

  static const List<String> _tables = [
    'comics',
    'history',
    'lib_categories',
    'lib_mapping',
    'reader_progress',
    'bookmarks',
    'catalog_cache',
    'library_status',
    'reading_activity',
  ];

  Future<String?> exportToJsonFile() async {
    final db = await DatabaseHelper.instance.database;
    final prefs = await SharedPreferences.getInstance();

    // 1. Sao lưu danh sách truyện chữ (Local Novels)
    final novelsRaw = prefs.getStringList('local_novels_v1') ?? [];
    final List<Map<String, dynamic>> localNovels = [];
    for (final str in novelsRaw) {
      try {
        final map = jsonDecode(str);
        if (map is Map<String, dynamic>) {
          localNovels.add(map);
        } else if (map is Map) {
          localNovels.add(map.map((k, v) => MapEntry(k.toString(), v)));
        }
      } catch (_) {}
    }

    // 2. Sao lưu các cài đặt cấu hình người dùng
    final preferences = <String, dynamic>{
      'auto_download_new_chapters': prefs.getBool('auto_download_new_chapters'),
      'auto_download_max_chapters': prefs.getInt('auto_download_max_chapters'),
      'global_tts_rate': prefs.getDouble('global_tts_rate'),
      'global_tts_pitch': prefs.getDouble('global_tts_pitch'),
      'global_tts_lang': prefs.getString('global_tts_lang'),
      'global_tts_voice_name': prefs.getString('global_tts_voice_name'),
      'global_tts_voice_locale': prefs.getString('global_tts_voice_locale'),
      'reading_mode': prefs.getString('reading_mode'),
      'reader_image_fit': prefs.getString('reader_image_fit'),
      'reader_direction': prefs.getString('reader_direction'),
      'reader_background': prefs.getString('reader_background'),
      'reader_dim_level': prefs.getDouble('reader_dim_level'),
      'reader_tint_level': prefs.getDouble('reader_tint_level'),
      'reader_invert_colors': prefs.getBool('reader_invert_colors'),
      'achievements_unlocked_data': prefs.getString('achievements_unlocked_data'),
      'achievements_chapters_read_count': prefs.getInt('achievements_chapters_read_count'),
      'achievements_unique_genres': prefs.getStringList('achievements_unique_genres'),
    }..removeWhere((k, v) => v == null);

    final data = <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': <String, dynamic>{},
      'local_novels': localNovels,
      'preferences': preferences,
    };

    final tables = data['tables'] as Map<String, dynamic>;
    for (final table in _tables) {
      tables[table] = await db.query(table);
    }

    final fileName =
        'manga_reader_backup_${DateTime.now().millisecondsSinceEpoch}.json';

    final rootPath = FolderService.rootPath;
    if (rootPath == null) return null;

    final backupsDir = Directory('$rootPath/backups');
    if (!await backupsDir.exists()) {
      await backupsDir.create(recursive: true);
    }

    final outputPath = '${backupsDir.path}/$fileName';
    final file = File(outputPath);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(data), flush: true);

    debugPrint('✅ Đã lưu backup tại: $outputPath');
    return outputPath;
  }

  Future<List<File>> getBackupFiles() async {
    final rootPath = FolderService.rootPath;
    if (rootPath == null) return [];
    final backupsDir = Directory('$rootPath/backups');
    if (!await backupsDir.exists()) return [];
    try {
      final files = backupsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.json'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      return files;
    } catch (e) {
      debugPrint('Error listing backups: $e');
      return [];
    }
  }

  Future<bool> deleteBackupFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error deleting backup: $e');
      return false;
    }
  }

  Future<BackupImportResult?> importFromJsonFile({
    String? filePath,
    required bool replaceExisting,
  }) async {
    String? path = filePath;
    if (path == null || path.isEmpty) {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Chọn file backup Manga Reader',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: false,
      );
      path = result?.files.single.path;
    }
    if (path == null || path.isEmpty) return null;

    final raw = await File(path).readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('File backup không hợp lệ');
    }

    final tablesRaw = decoded['tables'];
    if (tablesRaw is! Map<String, dynamic>) {
      throw const FormatException('File backup thiếu trường tables');
    }

    final db = await DatabaseHelper.instance.database;
    final importedCounts = <String, int>{};

    await db.transaction((txn) async {
      if (replaceExisting) {
        for (final table in _tables.reversed) {
          await txn.delete(table);
        }
      }

      for (final table in _tables) {
        final rowsRaw = tablesRaw[table];
        if (rowsRaw is! List) continue;

        var count = 0;
        for (final rowRaw in rowsRaw) {
          if (rowRaw is! Map) continue;
          final row = rowRaw.map(
            (key, value) => MapEntry(key.toString(), value),
          );

          await txn.insert(
            table,
            row,
            conflictAlgorithm: replaceExisting
                ? ConflictAlgorithm.replace
                : ConflictAlgorithm.ignore,
          );
          count++;
        }
        importedCounts[table] = count;
      }
    });

    // Khôi phục danh sách truyện chữ (Local Novels) chuẩn cấu trúc NovelService (StringList)
    int importedNovelsCount = 0;
    final localNovelsRaw = decoded['local_novels'];
    if (localNovelsRaw is List) {
      final prefs = await SharedPreferences.getInstance();
      if (replaceExisting) {
        final stringList = <String>[];
        for (final item in localNovelsRaw) {
          if (item is Map) {
            stringList.add(jsonEncode(item));
            importedNovelsCount++;
          }
        }
        await prefs.setStringList('local_novels_v1', stringList);
      } else {
        final existingRaw = prefs.getStringList('local_novels_v1') ?? [];
        final existingPaths = <String>{};
        for (final s in existingRaw) {
          try {
            final m = jsonDecode(s);
            if (m is Map && m['path'] != null) {
              existingPaths.add(m['path'].toString());
            }
          } catch (_) {}
        }
        final updatedList = List<String>.from(existingRaw);
        for (final item in localNovelsRaw) {
          if (item is Map && item['path'] != null) {
            final pStr = item['path'].toString();
            if (!existingPaths.contains(pStr)) {
              updatedList.add(jsonEncode(item));
              existingPaths.add(pStr);
              importedNovelsCount++;
            }
          }
        }
        await prefs.setStringList('local_novels_v1', updatedList);
      }
    }

    // Khôi phục cài đặt người dùng (Preferences)
    final preferencesRaw = decoded['preferences'];
    if (preferencesRaw is Map) {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in preferencesRaw.entries) {
        final val = entry.value;
        if (val is bool) {
          await prefs.setBool(entry.key.toString(), val);
        } else if (val is int) {
          await prefs.setInt(entry.key.toString(), val);
        } else if (val is double) {
          await prefs.setDouble(entry.key.toString(), val);
        } else if (val is String) {
          await prefs.setString(entry.key.toString(), val);
        } else if (val is List) {
          await prefs.setStringList(
            entry.key.toString(),
            val.map((e) => e.toString()).toList(),
          );
        }
      }
    }

    await AchievementService.instance.reload();
    LibraryService.instance.notifyMappingChanged();
    await LibraryService.instance.refreshCategories();

    debugPrint('Imported Manga Reader backup: $importedCounts + $importedNovelsCount novels');
    return BackupImportResult(
      path: path,
      importedCounts: importedCounts,
      importedNovelsCount: importedNovelsCount,
    );
  }
}

class BackupImportResult {
  final String path;
  final Map<String, int> importedCounts;
  final int importedNovelsCount;

  const BackupImportResult({
    required this.path,
    required this.importedCounts,
    this.importedNovelsCount = 0,
  });

  int get totalRows =>
      importedCounts.values.fold<int>(0, (sum, value) => sum + value) +
      importedNovelsCount;
}
