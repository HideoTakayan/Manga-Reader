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

  void add(T newValue) {
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
        await addCategory('Mặc định');
        return _refreshCategories(); // Gọi lại để emit category mới
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
      'SELECT count(*) as count FROM lib_categories',
    );
    final count = _readInt(countMap.first, 'count');
    await db.insert('lib_categories', {
      'name': trimmed,
      'sortIndex': count,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    _refreshCategories();
  }

  Future<void> updateCategory(String oldName, String newName) async {
    final trimmedNew = newName.trim();
    if (oldName == 'Mặc định' || trimmedNew.isEmpty) return; // Bảo vệ danh mục mặc định và chống rỗng
    final db = await _dbHelper.database;
    // transaction: đảm bảo cả 2 update thành công hoặc cả 2 rollback
    await db.transaction((txn) async {
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
    await batch.commit(noResult: true);
    _refreshCategories();
  }

  Future<void> removeCategory(String name) async {
    if (name == 'Mặc định') return; // Bảo vệ danh mục mặc định
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete(
        'lib_mapping',
        where: 'categoryName = ?',
        whereArgs: [name],
      );
      await txn.delete('lib_categories', where: 'name = ?', whereArgs: [name]);
    });
    // Hủy subscription và xóa controller của category đã xóa để tránh leak
    await _catMappingSubs.remove(name)?.cancel();
    _mangasInCatControllers.remove(name)?.close();
    _refreshCategories();
    _mappingController.add(null);
  }

  Stream<List<String>> streamMangaCategories(String mangaId) {
    // Dùng StreamController.broadcast() thay vì single-subscription để nhiều
    // listener cùng lắng nghe (ví dụ: widget re-mount) mà không bị lỗi.
    late StreamController<List<String>> controller;
    StreamSubscription? subscription;

    Future<void> fetch() async {
      if (controller.isClosed) return;
      try {
        final db = await _dbHelper.database;
        final maps = await db.query(
          'lib_mapping',
          where: 'mangaId = ?',
          whereArgs: [mangaId],
        );
        if (!controller.isClosed) {
          controller.add(
            maps
                .map((m) => _readString(m, 'categoryName'))
                .where((categoryName) => categoryName.isNotEmpty)
                .toList(),
          );
        }
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    controller = StreamController<List<String>>(
      onListen: () {
        fetch();
        // Lắng nghe sự kiện mapping thay đổi để re-fetch
        subscription = _mappingController.stream.listen((_) => fetch());
      },
      onCancel: () {
        // Hủy subscription khi không còn listener — tránh leak
        subscription?.cancel();
        subscription = null;
        controller.close();
      },
    );

    return controller.stream;
  }

  final Map<String, _ValueStreamController<List<String>>> _mangasInCatControllers = {};

  final Map<String, StreamSubscription> _catMappingSubs = {};

  Stream<List<String>> streamMangasInCategory(String category) {
    if (!_mangasInCatControllers.containsKey(category)) {
      final controller = _ValueStreamController<List<String>>([]);
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
          controller.add(list);
        } catch (_) {}
      }

      fetch();
      // Lưu subscription để cancel khi category bị xóa
      _catMappingSubs[category] = _mappingController.stream.listen((_) => fetch());
    }

    return _mangasInCatControllers[category]!.stream;
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
    late StreamController<int> sc;
    StreamSubscription? sub;

    Future<void> fetch() async {
      if (sc.isClosed) return;
      final count = await getMangaCountInCategory(category);
      if (!sc.isClosed) sc.add(count);
    }

    sc = StreamController<int>.broadcast(
      onListen: () {
        fetch();
        sub = _mappingController.stream.listen((_) => fetch());
      },
      onCancel: () {
        sub?.cancel();
        sc.close();
      },
    );

    return sc.stream;
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
