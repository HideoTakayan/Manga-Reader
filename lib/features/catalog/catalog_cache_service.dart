import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../data/database_helper.dart';
import '../../data/models_cloud.dart';

class CatalogCacheService {
  CatalogCacheService._();

  static final CatalogCacheService instance = CatalogCacheService._();

  Future<void> saveCatalog(List<CloudManga> mangas) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await db.transaction((txn) async {
      // Clear old cache so deleted mangas on Drive are also removed locally
      await txn.delete('catalog_cache');
      
      final batch = txn.batch();
      for (final manga in mangas) {
        batch.insert('catalog_cache', {
          'mangaId': manga.id,
          'title': manga.title,
          'normalizedTitle': normalize(manga.title),
          'aliasesJson': jsonEncode(_aliasesFor(manga)),
          'genresJson': jsonEncode(manga.genres),
          'author': manga.author,
          'status': manga.status,
          'coverFileId': manga.coverFileId,
          'updatedAt': manga.updatedAt.millisecondsSinceEpoch,
          'viewCount': manga.viewCount,
          'likeCount': manga.likeCount,
          'rawJson': jsonEncode(manga.toMap()),
          'cachedAt': now,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<CloudManga>> getCachedCatalog() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('catalog_cache', orderBy: 'updatedAt DESC');
    if (rows.isEmpty) return [];
    
    // Parse JSON in background isolate to prevent UI jank
    return await compute(_parseCacheRows, rows);
  }

  // Top-level or static function for compute
  static List<CloudManga> _parseCacheRows(List<Map<String, dynamic>> rows) {
    return rows.map(_fromCacheRowStatic).whereType<CloudManga>().toList();
  }

  Future<List<CloudManga>> search({
    required String query,
    required Map<String, bool> includedGenres,
    required Map<String, bool> excludedGenres,
    String? status,
  }) async {
    final normalizedQuery = normalize(query);
    final catalog = await getCachedCatalog();

    return catalog.where((manga) {
      final searchText = normalize(
        '${manga.title} ${manga.author} ${manga.genres.join(' ')}',
      );
      final matchesQuery =
          normalizedQuery.isEmpty || searchText.contains(normalizedQuery);

      final matchesIncluded = includedGenres.entries
          .where((e) => e.value)
          .every((e) => manga.genres.contains(e.key));
      final matchesExcluded = excludedGenres.entries
          .where((e) => e.value)
          .every((e) => !manga.genres.contains(e.key));
      final matchesStatus = status == null || manga.status == status;

      return matchesQuery &&
          matchesIncluded &&
          matchesExcluded &&
          matchesStatus;
    }).toList();
  }

  Future<DateTime?> getLastCachedAt() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      'SELECT MAX(cachedAt) as cachedAt FROM catalog_cache',
    );
    if (rows.isEmpty) return null;
    final value = rows.first['cachedAt'];
    final millis = value is int
        ? value
        : value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    if (millis == null || millis <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  String normalize(String input) {
    var value = input.toLowerCase().trim();
    const from =
        'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const to =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

    for (var i = 0; i < from.length; i++) {
      value = value.replaceAll(from[i], to[i]);
    }
    return value.replaceAll(RegExp(r'\s+'), ' ');
  }

  static CloudManga? _fromCacheRowStatic(Map<String, dynamic> row) {
    try {
      final raw = row['rawJson']?.toString();
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return CloudManga.fromMap(decoded);
      }

      return CloudManga(
        id: row['mangaId']?.toString() ?? '',
        title: row['title']?.toString() ?? '',
        author: row['author']?.toString() ?? '',
        description: '',
        coverFileId: row['coverFileId']?.toString() ?? '',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(_readIntStatic(row['updatedAt'])),
        genres: _readStringListStatic(row['genresJson']),
        status: row['status']?.toString() ?? 'Đang Cập Nhật',
        viewCount: _readIntStatic(row['viewCount']),
        likeCount: _readIntStatic(row['likeCount']),
      );
    } catch (_) {
      return null;
    }
  }

  List<String> _aliasesFor(CloudManga manga) {
    final aliases = <String>{manga.title, normalize(manga.title)};
    return aliases.where((alias) => alias.isNotEmpty).toList();
  }

  static List<String> _readStringListStatic(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String && value.isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    }
    return const [];
  }

  static int _readIntStatic(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
