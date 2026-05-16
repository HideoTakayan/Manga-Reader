import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../data/database_helper.dart';
import '../../data/models_cloud.dart';

class CatalogCacheService {
  CatalogCacheService._();

  static final CatalogCacheService instance = CatalogCacheService._();

  Future<void> saveCatalog(List<CloudManga> mangas) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();

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
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  Future<List<CloudManga>> getCachedCatalog() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('catalog_cache', orderBy: 'updatedAt DESC');
    return rows.map(_fromCacheRow).whereType<CloudManga>().toList();
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

      final matchesIncluded = includedGenres.keys.every(
        (genre) => manga.genres.contains(genre),
      );
      final matchesExcluded = excludedGenres.keys.every(
        (genre) => !manga.genres.contains(genre),
      );
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

  CloudManga? _fromCacheRow(Map<String, dynamic> row) {
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
        updatedAt: DateTime.fromMillisecondsSinceEpoch(_readInt(row['updatedAt'])),
        genres: _readStringList(row['genresJson']),
        status: row['status']?.toString() ?? 'Đang Cập Nhật',
        viewCount: _readInt(row['viewCount']),
        likeCount: _readInt(row['likeCount']),
      );
    } catch (_) {
      return null;
    }
  }

  List<String> _aliasesFor(CloudManga manga) {
    final aliases = <String>{manga.title, normalize(manga.title)};
    return aliases.where((alias) => alias.isNotEmpty).toList();
  }

  List<String> _readStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String && value.isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    }
    return const [];
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
