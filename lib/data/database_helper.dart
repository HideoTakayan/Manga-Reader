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
    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE history ADD COLUMN chapterTitle TEXT');
    }
    if (oldVersion < 3) {
      // Tái tạo bảng history để thêm cột userId và cập nhật Primary Key
      await db.execute('DROP TABLE IF EXISTS history');
      await db.execute('''
        CREATE TABLE history (
          userId TEXT,
          comicId TEXT,
          chapterId TEXT,
          chapterTitle TEXT,
          lastPageIndex INTEGER,
          updatedAt INTEGER,
          PRIMARY KEY (userId, comicId)
        )
      ''');
    }
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

    // 🕰️ Tạo bảng history
    await db.execute('''
      CREATE TABLE IF NOT EXISTS history (
        userId TEXT,
        comicId TEXT,
        chapterId TEXT,
        chapterTitle TEXT,
        lastPageIndex INTEGER,
        updatedAt INTEGER,
        PRIMARY KEY (userId, comicId)
      )
    ''');
  }

  // ... (Methods omitted)

  // ===========================
  // 🕰️ History
  // ===========================

  Future<void> saveHistory(ReadingHistory history) async {
    final db = await instance.database;
    // Đảm bảo bảng tồn tại (cho trường hợp update app)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS history (
        userId TEXT,
        comicId TEXT,
        chapterId TEXT,
        chapterTitle TEXT,
        lastPageIndex INTEGER,
        updatedAt INTEGER,
        PRIMARY KEY (userId, comicId)
      )
    ''');

    await db.insert(
      'history',
      history.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ReadingHistory>> getHistory(String userId) async {
    final db = await instance.database;
    // Đảm bảo bảng tồn tại
    try {
      final result = await db.query(
        'history',
        where: 'userId = ?',
        whereArgs: [userId],
        orderBy: 'updatedAt DESC',
      );
      return result.map((e) => ReadingHistory.fromMap(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<ReadingHistory?> getHistoryForComic(
    String userId,
    String comicId,
  ) async {
    final db = await instance.database;
    try {
      final result = await db.query(
        'history',
        where: 'userId = ? AND comicId = ?',
        whereArgs: [userId, comicId],
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

  Future<void> clearHistory(String userId) async {
    final db = await instance.database;
    try {
      await db.delete('history', where: 'userId = ?', whereArgs: [userId]);
    } catch (e) {
      print('Error clearing history: $e');
    }
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
