import 'dart:async';
import 'package:manga_reader/data/models.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'mock_catalog.dart';

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
    await _insertMockData(db);
  }

  // ===========================
  // 📥 Import dữ liệu mock
  // ===========================
  Future<void> _insertMockData(Database db) async {
    for (final comic in MockCatalog.comics()) {
      await db.insert('comics', {
        'id': comic.id,
        'title': comic.title,
        'author': comic.author,
        'description': comic.description,
        'coverUrl': comic.coverUrl,
      });

      final chapters = MockCatalog.chaptersOf(comic.id);
      for (final chap in chapters) {
        await db.insert('chapters', {
          'id': chap.id,
          'comicId': comic.id,
          'name': chap.name,
          'number': chap.number,
        });

        final pages = MockCatalog.pagesOf(chap.id);
        for (final page in pages) {
          await db.insert('pages', {
            'id': page.id,
            'chapterId': chap.id,
            'imageUrl': page.imageUrl,
            'pageIndex': page.index,
          });
        }
      }
    }
  }

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

  Future<List<PageImage>> getPagesByChapter(String chapterId) async {
    final db = await instance.database;
    final result = await db.query(
      'pages',
      where: 'chapterId = ?',
      whereArgs: [chapterId],
    );
    return result
        .map(
          (e) => PageImage(
            id: e['id'] as String,
            chapterId: e['chapterId'] as String,
            imageUrl: e['imageUrl'] as String,
            index: e['pageIndex'] as int,
          ),
        )
        .toList();
  }

  // Xoá toàn bộ DB (nếu muốn reset)
  Future<void> clearAll() async {
    final db = await instance.database;
    await db.delete('pages');
    await db.delete('chapters');
    await db.delete('comics');
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
