import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

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
      // Sắp xếp mới nhất lên đầu
      novels.sort((a, b) => b.importedAt.compareTo(a.importedAt));
      return novels;
    } catch (e) {
      debugPrint('NovelService.getAll error: $e');
      return [];
    }
  }

  /// Hàm hỗ trợ: Trích xuất ảnh bìa EPUB
  Future<String> _extractAndSaveCover(String epubPath, String title) async {
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
        final dir = await getApplicationDocumentsDirectory();
        final safeName = title.replaceAll(RegExp(r'[^\w\s]'), '_');
        final coverFile = File('${dir.path}/cover_$safeName.jpg');
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

      // Kiểm tra trùng path
      final exists = raw.any((s) {
        try {
          final map = jsonDecode(s) as Map<String, dynamic>;
          return map['path'] == novel.path;
        } catch (_) {
          return false;
        }
      });
      if (exists) return false;

      // Trích xuất ảnh bìa
      final coverPath = await _extractAndSaveCover(novel.path, novel.title);
      final finalNovel = novel.copyWith(coverPath: coverPath);

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
      raw.removeWhere((s) {
        try {
          return (jsonDecode(s) as Map<String, dynamic>)['path'] == path;
        } catch (_) {
          return false;
        }
      });
      await prefs.setStringList(_key, raw);
      debugPrint('🗑️ NovelService: Đã xóa $path');
    } catch (e) {
      debugPrint('NovelService.remove error: $e');
    }
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
