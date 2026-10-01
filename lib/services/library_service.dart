import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../data/database_helper.dart';

class _ValueStreamController<T> {
  T value;
  final StreamController<T> _controller = StreamController<T>.broadcast();

  _ValueStreamController(this.value);

  Stream<T> get stream {
    return Stream<T>.multi((multiController) {
      multiController.add(value);
      final sub = _controller.stream.listen(
        multiController.add,
        onError: multiController.addError,
        onDone: multiController.close,
      );
      multiController.onCancel = sub.cancel;
    });
  }

  bool get isClosed => _controller.isClosed;

  void add(T newValue) {
    if (_controller.isClosed) return;
    value = newValue;
    _controller.add(newValue);
  }

  void close() {
    _controller.close();
  }
}

// LibraryService: quản lý Categories và Mapping trong SQLite local.
// Dùng StreamController thủ công vì SQLite không có built-in reactive streams như Firestore.
// Mỗi khi data thay đổi, service tự push update vào controller để UI rebuild.
class LibraryService {
  static final LibraryService instance = LibraryService._();
  LibraryService._() {
    _refreshCategories();
  }

  final _dbHelper = DatabaseHelper.instance;

  final _categoriesController = _ValueStreamController<List<String>>([]);
  final _mappingController = StreamController<void>.broadcast();

  void notifyMappingChanged() {
    _mappingController.add(null);
  }

  Future<List<String>> getCategories() async {
    final db = await _dbHelper.database;
    final maps = await db.query('lib_categories', orderBy: 'sortIndex ASC');
    final cats = maps
        .map((m) => _readString(m, 'name'))
        .where((name) => name.isNotEmpty)
        .toList();
    if (cats.isEmpty) {
      await addCategory('Mặc định');
      return ['Mặc định'];
    }
    return cats;
  }

  Future<void> refreshCategories() => _refreshCategories();

  Stream<List<String>> streamCategories() {
    // If empty, we trigger a refresh but return the stream immediately
    if (_categoriesController.value.isEmpty) {
      _refreshCategories();
    }
    return _categoriesController.stream;
  }
  
  List<String> get currentCategories => _categoriesController.value;

  Future<void> _refreshCategories() async {
    try {
      final db = await _dbHelper.database;
      final maps = await db.query('lib_categories', orderBy: 'sortIndex ASC');
      final cats = maps
          .map((m) => _readString(m, 'name'))
          .where((name) => name.isNotEmpty)
          .toList();
      if (cats.isEmpty) {
        // Auto-tạo category "Mặc định" nếu user xóa hết — đảm bảo có ít nhất 1 category
        // addCategory bên trong đã tự gọi _refreshCategories(), return để tránh gọi kép
        await addCategory('Mặc định');
        return;
      }
      _categoriesController.add(cats);
    } catch (_) {
      if (_categoriesController.value.isEmpty) {
        _categoriesController.add(['Mặc định']);
      }
    }
  }

  Future<void> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final db = await _dbHelper.database;
    final countMap = await db.rawQuery(
      'SELECT COALESCE(MAX(sortIndex), -1) + 1 as nextIndex FROM lib_categories',
    );
    final count = _readInt(countMap.first, 'nextIndex');
    await db.insert('lib_categories', {
      'name': trimmed,
      'sortIndex': count,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    _refreshCategories();
  }

  Future<void> updateCategory(String oldName, String newName) async {
    final trimmedNew = newName.trim();
    if (oldName == 'Mặc định' || trimmedNew.isEmpty || oldName == trimmedNew) return;
    final db = await _dbHelper.database;

    await db.transaction((txn) async {
      // 1. Kiểm tra xem category đích đã tồn tại chưa để tránh crash UNIQUE constraint
      final existingTarget = await txn.query(
        'lib_categories',
        where: 'name = ?',
        whereArgs: [trimmedNew],
      );

      if (existingTarget.isNotEmpty) {
        // Nếu tên đích đã tồn tại: Chế độ merge (gộp)
        // Xóa các mapping của oldName cho truyện đã thuộc trimmedNew để tránh lỗi PK (mangaId, categoryName)
        await txn.rawDelete(
          '''
          DELETE FROM lib_mapping 
          WHERE categoryName = ? AND mangaId IN (
            SELECT mangaId FROM lib_mapping WHERE categoryName = ?
          )
          ''',
          [oldName, trimmedNew],
        );
        // Chuyển các mapping còn lại sang trimmedNew
        await txn.update(
          'lib_mapping',
          {'categoryName': trimmedNew},
          where: 'categoryName = ?',
          whereArgs: [oldName],
        );
        // Xóa category cũ
        await txn.delete(
          'lib_categories',
          where: 'name = ?',
          whereArgs: [oldName],
        );
      } else {
        // Tên mới chưa tồn tại: Cập nhật bình thường
        await txn.update(
          'lib_categories',
          {'name': trimmedNew},
          where: 'name = ?',
          whereArgs: [oldName],
        );
        await txn.update(
          'lib_mapping',
          {'categoryName': trimmedNew},
          where: 'categoryName = ?',
          whereArgs: [oldName],
        );
      }
    });

    // Dọn dẹp listener và controller của category cũ để tránh zombie/memory leak
    await _catMappingSubs.remove(oldName)?.cancel();
    _mangasInCatControllers.remove(oldName)?.close();

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
    await batch.commit(noResult: true);
    _refreshCategories();
  }

  Future<void> removeCategory(String name) async {
    if (name == 'Mặc định') return; // Bảo vệ danh mục mặc định
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      // 1. Chỉ chuyển những truyện CHỈ nằm duy nhất trong category này sang 'Mặc định'
      // để đảm bảo truyện trong thư viện không bị mất dấu/mồ côi.
      // Những truyện đã nằm trong category khác vẫn được giữ nguyên ở các category đó.
      await txn.rawInsert(
        '''
        INSERT OR IGNORE INTO lib_mapping (mangaId, categoryName)
        SELECT mangaId, 'Mặc định'
        FROM lib_mapping
        WHERE categoryName = ?
          AND mangaId NOT IN (
            SELECT mangaId FROM lib_mapping WHERE categoryName != ?
          )
        ''',
        [name, name],
      );
      // 2. Xóa mapping của category bị xóa
      await txn.delete(
        'lib_mapping',
        where: 'categoryName = ?',
        whereArgs: [name],
      );
      // 3. Xóa category
      await txn.delete('lib_categories', where: 'name = ?', whereArgs: [name]);
    });
    // Hủy subscription và xóa controller của category đã xóa để tránh leak
    await _catMappingSubs.remove(name)?.cancel();
    _mangasInCatControllers.remove(name)?.close();
    _refreshCategories();
    _mappingController.add(null);
  }

  Stream<List<String>> streamMangaCategories(String mangaId) {
    // Dùng Stream.multi để mỗi listener (ví dụ: các widget khác nhau hoặc khi re-mount)
    // có vòng đời độc lập, fetch tức thì và hủy subscription sạch sẽ khi unmount
    return Stream<List<String>>.multi((multiController) {
      Future<void> fetch() async {
        if (multiController.isClosed) return;
        try {
          final cats = await getMangaCategories(mangaId);
          if (!multiController.isClosed) {
            multiController.add(cats);
          }
        } catch (e) {
          if (!multiController.isClosed) {
            multiController.addError(e);
          }
        }
      }

      fetch();
      final sub = _mappingController.stream.listen((_) => fetch());
      multiController.onCancel = () {
        sub.cancel();
      };
    });
  }

  final Map<String, _ValueStreamController<List<String>>> _mangasInCatControllers = {};

  final Map<String, StreamSubscription> _catMappingSubs = {};

  Stream<List<String>> streamMangasInCategory(String category) {
    var controller = _mangasInCatControllers[category];
    if (controller == null || controller.isClosed) {
      controller = _ValueStreamController<List<String>>([]);
      _mangasInCatControllers[category] = controller;

      Future<void> fetch() async {
        try {
          final db = await _dbHelper.database;
          final maps = await db.query(
            'lib_mapping',
            columns: ['mangaId'],
            where: 'categoryName = ?',
            whereArgs: [category],
          );
          final list = maps
              .map((m) => _readString(m, 'mangaId'))
              .where((id) => id.isNotEmpty)
              .toList();
          controller!.add(list);
        } catch (_) {}
      }

      fetch();
      _catMappingSubs[category]?.cancel();
      _catMappingSubs[category] = _mappingController.stream.listen((_) => fetch());
    }

    return controller.stream;
  }

  Future<int> getMangaCountInCategory(String category) async {
    try {
      final db = await _dbHelper.database;
      final result = await db.rawQuery(
        'SELECT count(*) as count FROM lib_mapping WHERE categoryName = ?',
        [category],
      );
      if (result.isEmpty) return 0;
      return _readInt(result.first, 'count');
    } catch (_) {
      return 0;
    }
  }

  Stream<int> streamMangaCountInCategory(String category) {
    return streamMangasInCategory(category).map((mangas) => mangas.length);
  }

  Future<void> setMangaCategoriesForMultiple(
    List<String> mangaIds,
    List<String> categories,
  ) async {
    if (mangaIds.isEmpty) return;
    final db = await _dbHelper.database;
    final cleanCategories = categories
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final id in mangaIds) {
        batch.delete(
          'lib_mapping',
          where: 'mangaId = ?',
          whereArgs: [id],
        );
        for (var cat in cleanCategories) {
          batch.insert(
            'lib_mapping',
            {
              'mangaId': id,
              'categoryName': cat,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await batch.commit(noResult: true);
    });
    _mappingController.add(null);
  }

  Future<void> setMangaCategories(
    String mangaId,
    List<String> categories,
  ) {
    return setMangaCategoriesForMultiple([mangaId], categories);
  }

  Future<void> removeMultipleFromCategory(
    List<String> mangaIds,
    String categoryName,
  ) async {
    if (mangaIds.isEmpty) return;
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final id in mangaIds) {
      batch.delete(
        'lib_mapping',
        where: 'mangaId = ? AND categoryName = ?',
        whereArgs: [id, categoryName],
      );
    }
    await batch.commit(noResult: true);
    _mappingController.add(null);
  }

  Future<void> removeFromCategory(String mangaId, String categoryName) {
    return removeMultipleFromCategory([mangaId], categoryName);
  }

  Future<List<String>> getMangaCategories(String mangaId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'lib_mapping',
      where: 'mangaId = ?',
      whereArgs: [mangaId],
    );
    return maps
        .map((m) => _readString(m, 'categoryName'))
        .where((categoryName) => categoryName.isNotEmpty)
        .toList();
  }

  Future<void> addToCategory(String mangaId, String categoryName) async {
    final db = await _dbHelper.database;
    await db.insert('lib_mapping', {
      'mangaId': mangaId,
      'categoryName': categoryName,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    _mappingController.add(null);
  }

  String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return '';
    return value.toString().trim();
  }

  int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
