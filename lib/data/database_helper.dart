import 'dart:async';
import 'package:manga_reader/data/models.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('comics.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  // ===========================
  // 🧱 Tạo bảng
  // ===========================
  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE comics (
        id TEXT PRIMARY KEY,
        title TEXT,
        author TEXT,
        description TEXT,
        coverUrl TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE chapters (
        id TEXT PRIMARY KEY,
        comicId TEXT,
        name TEXT,
        number INTEGER,
        FOREIGN KEY (comicId) REFERENCES comics (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE pages (
        id TEXT PRIMARY KEY,
        chapterId TEXT,
        imageUrl TEXT,
        pageIndex INTEGER,
        FOREIGN KEY (chapterId) REFERENCES chapters (id) ON DELETE CASCADE
      )
    ''');

    // ✅ Chèn dữ liệu mặc định từ mock_catalog
    // await _insertMockData(db); // REMOVED MOCK DATA

    // 🕰️ Tạo bảng history
    await db.execute('''
      CREATE TABLE IF NOT EXISTS history (
        comicId TEXT PRIMARY KEY,
        chapterId TEXT,
        lastPageIndex INTEGER,
        updatedAt INTEGER
      )
    ''');
  }

  // ===========================
  // 📥 Import dữ liệu mock (Đã xóa)
  // ===========================
  // Future<void> _insertMockData(Database db) async {}

  // ===========================
  // 📚 CRUD cơ bản
  // ===========================

  Future<List<Comic>> getAllComics() async {
    final db = await instance.database;
    final result = await db.query('comics');
    return result
        .map(
          (e) => Comic(
            id: e['id'] as String,
            title: e['title'] as String,
            author: e['author'] as String,
            description: e['description'] as String,
            coverUrl: e['coverUrl'] as String,
          ),
        )
        .toList();
  }

  Future<List<Chapter>> getChaptersByComic(String comicId) async {
    final db = await instance.database;
    final result = await db.query(
      'chapters',
      where: 'comicId = ?',
      whereArgs: [comicId],
    );
    return result
        .map(
          (e) => Chapter(
            id: e['id'] as String,
            comicId: e['comicId'] as String,
            name: e['name'] as String,
            number: e['number'] as int,
          ),
        )
        .toList();
  }

  // ===========================
  // 🕰️ History
  // ===========================

  Future<void> saveHistory(ReadingHistory history) async {
    final db = await instance.database;
    // Đảm bảo bảng tồn tại (cho trường hợp update app)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS history (
        comicId TEXT PRIMARY KEY,
        chapterId TEXT,
        lastPageIndex INTEGER,
        updatedAt INTEGER
      )
    ''');

    await db.insert(
      'history',
      history.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ReadingHistory>> getHistory() async {
    final db = await instance.database;
    // Đảm bảo bảng tồn tại
    try {
      final result = await db.query('history', orderBy: 'updatedAt DESC');
      return result.map((e) => ReadingHistory.fromMap(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<ReadingHistory?> getHistoryForComic(String comicId) async {
    final db = await instance.database;
    try {
      final result = await db.query(
        'history',
        where: 'comicId = ?',
        whereArgs: [comicId],
      );
      if (result.isNotEmpty) {
        return ReadingHistory.fromMap(result.first);
      }
    } catch (_) {}
    return null;
  }

  Future<void> clearAll() async {
    final db = await instance.database;
    await db.delete('pages');
    await db.delete('chapters');
    await db.delete('comics');
  }

  Future<void> clearHistory() async {
    final db = await instance.database;
    await db.delete('history');
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
