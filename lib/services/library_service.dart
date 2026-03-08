import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../data/database_helper.dart';

// LibraryService: quản lý Categories và Mapping trong SQLite local.
// Dùng StreamController thủ công vì SQLite không có built-in reactive streams như Firestore.
// Mỗi khi data thay đổi, service tự push update vào controller để UI rebuild.
class LibraryService {
  static final LibraryService instance = LibraryService._();
  LibraryService._();

  final _dbHelper = DatabaseHelper.instance;

  final _categoriesController =
      StreamController<List<String>>.broadcast(); 
  final _mappingController = StreamController<void>.broadcast();
  Stream<List<String>> streamCategories() {
    _refreshCategories();
    return _categoriesController.stream;
  }

  Future<void> _refreshCategories() async {
    final db = await _dbHelper.database;
    final maps = await db.query('lib_categories', orderBy: 'sortIndex ASC');
    final cats = maps.map((m) => m['name'] as String).toList();
    if (cats.isEmpty) {
      // Auto-tạo category "Mặc định" nếu user xóa hết — đảm bảo có ít nhất 1 category
      await addCategory('Mặc định');
      return _refreshCategories(); // Gọi lại để emit category mới
    }
    _categoriesController.add(cats);
  }

  Future<void> addCategory(String name) async {
    final db = await _dbHelper.database;
    final countMap = await db.rawQuery(
      'SELECT count(*) as count FROM lib_categories',
    );
    final count = countMap.first['count'] as int;
    await db.insert(
      'lib_categories',
      {'name': name, 'sortIndex': count},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    ); 
    _refreshCategories();
  }

  Future<void> updateCategory(String oldName, String newName) async {
    final db = await _dbHelper.database;
    // transaction: đảm bảo cả 2 update thành công hoặc cả 2 rollback
    await db.transaction((txn) async {
      await txn.update(
        'lib_categories',
        {'name': newName},
        where: 'name = ?',
        whereArgs: [oldName],
      );
      await txn.update(
        'lib_mapping',
        {'categoryName': newName},
        where: 'categoryName = ?',
        whereArgs: [oldName],
      );
    });
    _refreshCategories();
    _mappingController.add(null);
  }

  Future<void> reorderCategories(List<String> orderedNames) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (int i = 0; i < orderedNames.length; i++) {
      batch.update(
        'lib_categories',
        {'sortIndex': i},
        where: 'name = ?',
        whereArgs: [orderedNames[i]],
      );
    }
    await batch.commit(
      noResult: true,
    ); 
    _refreshCategories();
  }

  Future<void> removeCategory(String name) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete(
        'lib_mapping',
        where: 'categoryName = ?',
        whereArgs: [name],
      );
      await txn.delete('lib_categories', where: 'name = ?', whereArgs: [name]);
    });
    _refreshCategories();
    _mappingController.add(null);
  }

  Stream<List<String>> streamMangaCategories(String mangaId) {
    final controller = StreamController<List<String>>();

    Future<void> fetch() async {
      final db = await _dbHelper.database;
      final maps = await db.query(
        'lib_mapping',
        where: 'mangaId = ?',
        whereArgs: [mangaId],
      );
      controller.add(maps.map((m) => m['categoryName'] as String).toList());
    }

    fetch();
    final subscription = _mappingController.stream.listen((_) => fetch());
    controller.onCancel = () =>
        subscription.cancel(); 
    return controller.stream;
  }

  Future<void> setMangaCategories(
    String mangaId,
    List<String> categories,
  ) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete(
        'lib_mapping',
        where: 'mangaId = ?',
        whereArgs: [mangaId],
      );
      for (var cat in categories) {
        await txn.insert('lib_mapping', {
          'mangaId': mangaId,
          'categoryName': cat,
        });
      }
    });
    _mappingController.add(null);
  }

  Stream<List<String>> streamMangasInCategory(String category) {
    final controller = StreamController<List<String>>();
    Future<void> fetch() async {
      final db = await _dbHelper.database;
      final maps = await db.query(
        'lib_mapping',
        where: 'categoryName = ?',
        whereArgs: [category],
      );
      controller.add(maps.map((m) => m['mangaId'] as String).toList());
    }

    fetch();
    final subscription = _mappingController.stream.listen((_) => fetch());
    controller.onCancel = () => subscription.cancel();
    return controller.stream;
  }

  Future<List<String>> getMangaCategories(String mangaId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'lib_mapping',
      where: 'mangaId = ?',
      whereArgs: [mangaId],
    );
    return maps.map((m) => m['categoryName'] as String).toList();
  }

  Future<void> addToCategory(String mangaId, String categoryName) async {
    final db = await _dbHelper.database;
    await db.insert('lib_mapping', {
      'mangaId': mangaId,
      'categoryName': categoryName,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    _mappingController.add(null);
  }
}
