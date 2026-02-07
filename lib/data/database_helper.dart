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
      version: 8, // Tăng version lên 8
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE history ADD COLUMN chapterTitle TEXT');
    }
    if (oldVersion < 3) {
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
    if (oldVersion < 4) {
      await _createLibraryTables(db);
    }
    if (oldVersion < 5) {
      try {
        await db.execute(
          'ALTER TABLE lib_categories ADD COLUMN sortIndex INTEGER DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 6) {
      await _createDownloadTable(db);
    }
    if (oldVersion < 7) {
      try {
        await db.execute('ALTER TABLE comics ADD COLUMN genres TEXT');
      } catch (_) {}
    }
    if (oldVersion < 8) {
      // Thêm cột isSynced cho tính năng Offline Sync
      try {
        await db.execute(
          'ALTER TABLE history ADD COLUMN isSynced INTEGER DEFAULT 0',
        );
      } catch (_) {}
    }
  }

  Future<void> _createLibraryTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lib_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE,
        sortIndex INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lib_mapping (
        mangaId TEXT,
        categoryName TEXT,
        PRIMARY KEY (mangaId, categoryName)
      )
    ''');
    // Chèn danh mục mặc định
    await db.insert('lib_categories', {
      'name': 'Mặc định',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _createDownloadTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS downloaded_chapters (
        chapterId TEXT PRIMARY KEY,
        mangaId TEXT NOT NULL,
        mangaTitle TEXT,
        chapterTitle TEXT,
        localPath TEXT NOT NULL,
        fileSize INTEGER DEFAULT 0,
        downloadDate INTEGER NOT NULL
      )
    ''');
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
        isSynced INTEGER DEFAULT 0,
        PRIMARY KEY (userId, comicId)
      )
    ''');

    // 📚 Tạo bảng Library (Offline)
    await _createLibraryTables(db);

    // 📥 Tạo bảng Download
    await _createDownloadTable(db);

    // Ensure comics table has genres column (for fresh install)
    try {
      await db.execute('ALTER TABLE comics ADD COLUMN genres TEXT');
    } catch (_) {}
  }

  // ===========================
  // 📚 Local Manga Info (Offline Support)
  // ===========================

  Future<void> saveLocalManga(Manga manga) async {
    final db = await instance.database;
    await db.insert(
      'comics',
      manga.toMap(), // Manga.toMap() already handles jsonEncode for genres
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Manga?> getLocalManga(String mangaId) async {
    final db = await instance.database;
    final result = await db.query(
      'comics',
      where: 'id = ?',
      whereArgs: [mangaId],
    );
    if (result.isNotEmpty) {
      return Manga.fromMap(result.first);
    }
    return null;
  }

  Future<List<Manga>> getAllLocalMangas() async {
    final db = await instance.database;
    final result = await db.query('comics');
    return result.map((json) => Manga.fromMap(json)).toList();
  }

  // ===========================
  // 🕰️ History
  // ===========================

  Future<void> saveHistory(ReadingHistory history) async {
    final db = await instance.database;
    // Đảm bảo bảng tồn tại (cho trường hợp update app)
    // Giữ nguyên tên bảng và tên cột để tránh mất dữ liệu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS history (
        userId TEXT,
        comicId TEXT,
        chapterId TEXT,
        chapterTitle TEXT,
        lastPageIndex INTEGER,
        updatedAt INTEGER,
        isSynced INTEGER DEFAULT 0,
        PRIMARY KEY (userId, comicId)
      )
    ''');

    // Filter map để chỉ giữ các key tồn tại trong DB schema
    final map = history.toMap();
    // Chúng ta cần 'comicId' cho cột DB, nếu map có 'mangaId' ta sẽ dùng nó cho 'comicId' nếu cần
    // Nhưng ReadingHistory.toMap() hiện tại đã trả về cả hai.
    // SQFLite sẽ ignore hoặc lỗi nếu có key thừa? Thường là lỗi.
    // Chúng ta sẽ tạo map mới sạch sẽ.
    final dbMap = {
      'userId': map['userId'],
      'comicId':
          map['mangaId'] ?? map['comicId'], // Ưu tiên mangaId, fallback comicId
      'chapterId': map['chapterId'],
      'chapterTitle': map['chapterTitle'],
      'lastPageIndex': map['lastPageIndex'],
      'updatedAt': map['updatedAt'],
      'isSynced': 0, // Mặc định là chưa sync khi mới lưu local
    };

    await db.insert(
      'history',
      dbMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Lấy danh sách lịch sử chưa đồng bộ (isSynced = 0) của user
  Future<List<ReadingHistory>> getUnsyncedHistory(String userId) async {
    final db = await instance.database;
    try {
      final result = await db.query(
        'history',
        where: 'userId = ? AND isSynced = 0',
        whereArgs: [userId],
      );
      return result.map((e) => ReadingHistory.fromMap(e)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Đánh dấu lịch sử là đã đồng bộ (isSynced = 1)
  Future<void> markHistoryAsSynced(String userId, String comicId) async {
    final db = await instance.database;
    await db.update(
      'history',
      {'isSynced': 1},
      where: 'userId = ? AND comicId = ?',
      whereArgs: [userId, comicId],
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

  Future<ReadingHistory?> getHistoryForManga(
    String userId,
    String mangaId,
  ) async {
    final db = await instance.database;
    try {
      final result = await db.query(
        'history',
        where: 'userId = ? AND comicId = ?', // Vẫn query cột comicId
        whereArgs: [userId, mangaId],
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

  // ===========================
  // 📥 Download Management
  // ===========================

  /// Lưu thông tin chương đã tải về
  Future<void> saveDownload({
    required String chapterId,
    required String mangaId,
    required String mangaTitle,
    required String chapterTitle,
    required String localPath,
    required int fileSize,
  }) async {
    final db = await instance.database;
    await db.insert('downloaded_chapters', {
      'chapterId': chapterId,
      'mangaId': mangaId,
      'mangaTitle': mangaTitle,
      'chapterTitle': chapterTitle,
      'localPath': localPath,
      'fileSize': fileSize,
      'downloadDate': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Kiểm tra chương đã được tải chưa
  Future<bool> isChapterDownloaded(String chapterId) async {
    final db = await instance.database;
    final result = await db.query(
      'downloaded_chapters',
      where: 'chapterId = ?',
      whereArgs: [chapterId],
    );
    return result.isNotEmpty;
  }

  /// Lấy thông tin download của một chương
  Future<Map<String, dynamic>?> getDownload(String chapterId) async {
    final db = await instance.database;
    final result = await db.query(
      'downloaded_chapters',
      where: 'chapterId = ?',
      whereArgs: [chapterId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  /// Lấy tất cả chương đã tải
  Future<List<Map<String, dynamic>>> getAllDownloads() async {
    final db = await instance.database;
    return await db.query('downloaded_chapters', orderBy: 'downloadDate DESC');
  }

  /// Lấy danh sách download theo mangaId
  Future<List<Map<String, dynamic>>> getDownloadsByManga(String mangaId) async {
    final db = await instance.database;
    return await db.query(
      'downloaded_chapters',
      where: 'mangaId = ?',
      whereArgs: [mangaId],
      orderBy: 'downloadDate DESC',
    );
  }

  /// Xóa một chương đã tải
  Future<void> deleteDownload(String chapterId) async {
    final db = await instance.database;
    await db.delete(
      'downloaded_chapters',
      where: 'chapterId = ?',
      whereArgs: [chapterId],
    );
  }

  /// Xóa tất cả download của một manga
  Future<void> deleteDownloadsByManga(String mangaId) async {
    final db = await instance.database;
    await db.delete(
      'downloaded_chapters',
      where: 'mangaId = ?',
      whereArgs: [mangaId],
    );
  }

  /// Cập nhật mangaId cho một chương đã tải (Dùng cho Silent Repair)
  Future<void> updateDownloadMangaId(String chapterId, String mangaId) async {
    final db = await instance.database;
    await db.update(
      'downloaded_chapters',
      {'mangaId': mangaId},
      where: 'chapterId = ?',
      whereArgs: [chapterId],
    );
  }

  /// Lấy tổng dung lượng đã tải
  Future<int> getTotalDownloadSize() async {
    final db = await instance.database;
    final result = await db.rawQuery(
      'SELECT SUM(fileSize) as total FROM downloaded_chapters',
    );
    return (result.first['total'] as int?) ?? 0;
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
