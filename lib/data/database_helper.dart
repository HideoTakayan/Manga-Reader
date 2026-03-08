import 'dart:async';
import 'package:manga_reader/data/models.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// Quản lý toàn bộ dữ liệu cục bộ của app: lịch sử đọc, file đã tải, thư viện cá nhân.
// Dùng pattern Singleton — cả app chỉ có 1 instance, tránh mở DB nhiều lần.
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database; // Giữ kết nối DB, null = chưa mở lần nào
  DatabaseHelper._init(); // Constructor private — không cho tạo instance mới từ bên ngoài

  // Lazy init: lần đầu gọi thì mở DB, các lần sau trả về kết nối cũ luôn.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('comics.db');
    return _database!;
  }

  // Tìm thư mục lưu trữ của thiết bị và mở file DB.
  // version: tăng lên khi thay đổi cấu trúc bảng. onCreate chạy lần đầu, onUpgrade chạy khi version tăng.
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 8,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  // Migration: thêm bảng/cột mới mà không xóa dữ liệu cũ.
  // Mỗi khối if xử lý một lần nâng cấp — tăng version trong _initDB thì phải thêm khối tương ứng ở đây.
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE history ADD COLUMN chapterTitle TEXT');
    }
    if (oldVersion < 3) {
      // Tạo lại bảng history với PRIMARY KEY kép để mỗi user chỉ có 1 bản ghi cho mỗi truyện.
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
      // isSynced: cờ đánh dấu bản ghi lịch sử đã được đẩy lên Firestore chưa (0 = chưa, 1 = rồi).
      try {
        await db.execute(
          'ALTER TABLE history ADD COLUMN isSynced INTEGER DEFAULT 0',
        );
      } catch (_) {}
    }
  }

  // Tạo 2 bảng thư viện cá nhân:
  // lib_categories: danh mục người dùng tự đặt tên. lib_mapping: nối mangaId <-> categoryName (nhiều-nhiều).
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
    await db.insert('lib_categories', {
      'name': 'Mặc định',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // Tạo bảng lưu thông tin các chương đã tải về máy (localPath là đường dẫn file ZIP thực tế).
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

  // Chạy một lần duy nhất khi cài app — tạo toàn bộ bảng với cấu trúc mới nhất.
  Future _createDB(Database db, int version) async {
    // Cache thông tin bộ truyện để dùng offline
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

    // PRIMARY KEY (userId, comicId): mỗi user chỉ có 1 bản ghi / 1 truyện — đọc lại thì ghi đè.
    // isSynced: 0 = chưa đồng bộ lên Cloud, 1 = đã đồng bộ.
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

    await _createLibraryTables(db);
    await _createDownloadTable(db);

    try {
      await db.execute('ALTER TABLE comics ADD COLUMN genres TEXT');
    } catch (_) {}
  }

  // ── TRUYỆN CỤC BỘ ──────────────────────────────────────────────────────────

  // Lưu (hoặc ghi đè) thông tin bộ truyện vào DB cục bộ.
  Future<void> saveLocalManga(Manga manga) async {
    final db = await instance.database;
    await db.insert(
      'comics',
      manga.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Lấy thông tin bộ truyện theo ID. Trả về null nếu chưa có trong DB.
  Future<Manga?> getLocalManga(String mangaId) async {
    final db = await instance.database;
    final result = await db.query(
      'comics',
      where: 'id = ?',
      whereArgs: [mangaId],
    );
    if (result.isNotEmpty) return Manga.fromMap(result.first);
    return null;
  }

  // Lấy toàn bộ truyện đang cache cục bộ.
  Future<List<Manga>> getAllLocalMangas() async {
    final db = await instance.database;
    final result = await db.query('comics');
    return result.map((json) => Manga.fromMap(json)).toList();
  }

  // ── LỊCH SỬ ĐỌC ────────────────────────────────────────────────────────────

  // Lưu tiến độ đọc. Ghi đè bản ghi cũ nếu đã có (cùng userId + comicId).
  // Luôn đặt isSynced = 0 để SyncService biết cần push lên Firestore lần sau có mạng.
  Future<void> saveHistory(ReadingHistory history) async {
    final db = await instance.database;
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

    // Tạo map sạch đúng với schema — tránh lỗi do ReadingHistory.toMap() trả về key thừa.
    final map = history.toMap();
    final dbMap = {
      'userId': map['userId'],
      'comicId': map['mangaId'] ?? map['comicId'],
      'chapterId': map['chapterId'],
      'chapterTitle': map['chapterTitle'],
      'lastPageIndex': map['lastPageIndex'],
      'updatedAt': map['updatedAt'],
      'isSynced': 0,
    };

    await db.insert(
      'history',
      dbMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Lấy các bản ghi lịch sử chưa đồng bộ (isSynced = 0).
  // SyncService gọi hàm này khi app khởi động có mạng để push lên Firestore.
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

  // Đánh dấu một bản ghi lịch sử là đã đồng bộ thành công lên Firestore.
  Future<void> markHistoryAsSynced(String userId, String comicId) async {
    final db = await instance.database;
    await db.update(
      'history',
      {'isSynced': 1},
      where: 'userId = ? AND comicId = ?',
      whereArgs: [userId, comicId],
    );
  }

  // Lấy toàn bộ lịch sử đọc của user, mới nhất lên đầu.
  Future<List<ReadingHistory>> getHistory(String userId) async {
    final db = await instance.database;
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

  // Lấy lịch sử của một bộ truyện cụ thể — biết user đang đọc dở chương nào.
  Future<ReadingHistory?> getHistoryForManga(
    String userId,
    String mangaId,
  ) async {
    final db = await instance.database;
    try {
      final result = await db.query(
        'history',
        where: 'userId = ? AND comicId = ?',
        whereArgs: [userId, mangaId],
      );
      if (result.isNotEmpty) return ReadingHistory.fromMap(result.first);
    } catch (_) {}
    return null;
  }

  // Xóa toàn bộ cache (pages → chapters → comics theo thứ tự để không vi phạm FOREIGN KEY).
  Future<void> clearAll() async {
    final db = await instance.database;
    await db.delete('pages');
    await db.delete('chapters');
    await db.delete('comics');
  }

  // Xóa toàn bộ lịch sử đọc của một user.
  Future<void> clearHistory(String userId) async {
    final db = await instance.database;
    try {
      await db.delete('history', where: 'userId = ?', whereArgs: [userId]);
    } catch (e) {
      print('Error clearing history: $e');
    }
  }

  // ── QUẢN LÝ FILE ĐÃ TẢI ────────────────────────────────────────────────────

  // Ghi thông tin chương vừa tải xong. DownloadService gọi sau khi file lưu thành công.
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

  // Kiểm tra chương đã tải chưa. ReaderProvider gọi đầu tiên để chọn đọc online hay offline.
  Future<bool> isChapterDownloaded(String chapterId) async {
    final db = await instance.database;
    final result = await db.query(
      'downloaded_chapters',
      where: 'chapterId = ?',
      whereArgs: [chapterId],
    );
    return result.isNotEmpty;
  }

  // Lấy thông tin download (bao gồm localPath) để đọc file từ ổ cứng.
  Future<Map<String, dynamic>?> getDownload(String chapterId) async {
    final db = await instance.database;
    final result = await db.query(
      'downloaded_chapters',
      where: 'chapterId = ?',
      whereArgs: [chapterId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  // Lấy tất cả chương đã tải, mới nhất lên đầu.
  Future<List<Map<String, dynamic>>> getAllDownloads() async {
    final db = await instance.database;
    return await db.query('downloaded_chapters', orderBy: 'downloadDate DESC');
  }

  // Lấy danh sách chương đã tải của một bộ truyện cụ thể.
  Future<List<Map<String, dynamic>>> getDownloadsByManga(String mangaId) async {
    final db = await instance.database;
    return await db.query(
      'downloaded_chapters',
      where: 'mangaId = ?',
      whereArgs: [mangaId],
      orderBy: 'downloadDate DESC',
    );
  }

  // Xóa bản ghi download của một chương (thường đi kèm xóa file vật lý).
  Future<void> deleteDownload(String chapterId) async {
    final db = await instance.database;
    await db.delete(
      'downloaded_chapters',
      where: 'chapterId = ?',
      whereArgs: [chapterId],
    );
  }

  // Xóa toàn bộ bản ghi download của một bộ truyện.
  Future<void> deleteDownloadsByManga(String mangaId) async {
    final db = await instance.database;
    await db.delete(
      'downloaded_chapters',
      where: 'mangaId = ?',
      whereArgs: [mangaId],
    );
  }

  // Sửa mangaId của một bản ghi download (dùng trong luồng Silent Repair).
  Future<void> updateDownloadMangaId(String chapterId, String mangaId) async {
    final db = await instance.database;
    await db.update(
      'downloaded_chapters',
      {'mangaId': mangaId},
      where: 'chapterId = ?',
      whereArgs: [chapterId],
    );
  }

  // Tính tổng dung lượng đĩa của tất cả file đã tải (byte). Dùng rawQuery vì sqflite không hỗ trợ SUM() trực tiếp.
  Future<int> getTotalDownloadSize() async {
    final db = await instance.database;
    final result = await db.rawQuery(
      'SELECT SUM(fileSize) as total FROM downloaded_chapters',
    );
    return (result.first['total'] as int?) ?? 0;
  }

  // Đóng kết nối DB (thường không cần gọi thủ công).
  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
