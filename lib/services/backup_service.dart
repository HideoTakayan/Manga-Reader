import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database_helper.dart';
import 'folder_service.dart';

class BackupService {
  BackupService._();

  static final BackupService instance = BackupService._();

  static const int currentSchemaVersion = 1;

  static const List<String> _tables = [
    'comics',
    'history',
    'lib_categories',
    'lib_mapping',
    'reader_progress',
    'bookmarks',
    'catalog_cache',
    'library_status',
  ];

  Future<String?> exportToJsonFile() async {
    final db = await DatabaseHelper.instance.database;
    final data = <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': <String, dynamic>{},
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

  Future<BackupImportResult?> importFromJsonFile({
    required bool replaceExisting,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Chọn file backup Manga Reader',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: false,
    );
    final path = result?.files.single.path;
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

    debugPrint('Imported Manga Reader backup: $importedCounts');
    return BackupImportResult(path: path, importedCounts: importedCounts);
  }
}

class BackupImportResult {
  final String path;
  final Map<String, int> importedCounts;

  const BackupImportResult({required this.path, required this.importedCounts});

  int get totalRows =>
      importedCounts.values.fold<int>(0, (sum, value) => sum + value);
}
