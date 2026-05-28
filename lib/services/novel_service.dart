import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:archive/archive_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'folder_service.dart';

/// Một cuốn EPUB đã nhập vào thư viện cục bộ.
class LocalNovel {
  final String path; // Đường dẫn tuyệt đối đến file .epub trên máy
  final String title; // Tên hiển thị (tên file không có phần mở rộng)
  final String coverPath; // Đường dẫn đến ảnh bìa đã giải nén
  final DateTime importedAt;

  const LocalNovel({
    required this.path,
    required this.title,
    this.coverPath = '',
    required this.importedAt,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'title': title,
    'coverPath': coverPath,
    'importedAt': importedAt.millisecondsSinceEpoch,
  };

  factory LocalNovel.fromJson(Map<String, dynamic> json) {
    final path = _readString(json, 'path');
    if (path.isEmpty) {
      throw const FormatException('LocalNovel requires a path.');
    }

    final title = _readString(json, 'title');
    return LocalNovel(
      path: path,
      title: title.isEmpty ? path.split(RegExp(r'[\\/]')).last : title,
      coverPath: _readString(json, 'coverPath'),
      importedAt: DateTime.fromMillisecondsSinceEpoch(
        _readInt(json, 'importedAt'),
      ),
    );
  }

  LocalNovel copyWith({String? title, String? coverPath}) => LocalNovel(
    path: path,
    title: title ?? this.title,
    coverPath: coverPath ?? this.coverPath,
    importedAt: importedAt,
  );

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return '';
    return value.toString().trim();
  }

  static int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// Quản lý danh sách EPUB đã nhập — lưu vào SharedPreferences (local, không cloud).
/// Singleton pattern — dùng NovelService.instance ở mọi nơi.
class NovelService {
  NovelService._();
  static final NovelService instance = NovelService._();

  static const _key = 'local_novels_v1';

  int _stablePathHash(String value) {
    return value.codeUnits.fold<int>(
      0,
      (hash, codeUnit) => (hash * 31 + codeUnit) & 0x7fffffff,
    );
  }

  String _managedFolderName(String title, String sourcePath) {
    final safeTitle = FolderService.sanitize(title)
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    final normalizedSource = sourcePath.replaceAll('\\', '/').toLowerCase();
    final hash = _stablePathHash(normalizedSource).toRadixString(16);
    final titlePrefix = safeTitle.isEmpty ? 'novel' : safeTitle;
    return '${titlePrefix}_$hash';
  }

  /// Lấy toàn bộ danh sách EPUB đã nhập, mới nhất lên đầu.
  Future<List<LocalNovel>> getAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? [];
      final novels = raw
          .map((s) {
            try {
              return LocalNovel.fromJson(jsonDecode(s) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<LocalNovel>()
          .toList();
      final migrated = await _migrateLegacyNovels(novels);
      // Sắp xếp mới nhất lên đầu
      migrated.sort((a, b) => b.importedAt.compareTo(a.importedAt));
      return migrated;
    } catch (e) {
      debugPrint('NovelService.getAll error: $e');
      return [];
    }
  }

  bool _isManagedNovelPath(String path) {
    final normalizedPath = path.replaceAll('\\', '/');
    final normalizedRoot = FolderService.downloadPath.replaceAll('\\', '/');
    return normalizedPath.startsWith(normalizedRoot) &&
        normalizedPath.contains('/_novels/');
  }

  Future<String> _resolveManagedPath(String title, String sourcePath) async {
    final folderName = _managedFolderName(title, sourcePath);
    final novelsPath = await FolderService.getNovelsPath();
    final folder = Directory('$novelsPath/$folderName');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return '${folder.path}/book.epub';
  }

  Future<String> _resolveManagedCoverPath(String title, String sourcePath) async {
    final managedPath = await _resolveManagedPath(title, sourcePath);
    return '${File(managedPath).parent.path}/cover.jpg';
  }

  Future<void> _copyToManagedStorage(String sourcePath, String targetPath) async {
    if (sourcePath == targetPath) return;

    final source = File(sourcePath);
    if (!await source.exists()) {
      throw Exception('Không tìm thấy file EPUB đã chọn.');
    }

    final target = File(targetPath);
    await target.parent.create(recursive: true);
    await source.copy(targetPath);
  }

  /// Hàm hỗ trợ: Trích xuất ảnh bìa EPUB
  Future<String> _extractAndSaveCover(
    String epubPath,
    String title, {
    String? sourcePath,
  }) async {
    try {
      final bytes = await File(epubPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      Uint8List? coverBytes;

      // Tìm file ảnh chứa từ 'cover' hoặc 'bìa'
      for (final file in archive) {
        if (file.isFile) {
          final lowerName = file.name.toLowerCase();
          if ((lowerName.contains('cover') || lowerName.contains('bìa')) &&
              (lowerName.endsWith('.jpg') ||
                  lowerName.endsWith('.jpeg') ||
                  lowerName.endsWith('.png'))) {
            coverBytes = file.content as Uint8List;
            break;
          }
        }
      }

      // Nếu không tìm thấy bằng tên, lấy file ảnh bất kỳ đầu tiên (thường là bìa)
      if (coverBytes == null) {
        for (final file in archive) {
          if (file.isFile) {
            final lowerName = file.name.toLowerCase();
            if (lowerName.endsWith('.jpg') ||
                lowerName.endsWith('.jpeg') ||
                lowerName.endsWith('.png')) {
              coverBytes = file.content as Uint8List;
              break;
            }
          }
        }
      }

      if (coverBytes != null) {
        final coverFile = File(
          sourcePath == null
              ? await FolderService.getNovelCoverPath(title)
              : await _resolveManagedCoverPath(title, sourcePath),
        );
        await coverFile.parent.create(recursive: true);
        await coverFile.writeAsBytes(coverBytes);
        return coverFile.path;
      }
    } catch (e) {
      debugPrint('Lỗi giải nén ảnh bìa EPUB: $e');
    }
    return '';
  }

  /// Thêm 1 file EPUB vào thư viện.
  /// Trả về false nếu file đã tồn tại (tránh trùng).
  Future<bool> add(LocalNovel novel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? [];
      final managedPath = await _resolveManagedPath(novel.title, novel.path);

      // Kiểm tra trùng path gốc hoặc trùng path nội bộ đã suy ra từ nguồn này.
      final exists = raw.any((s) {
        try {
          final map = jsonDecode(s) as Map<String, dynamic>;
          final path = map['path']?.toString() ?? '';
          return path == novel.path || path == managedPath;
        } catch (_) {
          return false;
        }
      });
      if (exists) return false;

      await _copyToManagedStorage(novel.path, managedPath);

      // Trích xuất ảnh bìa
      final coverPath = await _extractAndSaveCover(
        managedPath,
        novel.title,
        sourcePath: novel.path,
      );
      final finalNovel = LocalNovel(
        path: managedPath,
        title: novel.title,
        coverPath: coverPath,
        importedAt: novel.importedAt,
      );

      raw.add(jsonEncode(finalNovel.toJson()));
      await prefs.setStringList(_key, raw);
      debugPrint('📚 NovelService: Đã thêm "${finalNovel.title}"');
      return true;
    } catch (e) {
      debugPrint('NovelService.add error: $e');
      return false;
    }
  }

  /// Xóa 1 cuốn sách khỏi thư viện theo đường dẫn.
  Future<void> remove(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? [];
      final removedNovels = <LocalNovel>[];
      raw.removeWhere((s) {
        try {
          final novel = LocalNovel.fromJson(jsonDecode(s) as Map<String, dynamic>);
          final match = novel.path == path;
          if (match) {
            removedNovels.add(novel);
          }
          return match;
        } catch (_) {
          return false;
        }
      });
      await prefs.setStringList(_key, raw);

      for (final novel in removedNovels) {
        try {
          if (_isManagedNovelPath(novel.path)) {
            final folder = Directory(File(novel.path).parent.path);
            if (await folder.exists()) {
              await folder.delete(recursive: true);
            }
          } else if (novel.coverPath.isNotEmpty) {
            final coverFile = File(novel.coverPath);
            if (await coverFile.exists()) {
              await coverFile.delete();
            }
          }
        } catch (e) {
          debugPrint('NovelService.remove cleanup error: $e');
        }
      }
      debugPrint('🗑️ NovelService: Đã xóa $path');
    } catch (e) {
      debugPrint('NovelService.remove error: $e');
    }
  }

  Future<List<LocalNovel>> _migrateLegacyNovels(List<LocalNovel> novels) async {
    var changed = false;
    final migrated = <LocalNovel>[];

    for (final novel in novels) {
      if (_isManagedNovelPath(novel.path)) {
        migrated.add(novel);
        continue;
      }

      final sourceFile = File(novel.path);
      if (!await sourceFile.exists()) {
        final legacyPath = novel.path.startsWith('MISSING_FILE_Legacy|')
            ? novel.path
            : 'MISSING_FILE_Legacy|${novel.path}';
        
        if (legacyPath != novel.path) {
          migrated.add(
            LocalNovel(
              path: legacyPath,
              title: novel.title,
              coverPath: novel.coverPath,
              importedAt: novel.importedAt,
            ),
          );
          changed = true;
        } else {
          migrated.add(novel);
        }
        continue;
      }

      try {
        final managedPath = await _resolveManagedPath(novel.title, novel.path);
        await _copyToManagedStorage(novel.path, managedPath);
        final coverPath = await _extractAndSaveCover(
          managedPath,
          novel.title,
          sourcePath: novel.path,
        );
        migrated.add(
          LocalNovel(
            path: managedPath,
            title: novel.title,
            coverPath: coverPath,
            importedAt: novel.importedAt,
          ),
        );
        changed = true;
      } catch (e) {
        debugPrint('NovelService legacy migration error: $e');
        migrated.add(novel);
      }
    }

    if (changed) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _key,
        migrated.map((novel) => jsonEncode(novel.toJson())).toList(),
      );
    }

    return migrated;
  }

  /// Đổi tên hiển thị của 1 cuốn sách.
  Future<void> rename(String path, String newTitle) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? [];
      final updated = raw.map((s) {
        try {
          final map = jsonDecode(s) as Map<String, dynamic>;
          if (map['path'] == path) {
            map['title'] = newTitle;
            // Trích xuất lại bìa với tên mới nếu cần, ở đây chỉ đổi tên
            return jsonEncode(map);
          }
          return s;
        } catch (_) {
          return s;
        }
      }).toList();
      await prefs.setStringList(_key, updated);
    } catch (e) {
      debugPrint('NovelService.rename error: $e');
    }
  }
}
