import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database_helper.dart';

enum MangaReadingStatus { reading, completed, paused, dropped, planToRead }

class LibraryStatusService extends ChangeNotifier {
  LibraryStatusService._();

  static final LibraryStatusService instance = LibraryStatusService._();

  static (String label, IconData icon, Color color) getStatusDisplay(
    MangaReadingStatus status,
  ) {
    switch (status) {
      case MangaReadingStatus.reading:
        return ('Đang đọc', Icons.menu_book_rounded, Colors.greenAccent);
      case MangaReadingStatus.completed:
        return ('Đã xong', Icons.check_circle_outline_rounded, Colors.blueAccent);
      case MangaReadingStatus.paused:
        return ('Tạm dừng', Icons.pause_circle_outline_rounded, Colors.amberAccent);
      case MangaReadingStatus.planToRead:
        return ('Dự định đọc', Icons.bookmark_outline_rounded, Colors.purpleAccent);
      case MangaReadingStatus.dropped:
        return ('Bỏ dở', Icons.cancel_outlined, Colors.redAccent);
    }
  }

  Future<void> setStatus(String mangaId, MangaReadingStatus status) async {
    final current = await getEntry(mangaId);
    await _saveEntry(
      LibraryStatusEntry(
        mangaId: mangaId,
        status: status,
        tags: current?.tags ?? const [],
        updatedAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  Future<void> setTags(String mangaId, List<String> tags) async {
    final current = await getEntry(mangaId);
    await _saveEntry(
      LibraryStatusEntry(
        mangaId: mangaId,
        status: current?.status ?? MangaReadingStatus.reading,
        tags: tags
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList(),
        updatedAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  Future<LibraryStatusEntry?> getEntry(String mangaId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'library_status',
      where: 'mangaId = ?',
      whereArgs: [mangaId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LibraryStatusEntry.fromMap(rows.first);
  }

  Future<List<LibraryStatusEntry>> getAll() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('library_status', orderBy: 'updatedAt DESC');
    return rows.map(LibraryStatusEntry.fromMap).toList();
  }

  Future<List<String>> getAllTags() async {
    final entries = await getAll();
    final tags = <String>{};
    for (final entry in entries) {
      tags.addAll(entry.tags);
    }
    return tags.toList()..sort();
  }

  Future<void> _saveEntry(LibraryStatusEntry entry) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'library_status',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeEntry(String mangaId) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'library_status',
      where: 'mangaId = ?',
      whereArgs: [mangaId],
    );
    notifyListeners();
  }
}

class LibraryStatusEntry {
  final String mangaId;
  final MangaReadingStatus status;
  final List<String> tags;
  final DateTime updatedAt;

  const LibraryStatusEntry({
    required this.mangaId,
    required this.status,
    required this.tags,
    required this.updatedAt,
  });

  factory LibraryStatusEntry.fromMap(Map<String, dynamic> map) {
    return LibraryStatusEntry(
      mangaId: map['mangaId']?.toString() ?? '',
      status: _statusFromString(map['status']?.toString()),
      tags: _readTags(map['tagsJson']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        _readInt(map['updatedAt']),
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'mangaId': mangaId,
      'status': status.name,
      'tagsJson': jsonEncode(tags),
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  static MangaReadingStatus _statusFromString(String? value) {
    return MangaReadingStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => MangaReadingStatus.reading,
    );
  }

  static List<String> _readTags(dynamic value) {
    if (value is List) return value.map((tag) => tag.toString()).toList();
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded.map((tag) => tag.toString()).toList();
      } catch (e) {
        // Ignored to prevent crashes from invalid JSON
      }
    }
    return const [];
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
