// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models_cloud.dart';
import 'content_type.dart';
import 'database_helper.dart';
import '../config/drive_config.dart';
import '../services/interaction_service.dart';
import '../services/notification_service.dart';
import '../services/folder_service.dart';
import '../features/catalog/catalog_cache_service.dart';
import '../core/utils/chapter_sort_helper.dart';

// Singleton kết nối với Google Drive API.
// Xử lý toàn bộ việc đọc/ghi file truyện: lấy danh sách, upload chapter, download để đọc.
// Người dùng thường → đọc qua Service Account (không cần đăng nhập).
// Admin → đăng nhập Google (OAuth) để được quyền ghi lên Drive.
class DriveService {
  static final DriveService instance = DriveService._internal();
  DriveService._internal();

  // Tái sử dụng HTTP client có Keep-Alive (giảm độ trễ bắt tay TLS 300-500ms)
  final http.Client _httpClient = http.Client();

  // _googleSignIn: dùng cho luồng Admin (OAuth, có quyền ghi).
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveScope],
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  List<CloudManga>? _cachedMangas;

  // Cache ID trực tiếp của catalog.json để bỏ qua tìm kiếm files.list (tiết kiệm 2s)
  String? _catalogFileId;
  static const String _catalogIdPrefKey = 'cached_drive_catalog_file_id';

  // Cache danh sách chương theo mangaId trong RAM với TTL 5 phút (tải 0ms khi xem lại)
  final Map<String, (DateTime, List<CloudChapter>)> _chapterCache = {};
  static const Duration _chapterCacheTtl = Duration(minutes: 5);

  // Cache file ZIP/CBZ trong RAM để không phải tải lại khi chuyển chapter.
  // Giới hạn 2 file (~50-100MB) để tránh dùng quá nhiều RAM (gây văng app OOM).
  final Map<String, Uint8List> _fileCache = {};
  final List<String> _fileCacheOrder = []; // Theo dõi thứ tự để xóa cái cũ nhất
  static const int _maxCacheSize = 2;

  final Map<String, Future<Uint8List?>> _activeDownloadFutures = {};
  final Map<String, Future<bool>> _activeFileDownloads = {};

  // Xóa file cũ nhất trong cache khi vượt giới hạn.
  void _trimFileCache() {
    while (_fileCacheOrder.length > _maxCacheSize) {
      final oldestKey = _fileCacheOrder.removeAt(0);
      _fileCache.remove(oldestKey);
      print('Đã giải phóng cache: $oldestKey');
    }
  }

  // Trả về file đang cache nếu có, null nếu chưa tải.
  Uint8List? getCachedFile(String fileId) => _fileCache[fileId];

  // Xóa toàn bộ cache RAM (dùng khi thiếu bộ nhớ).
  void clearFileCache() {
    _fileCache.clear();
    _fileCacheOrder.clear();
  }

  List<CloudManga>? get cachedMangas => _cachedMangas;

  CloudManga? getMangaById(String id) {
    if (_cachedMangas == null) return null;
    try {
      return _cachedMangas!.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  String mediaUrl(String fileId) =>
      'https://drive.google.com/uc?export=view&id=$fileId';

  String getThumbnailLink(String fileId) => mediaUrl(fileId);

  // Stream phát sự kiện khi trạng thái đăng nhập Google thay đổi.
  final _authController = StreamController<GoogleSignInAccount?>.broadcast();
  Stream<GoogleSignInAccount?> get onAuthStateChanged => _authController.stream;
  GoogleSignInAccount? get currentUser => _currentUser;

  // ID folder gốc trên Drive chứa toàn bộ dữ liệu app.
  String? _rootFolderId;
  static const String _catalogFileName = 'catalog.json'; // File danh mục tổng

  // ── XÁC THỰC NGƯỜI DÙNG (ADMIN / NHÓM DỊCH) ─────────────────────────────

  // Khởi tạo Drive API client từ token của user đã đăng nhập và xác thực quyền Drive thực tế.
  Future<bool> _initializeDriveApi() async {
    if (_currentUser != null) {
      try {
        final httpClient = await _googleSignIn.authenticatedClient();
        if (httpClient != null) {
          final testApi = drive.DriveApi(httpClient);
          // Gọi thử 1 lệnh API nhẹ để xác minh token có thực sự mang quyền Drive không
          await testApi.files.list(pageSize: 1, $fields: 'files(id)');
          _driveApi = testApi;
          return true;
        }
      } catch (e) {
        print('Xác thực quyền Drive không thành công (thiếu scope hoặc lỗi token): $e');
        _driveApi = null;
        return false;
      }
    }
    _driveApi = null;
    return false;
  }

  // Đảm bảo có quyền ghi vào Google Drive trước khi thực hiện các thao tác thêm/sửa/xóa
  Future<void> ensureDriveAccess() async {
    if (_currentUser == null || _driveApi == null) {
      await signIn();
    } else {
      final isAlive = await _initializeDriveApi();
      if (!isAlive) {
        // Nếu token hết hạn hoặc thiếu scope, yêu cầu cấp quyền lại
        try {
          final granted = await _googleSignIn.requestScopes([drive.DriveApi.driveScope]);
          if (granted) {
            await _initializeDriveApi();
          }
        } catch (e) {
          print('Lỗi requestScopes: $e');
        }
      }
    }
    if (_driveApi == null) {
      throw Exception('Chưa có quyền ghi Google Drive. Vui lòng bấm vào biểu tượng Đám Mây để kết nối và cấp quyền Drive.');
    }
  }

  // Đăng nhập Google (OAuth) để lấy quyền ghi Drive.
  Future<GoogleSignInAccount?> signIn() async {
    try {
      // 1. Mở màn hình chọn tài khoản / đăng nhập
      _currentUser = await _googleSignIn.signIn();
      if (_currentUser == null) {
        throw Exception('Người dùng đã huỷ thao tác đăng nhập');
      }

      // 2. Yêu cầu cấp quyền Drive
      try {
        final granted = await _googleSignIn.requestScopes([drive.DriveApi.driveScope]);
        if (!granted) {
          await _googleSignIn.signOut();
          _currentUser = null;
          _driveApi = null;
          _authController.add(null);
          throw Exception('Bạn chưa cấp quyền truy cập Google Drive. Vui lòng cấp quyền để có thể đăng truyện.');
        }
      } catch (e) {
        if (e.toString().contains('chưa cấp quyền')) rethrow;
        print('Cảnh báo khi gọi requestScopes: $e');
      }

      // 3. Khởi tạo và xác thực quyền Drive API
      final success = await _initializeDriveApi();
      if (!success) {
        // Thử lại requestScopes nếu cần
        try {
          await _googleSignIn.requestScopes([drive.DriveApi.driveScope]);
          await _initializeDriveApi();
        } catch (_) {}
      }

      if (_driveApi == null) {
        _currentUser = null;
        _authController.add(null);
        throw Exception('Tài khoản Google chưa được cấp quyền truy cập Drive. Vui lòng thử lại và chọn Cho phép (Allow).');
      }

      _authController.add(_currentUser);
      return _currentUser;
    } catch (e) {
      print('Lỗi đăng nhập Google: $e');
      _currentUser = null;
      _driveApi = null;
      _authController.add(null);
      rethrow;
    }
  }

  // Thử khôi phục phiên đăng nhập cũ khi mở app (im lặng, không hiện popup).
  Future<GoogleSignInAccount?> restorePreviousSession() async {
    try {
      final user = await _googleSignIn.signInSilently();
      if (user != null) {
        _currentUser = user;
        final hasDrive = await _initializeDriveApi();
        if (hasDrive) {
          _authController.add(_currentUser);
          return _currentUser;
        } else {
          // Tài khoản đăng nhập sẵn trong app nhưng chưa từng cấp quyền Drive
          _currentUser = null;
          _driveApi = null;
          _authController.add(null);
          return null;
        }
      }
      _currentUser = null;
      _driveApi = null;
      _authController.add(null);
      return null;
    } catch (e) {
      print('Lỗi khôi phục phiên đăng nhập: $e');
      _currentUser = null;
      _driveApi = null;
      _authController.add(null);
      return null;
    }
  }

  // Đăng xuất và reset toàn bộ trạng thái Drive.
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _driveApi = null;
    _rootFolderId = null;
    _authController.add(null);
  }

  // Lấy auth headers của user hiện tại (dùng cho các request HTTP thủ công).
  Future<Map<String, String>> getHeaders() async {
    final headers = await _currentUser?.authHeaders;
    return headers ?? {};
  }

  // ── SERVICE ACCOUNT (ĐỌC CÔNG KHAI) ───────────────────────────────────────

  // Lấy/tạo folder gốc từ config (không cần Service Account).
  Future<void> _initRootFolder() async {
    if (_rootFolderId != null) return;
    _rootFolderId = DriveConfig.publicFolderId;
    print('✅ Sử dụng thư mục công khai: $_rootFolderId');
  }

  // ── QUẢN LÝ TRUYỆN ─────────────────────────────────────────────────────────

  Future<String?> _getCatalogFileId() async {
    if (_catalogFileId != null && _catalogFileId!.isNotEmpty) {
      return _catalogFileId;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _catalogFileId = prefs.getString(_catalogIdPrefKey);
      if (_catalogFileId != null && _catalogFileId!.isNotEmpty) {
        return _catalogFileId;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveCatalogFileId(String id) async {
    _catalogFileId = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_catalogIdPrefKey, id);
    } catch (_) {}
  }

  Future<List<CloudManga>?> _fetchCatalogByFileId(String fileId) async {
    try {
      final dlUrl = Uri.parse(
        'https://www.googleapis.com/drive/v3/files/$fileId'
        '?alt=media&key=${DriveConfig.apiKey}',
      );
      final dlRes = await _httpClient.get(dlUrl).timeout(const Duration(seconds: 4));
      if (dlRes.statusCode == 200) {
        final content = utf8.decode(dlRes.bodyBytes);
        final List<dynamic> jsonList = jsonDecode(content);
        return jsonList.map((e) => CloudManga.fromMap(e)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Direct catalog download by ID failed: $e');
    }
    return null;
  }

  Future<(String?, List<CloudManga>?)> _searchAndDownloadCatalog() async {
    try {
      final q = "name = '$_catalogFileName' and '$_rootFolderId' in parents and trashed = false";
      final listUrl = Uri.parse(
        'https://www.googleapis.com/drive/v3/files'
        '?q=${Uri.encodeComponent(q)}&key=${DriveConfig.apiKey}',
      );
      final listRes = await _httpClient.get(listUrl).timeout(const Duration(seconds: 4));
      if (listRes.statusCode == 200) {
        final listData = jsonDecode(listRes.body) as Map<String, dynamic>;
        final files = listData['files'] as List<dynamic>? ?? [];
        if (files.isNotEmpty) {
          final fileId = files.first['id'] as String;
          final mangas = await _fetchCatalogByFileId(fileId);
          return (fileId, mangas);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Catalog search failed: $e');
    }
    return (null, null);
  }

  // Lấy danh sách toàn bộ truyện từ file catalog.json trên Drive.
  // Tối ưu hoá cực đại: Tải trực tiếp qua fileId + Song song Stats Firestore.
  Future<List<CloudManga>> getMangas({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedMangas != null && _cachedMangas!.isNotEmpty) {
      return _cachedMangas!;
    }

    try {
      await _initRootFolder();
      if (_rootFolderId == null) {
        final offline = await _loadOfflineCatalog();
        if (offline.isNotEmpty) {
          _cachedMangas = offline;
          return offline;
        }
        return [];
      }

      // Khởi chạy song song việc lấy Lượt xem/Thích từ Firestore để không làm nghẽn
      final statsFuture = InteractionService.instance
          .getAllMangaStats()
          .timeout(const Duration(seconds: 3))
          .catchError((_) => <String, Map<String, int>>{});

      List<CloudManga>? rawMangas;
      final cachedId = await _getCatalogFileId();
      if (cachedId != null) {
        // TẢI TRỰC TIẾP (Bỏ qua 2s tìm kiếm files.list)
        rawMangas = await _fetchCatalogByFileId(cachedId);
      }

      // Nếu chưa có ID hoặc ID cũ bị lỗi (404/re-upload), tìm kiếm lại và lưu ID mới
      if (rawMangas == null) {
        final (newId, searchMangas) = await _searchAndDownloadCatalog();
        if (newId != null) {
          _saveCatalogFileId(newId);
        }
        rawMangas = searchMangas;
      }

      if (rawMangas != null && rawMangas.isNotEmpty) {
        final statsMap = await statsFuture;
        final mergedMangas = rawMangas.map((c) {
          if (statsMap.containsKey(c.id)) {
            final stats = statsMap[c.id]!;
            return CloudManga(
              id: c.id,
              title: c.title,
              author: c.author,
              description: c.description,
              coverFileId: c.coverFileId,
              updatedAt: c.updatedAt,
              genres: c.genres,
              status: c.status,
              viewCount: stats['viewCount'] ?? c.viewCount,
              likeCount: stats['likeCount'] ?? c.likeCount,
              chapterOrder: c.chapterOrder,
              contentType: c.contentType,
              uploaderGroupId: c.uploaderGroupId,
              uploaderGroupName: c.uploaderGroupName,
            );
          }
          return c;
        }).toList();

        _cachedMangas = mergedMangas;
        Future.microtask(() => CatalogCacheService.instance.saveCatalog(mergedMangas));
        return _cachedMangas!;
      }

      // Fallback offline nếu không tải được trực tuyến
      final offline = await _loadOfflineCatalog();
      if (offline.isNotEmpty) {
        _cachedMangas = offline;
        return offline;
      }

      return [];
    } catch (e) {
      debugPrint('⚠️ Error in getMangas: $e');
      final offline = await _loadOfflineCatalog();
      if (offline.isNotEmpty) {
        _cachedMangas = offline;
        return offline;
      }
      return [];
    }
  }

  /// Khôi phục danh mục truyện từ SQLite khi ứng dụng chạy Ngoại tuyến
  Future<List<CloudManga>> _loadOfflineCatalog() async {
    try {
      final cached = await CatalogCacheService.instance.getCachedCatalog();
      if (cached.isNotEmpty) {
        final List<CloudManga> result = [];
        for (final m in cached) {
          String coverPath = m.coverFileId;
          try {
            if (!coverPath.startsWith('/') && !coverPath.contains('\\')) {
              if (await FolderService.hasCover(m.title)) {
                coverPath = await FolderService.getCoverPath(m.title);
              }
            }
          } catch (_) {}
          result.add(CloudManga(
            id: m.id,
            title: m.title,
            coverFileId: coverPath,
            author: m.author,
            description: m.description,
            updatedAt: m.updatedAt,
            genres: m.genres,
            status: m.status,
            chapterOrder: m.chapterOrder,
            contentType: m.contentType,
            viewCount: m.viewCount,
            likeCount: m.likeCount,
            uploaderGroupId: m.uploaderGroupId,
            uploaderGroupName: m.uploaderGroupName,
          ));
        }
        return result;
      }

      final localMangas = await DatabaseHelper.instance.getAllLocalMangas();
      if (localMangas.isNotEmpty) {
        final List<CloudManga> result = [];
        for (final m in localMangas) {
          String coverPath = m.coverUrl;
          try {
            if (!coverPath.startsWith('/') && !coverPath.contains('\\')) {
              if (await FolderService.hasCover(m.title)) {
                coverPath = await FolderService.getCoverPath(m.title);
              }
            }
          } catch (_) {}
          result.add(CloudManga(
            id: m.id,
            title: m.title,
            coverFileId: coverPath,
            author: m.author,
            description: m.description,
            updatedAt: DateTime.now(),
            genres: m.genres,
            status: 'Offline',
            chapterOrder: [],
            contentType: m.contentType,
          ));
        }
        return result;
      }
    } catch (e) {
      debugPrint('⚠️ Error loading offline catalog: $e');
    }
    return [];
  }

  // Thêm bộ truyện mới lên Drive: tạo folder → upload bìa → ghi info.json → cập nhật catalog.json.
  Future<void> addManga({
    required String title,
    required String author,
    required String description,
    required File coverFile,
    required List<String> genres,
    required String status,
    required MangaContentType contentType,
    String? uploaderGroupId,
    String? uploaderGroupName,
  }) async {
    await ensureDriveAccess();

    await _initRootFolder();
    if (_rootFolderId == null) throw Exception('Không tìm thấy thư mục gốc.');

    // Bước 1: Tạo folder truyện trong thư mục gốc
    final folderMeta = drive.File()
      ..name = title
      ..parents = [_rootFolderId!]
      ..mimeType = 'application/vnd.google-apps.folder';
    final folder = await _driveApi!.files.create(
      folderMeta,
      supportsAllDrives: true,
    );
    final folderId = folder.id!;

    // Bước 2: Upload ảnh bìa vào folder vừa tạo
    final coverMeta = drive.File()
      ..name = 'cover.${path.extension(coverFile.path)}'
      ..parents = [folderId];
    final coverMedia = drive.Media(
      coverFile.openRead(),
      coverFile.lengthSync(),
    );
    final coverResult = await _driveApi!.files.create(
      coverMeta,
      uploadMedia: coverMedia,
      supportsAllDrives: true,
    );

    // Bước 3: Tạo object CloudManga, dùng folderId làm ID truyện
    final manga = CloudManga(
      id: folderId,
      title: title,
      author: author,
      description: description,
      coverFileId: coverResult.id!,
      updatedAt: DateTime.now(),
      genres: genres,
      status: status,
      viewCount: 0,
      likeCount: 0,
      contentType: contentType,
      uploaderGroupId: uploaderGroupId,
      uploaderGroupName: uploaderGroupName,
    );

    // Bước 4: Ghi info.json chứa metadata vào folder truyện
    final infoMeta = drive.File()
      ..name = 'info.json'
      ..parents = [folderId];
    final infoContent = jsonEncode(manga.toMap());
    final infoBytes = utf8.encode(infoContent);
    final infoMedia = drive.Media(Stream.value(infoBytes), infoBytes.length);
    await _driveApi!.files.create(
      infoMeta,
      uploadMedia: infoMedia,
      supportsAllDrives: true,
    );

    // Bước 5: Thêm truyện mới vào catalog.json tổng để user khác thấy ngay
    await _updateCatalog(manga);
  }

  // Cập nhật catalog.json: tải về, thêm/thay thế bản ghi, ghi đè lại lên Drive.
  Future<void> _updateCatalog(CloudManga newManga) async {
    await ensureDriveAccess();
    if (_rootFolderId == null) await _initRootFolder();

    List<CloudManga> currentList = await getMangas();
    currentList.removeWhere((c) => c.id == newManga.id);
    currentList.insert(0, newManga); // Truyện mới lên đầu

    final jsonContent = jsonEncode(currentList.map((e) => e.toMap()).toList());
    final encodedJson = utf8.encode(jsonContent);

    // Tìm catalog.json hiện có để ghi đè, nếu chưa có thì tạo mới
    String? catalogFileId;
    try {
      final q =
          "name = '$_catalogFileName' and '$_rootFolderId' in parents and trashed = false";
      final fileList = await _driveApi!.files.list(
        q: q,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      if (fileList.files != null && fileList.files!.isNotEmpty) {
        catalogFileId = fileList.files!.first.id;
      }
    } catch (e) {
      print('Cảnh báo khi tìm file catalog: $e');
    }

    final media = drive.Media(Stream.value(encodedJson), encodedJson.length);

    if (catalogFileId != null) {
      await _driveApi!.files.update(
        drive.File(),
        catalogFileId,
        uploadMedia: media,
        supportsAllDrives: true,
      );
      _saveCatalogFileId(catalogFileId);
    } else {
      final fileMeta = drive.File()
        ..name = _catalogFileName
        ..parents = [_rootFolderId!];
      final createdFile = await _driveApi!.files.create(
        fileMeta,
        uploadMedia: media,
        supportsAllDrives: true,
      );
      if (createdFile.id != null) {
        _saveCatalogFileId(createdFile.id!);
      }
    }
    _cachedMangas = currentList;
  }

  // Xóa folder truyện trên Drive và cập nhật catalog.json.
  Future<void> deleteManga(String mangaId) async {
    await ensureDriveAccess();

    if (_cachedMangas == null) await getMangas();

    try {
      try {
        await _driveApi!.files.delete(mangaId, supportsAllDrives: true);
      } catch (e) {
        if (e is drive.DetailedApiRequestError && e.status == 404) {
          print('Folder đã bị xoá trước đó (404), tiếp tục cập nhật catalog.');
        } else {
          print('Lỗi nghiêm trọng khi xoá thư mục trên Drive: $e');
          rethrow;
        }
      }

      if (_cachedMangas != null) {
        _cachedMangas!.removeWhere((m) => m.id == mangaId);
        await _saveCatalogToDrive(_cachedMangas!);
      }
      print('Đã xóa Manga $mangaId và cập nhật catalog');
    } catch (e) {
      print('Lỗi quy trình xóa manga: $e');
      rethrow;
    }
  }

  // Quét lại toàn bộ folder để tái tạo catalog.json từ đầu (dùng khi catalog bị lỗi/mất).
  Future<void> rebuildCatalog() async {
    await ensureDriveAccess();

    await _initRootFolder();
    if (_rootFolderId == null) return;

    try {
      // Liệt kê tất cả folder con (mỗi folder = 1 bộ truyện)
      final foldersQuery =
          "mimeType = 'application/vnd.google-apps.folder' and '$_rootFolderId' in parents and trashed = false";
      final folderList = await _driveApi!.files.list(
        q: foldersQuery,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );

      if (folderList.files == null || folderList.files!.isEmpty) {
        _cachedMangas = [];
        await _saveCatalogToDrive([]);
        return;
      }

      // Đọc info.json trong từng folder để lấy metadata
      final List<CloudManga> mangas = [];
      for (final folder in folderList.files!) {
        try {
          final infoQuery =
              "name = 'info.json' and '${folder.id}' in parents and trashed = false";
          final infoFiles = await _driveApi!.files.list(
            q: infoQuery,
            supportsAllDrives: true,
            includeItemsFromAllDrives: true,
          );

          if (infoFiles.files != null && infoFiles.files!.isNotEmpty) {
            final infoFileId = infoFiles.files!.first.id!;
            final media =
                await _driveApi!.files.get(
                      infoFileId,
                      downloadOptions: drive.DownloadOptions.fullMedia,
                      supportsAllDrives: true,
                    )
                    as drive.Media;

            final List<int> bytes = [];
            await for (final chunk in media.stream) {
              bytes.addAll(chunk);
            }
            final content = utf8.decode(bytes);
            mangas.add(CloudManga.fromMap(jsonDecode(content)));
          } else {
            // Không có info.json → tạo bản ghi mặc định để không bị bỏ sót
            print(
              'Thiếu info.json cho ${folder.name}, đang tạo file mặc định...',
            );
            final inferredContentType = await _inferContentTypeFromFolderFiles(
              folder.id!,
            );
            final defaultManga = CloudManga(
              id: folder.id!,
              title: folder.name!,
              author: 'Không rõ',
              description: 'Chưa có mô tả.',
              coverFileId: '',
              updatedAt: folder.modifiedTime ?? DateTime.now(),
              genres: [],
              contentType: inferredContentType,
              status: 'Không rõ',
            );

            final infoMeta = drive.File()
              ..name = 'info.json'
              ..parents = [folder.id!];
            final infoContent = jsonEncode(defaultManga.toMap());
            final infoBytes = utf8.encode(infoContent);
            final infoMedia = drive.Media(
              Stream.value(infoBytes),
              infoBytes.length,
            );
            await _driveApi!.files.create(infoMeta, uploadMedia: infoMedia);
            mangas.add(defaultManga);
          }
        } catch (e) {
          print('Lỗi khi đọc info.json của ${folder.name}: $e');
        }
      }

      mangas.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await _saveCatalogToDrive(mangas);
      _cachedMangas = mangas;
      print('Đã tái tạo catalog với ${mangas.length} truyện');
    } catch (e) {
      print('Lỗi tái tạo catalog: $e');
      rethrow;
    }
  }

  Future<MangaContentType> _inferContentTypeFromFolderFiles(
    String folderId,
  ) async {
    try {
      final files = await _driveApi!.files.list(
        q: "'$folderId' in parents and trashed = false and name != 'info.json'",
        $fields: 'files(name)',
        pageSize: 1000,
      );
      final hasEpub =
          files.files?.any(
            (file) => (file.name ?? '').toLowerCase().endsWith('.epub'),
          ) ??
          false;
      return hasEpub ? MangaContentType.novel : MangaContentType.manga;
    } catch (e) {
      print('Không thể suy luận loại nội dung cho $folderId: $e');
      return MangaContentType.manga;
    }
  }

  // Ghi danh sách truyện vào file catalog.json trên Drive (ghi đè nếu đã có).
  Future<void> _saveCatalogToDrive(List<CloudManga> mangas) async {
    final jsonContent = jsonEncode(mangas.map((e) => e.toMap()).toList());

    String? catalogFileId;
    final q =
        "name = '$_catalogFileName' and '$_rootFolderId' in parents and trashed = false";
    final fileList = await _driveApi!.files.list(
      q: q,
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
    );
    if (fileList.files != null && fileList.files!.isNotEmpty) {
      catalogFileId = fileList.files!.first.id;
    }

    final encodedJson = utf8.encode(jsonContent);
    final media = drive.Media(Stream.value(encodedJson), encodedJson.length);

    if (catalogFileId != null) {
      await _driveApi!.files.update(
        drive.File(),
        catalogFileId,
        uploadMedia: media,
        supportsAllDrives: true,
      );
      _saveCatalogFileId(catalogFileId);
    } else {
      final fileMeta = drive.File()
        ..name = _catalogFileName
        ..parents = [_rootFolderId!];
      final created = await _driveApi!.files.create(
        fileMeta,
        uploadMedia: media,
        supportsAllDrives: true,
      );
      if (created.id != null) {
        _saveCatalogFileId(created.id!);
      }
    }
  }

  // Cập nhật metadata bộ truyện (tên, tác giả, bìa...) và catalog.json.
  // Nếu trạng thái thay đổi (VD: sang "Hoàn thành"), tự động gửi thông báo cho người theo dõi.
  Future<void> updateManga({
    required String mangaId,
    required String title,
    required String author,
    required String description,
    required List<String> genres,
    required String status,
    File? newCoverFile,
    MangaContentType? contentType,
  }) async {
    await ensureDriveAccess();

    final currentMangas = await getMangas();
    CloudManga? currentManga;
    for (final manga in currentMangas) {
      if (manga.id == mangaId) {
        currentManga = manga;
        break;
      }
    }
    if (currentManga == null) {
      throw Exception('Không tìm thấy truyện trong catalog để cập nhật.');
    }
    String coverFileId = currentManga.coverFileId;

    // Upload bìa mới nếu có, xóa bìa cũ để tiết kiệm dung lượng
    if (newCoverFile != null) {
      final coverMeta = drive.File()
        ..name = 'cover.${path.extension(newCoverFile.path)}'
        ..parents = [mangaId];
      final coverMedia = drive.Media(
        newCoverFile.openRead(),
        newCoverFile.lengthSync(),
      );

      try {
        await _driveApi!.files.delete(
          currentManga.coverFileId,
          supportsAllDrives: true,
        );
      } catch (e) {
        if (e is drive.DetailedApiRequestError && e.status == 404) {
          print('Ảnh bìa cũ không tồn tại (404), tiếp tục upload.');
        } else {
          print('Lỗi mạng/quyền khi xoá ảnh bìa cũ: $e');
          rethrow;
        }
      }

      final coverResult = await _driveApi!.files.create(
        coverMeta,
        uploadMedia: coverMedia,
        supportsAllDrives: true,
      );
      coverFileId = coverResult.id!;
    }

    final updatedManga = CloudManga(
      id: mangaId,
      title: title,
      author: author,
      description: description,
      coverFileId: coverFileId,
      updatedAt: DateTime.now(),
      genres: genres,
      status: status,
      viewCount: currentManga.viewCount,
      likeCount: currentManga.likeCount,
      chapterOrder: currentManga.chapterOrder,
      contentType: contentType ?? currentManga.contentType,
      uploaderGroupId: currentManga.uploaderGroupId,
      uploaderGroupName: currentManga.uploaderGroupName,
    );

    // Cập nhật info.json trong folder truyện
    try {
      final infoQuery =
          "name = 'info.json' and '$mangaId' in parents and trashed = false";
      final infoFiles = await _driveApi!.files.list(
        q: infoQuery,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      final infoContent = jsonEncode(updatedManga.toMap());
      final infoBytes = utf8.encode(infoContent);
      final infoMedia = drive.Media(Stream.value(infoBytes), infoBytes.length);

      if (infoFiles.files != null && infoFiles.files!.isNotEmpty) {
        await _driveApi!.files.update(
          drive.File(),
          infoFiles.files!.first.id!,
          uploadMedia: infoMedia,
          supportsAllDrives: true,
        );
      } else {
        final infoMeta = drive.File()
          ..name = 'info.json'
          ..parents = [mangaId];
        await _driveApi!.files.create(
          infoMeta,
          uploadMedia: infoMedia,
          supportsAllDrives: true,
        );
      }
    } catch (e) {
      print('Cảnh báo khi cập nhật info.json: $e');
    }

    await _updateCatalog(updatedManga);

    // Gửi thông báo nếu trạng thái truyện thay đổi
    if (currentManga.status != status) {
      await NotificationService.instance.notifySubscribers(
        mangaId: mangaId,
        title: '$title đã đổi trạng thái',
        body: 'Trạng thái mới: $status',
        type: 'status_update',
      );
    }
  }

  // ── QUẢN LÝ CHAPTER ────────────────────────────────────────────────────────

  // Lấy danh sách chapter của một truyện từ Drive (loại bỏ info.json và cover).
  // Tối ưu hoá: Cache RAM TTL 5 phút + Persistent HTTP Client.
  Future<List<CloudChapter>> getChapters(String mangaId, {bool forceRefresh = false}) async {
    // 1. Kiểm tra RAM cache (Tải tức thì 0ms khi xem lại)
    if (!forceRefresh && _chapterCache.containsKey(mangaId)) {
      final (cachedTime, cachedList) = _chapterCache[mangaId]!;
      if (DateTime.now().difference(cachedTime) < _chapterCacheTtl && cachedList.isNotEmpty) {
        return cachedList;
      }
    }

    try {
      final q =
          "'$mangaId' in parents and trashed = false and name != 'info.json' and not name contains 'cover.'";
      final listUrl = Uri.parse(
        'https://www.googleapis.com/drive/v3/files'
        '?q=${Uri.encodeComponent(q)}'
        '&fields=files(id,name,mimeType,size,createdTime)'
        '&pageSize=1000&key=${DriveConfig.apiKey}',
      );
      // Chạy song song: Tải danh sách file từ Google Drive và Lượt xem từ Firestore
      final driveFuture = _httpClient.get(listUrl).timeout(const Duration(seconds: 5));
      final statsFuture = InteractionService.instance
          .getChapterViews(mangaId)
          .timeout(const Duration(seconds: 3))
          .catchError((_) => <String, int>{});

      final results = await Future.wait([driveFuture, statsFuture]);
      final listRes = results[0] as http.Response;
      final statsMap = results[1] as Map<String, int>;

      if (listRes.statusCode != 200) {
        throw Exception('HTTP ${listRes.statusCode} khi lấy chapters');
      }

      final listData = jsonDecode(listRes.body) as Map<String, dynamic>;
      final rawFiles = listData['files'] as List<dynamic>? ?? [];

      final files = rawFiles.map((f) {
        final name = f['name'] as String? ?? '';
        final id = f['id'] as String? ?? '';
        String type = 'zip';
        final lowerName = name.toLowerCase();
        if (lowerName.endsWith('.epub')) type = 'epub';
        if (lowerName.endsWith('.cbz')) type = 'cbz';
        if (lowerName.endsWith('.pdf')) type = 'pdf';

        return CloudChapter(
          id: id,
          title: name.isEmpty ? 'Không rõ' : name,
          fileId: id,
          fileType: type,
          sizeBytes: int.tryParse((f['size'] as String?) ?? '0') ?? 0,
          uploadedAt: f['createdTime'] != null
              ? DateTime.tryParse(f['createdTime'] as String) ?? DateTime.now()
              : DateTime.now(),
          viewCount: statsMap[id] ?? 0,
        );
      }).toList();

      final sorted = ChapterSortHelper.sort(files);
      // Lưu vào RAM cache
      _chapterCache[mangaId] = (DateTime.now(), sorted);
      return sorted;
    } catch (e) {
      debugPrint('⚠️ Error fetching chapters: $e');
      if (_chapterCache.containsKey(mangaId)) {
        return _chapterCache[mangaId]!.$2;
      }
      return [];
    }
  }

  // Upload file chapter mới (ZIP/CBZ/PDF) lên folder truyện trên Drive.
  // Sau khi upload xong, gửi thông báo realtime cho người đang theo dõi truyện.
  Future<void> addChapter({
    required String mangaId,
    required String title,
    required File file,
  }) async {
    await ensureDriveAccess();

    // Xóa cache chương cũ để ép nạp mới
    _chapterCache.remove(mangaId);

    // Làm sạch tên file trước khi upload (bỏ ký tự đặc biệt, giữ lại Unicode)
    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final ext = path.extension(file.path);
    final fileName = '$safeTitle$ext';

    final fileMeta = drive.File()
      ..name = fileName
      ..parents = [mangaId];

    final media = drive.Media(file.openRead(), file.lengthSync());
    await _driveApi!.files.create(
      fileMeta,
      uploadMedia: media,
      supportsAllDrives: true,
    );
  }

  // Xóa một chapter khỏi Drive theo fileId.
  Future<void> deleteChapter(String chapterId, {String? mangaId}) async {
    await ensureDriveAccess();
    if (mangaId != null) {
      _chapterCache.remove(mangaId);
    } else {
      _chapterCache.clear();
    }
    try {
      await _driveApi!.files.delete(chapterId, supportsAllDrives: true);
    } catch (e) {
      if (e is drive.DetailedApiRequestError && e.status == 404) {
        print('Chapter đã bị xoá trước đó (404).');
        return;
      }
      rethrow;
    }
  }

  // Cập nhật thứ tự chapter mới (Admin kéo thả để sắp xếp lại).
  // Cập nhật RAM cache trước để UI phản hồi ngay, rồi ghi info.json và catalog.json.
  Future<void> saveChapterOrder(String mangaId, List<String> newOrder) async {
    await ensureDriveAccess();

    final currentMangas = await getMangas();
    final index = currentMangas.indexWhere((c) => c.id == mangaId);
    if (index == -1) return;

    final currentManga = currentMangas[index];
    final updatedManga = CloudManga(
      id: currentManga.id,
      title: currentManga.title,
      author: currentManga.author,
      description: currentManga.description,
      coverFileId: currentManga.coverFileId,
      updatedAt: currentManga.updatedAt,
      genres: currentManga.genres,
      status: currentManga.status,
      viewCount: currentManga.viewCount,
      likeCount: currentManga.likeCount,
      chapterOrder: newOrder,
      contentType: currentManga.contentType,
      uploaderGroupId: currentManga.uploaderGroupId,
      uploaderGroupName: currentManga.uploaderGroupName,
    );

    // Cập nhật cache RAM trước để UI không thấy lag
    currentMangas[index] = updatedManga;
    _cachedMangas = currentMangas;

    // Ghi info.json cập nhật thứ tự chương
    try {
      final infoQuery =
          "name = 'info.json' and '$mangaId' in parents and trashed = false";
      final infoFiles = await _driveApi!.files.list(
        q: infoQuery,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      final infoContent = jsonEncode(updatedManga.toMap());
      final encodedJson = utf8.encode(infoContent);
      final media = drive.Media(Stream.value(encodedJson), encodedJson.length);

      if (infoFiles.files != null && infoFiles.files!.isNotEmpty) {
        await _driveApi!.files.update(
          drive.File(),
          infoFiles.files!.first.id!,
          uploadMedia: media,
          supportsAllDrives: true,
        );
      } else {
        final infoMeta = drive.File()
          ..name = 'info.json'
          ..parents = [mangaId];
        await _driveApi!.files.create(
          infoMeta,
          uploadMedia: media,
          supportsAllDrives: true,
        );
      }
    } catch (e) {
      print('Warning save order info.json: $e');
    }

    await _updateCatalog(updatedManga);
    _chapterCache.remove(mangaId);
  }

  // ── TIỆN ÍCH ───────────────────────────────────────────────────────────────

  // Tạo URL thumbnail public của ảnh trên Drive (dùng API key tĩnh).
  // (Phương thức này được giữ cho Admin, user thường dùng mediaUrl hoặc getThumbnailLink bên class)
  // Lấy thông tin cơ bản của file Drive (id, name, parents).
  Future<Map<String, dynamic>?> getFile(String fileId) async {
    try {
      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files/$fileId'
        '?fields=id,name,parents,mimeType,size'
        '&supportsAllDrives=true&key=${DriveConfig.apiKey}',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return {
          'id': data['id'],
          'name': data['name'],
          'parents': data['parents'],
          'mimeType': data['mimeType'],
          'size': data['size'],
        };
      }
      return null;
    } catch (e) {
      print('Lỗi khi lấy thông tin file: $e');
      return null;
    }
  }

  /// Tải tệp tin trực tiếp vào tệp (.part) với hỗ trợ thử lại và hủy
  Future<bool> downloadFileToFile(
    String fileId,
    File file, {
    Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final lockKey = file.path;
    if (_activeFileDownloads.containsKey(lockKey)) {
      print('File đang được tải, tái sử dụng Future: $lockKey');
      return _activeFileDownloads[lockKey]!;
    }

    final downloadFuture = _performDownloadFileToFile(
      fileId,
      file,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    _activeFileDownloads[lockKey] = downloadFuture;

    try {
      return await downloadFuture;
    } finally {
      _activeFileDownloads.remove(lockKey);
    }
  }

  Future<bool> _performDownloadFileToFile(
    String fileId,
    File file, {
    Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      if (isCancelled != null && isCancelled()) {
        return false;
      }

      IOSink? sink;
      try {
        if (retryCount > 0) {
          print('Retry download to file ($retryCount/$maxRetries): $fileId');
        }

        if (!await file.parent.exists()) {
          await file.parent.create(recursive: true);
        }

        // Kiểm tra xem file .part đã có sẵn dung lượng nào chưa để tiếp tục (Resume)
        int existingBytes = 0;
        if (await file.exists()) {
          existingBytes = await file.length();
        }

        final apiMediaUrl = Uri.parse(
          'https://www.googleapis.com/drive/v3/files/$fileId'
          '?alt=media&key=${DriveConfig.apiKey}',
        );

        final req1 = http.Request('GET', apiMediaUrl);
        if (existingBytes > 0) {
          req1.headers['Range'] = 'bytes=$existingBytes-';
        }

        http.StreamedResponse response = await _httpClient
            .send(req1)
            .timeout(const Duration(seconds: 300));

        if ((response.statusCode != 200 && response.statusCode != 206) ||
            (response.headers['content-type']?.toLowerCase().contains(
                  'text/html',
                ) ??
                false)) {
          final publicUrl = Uri.parse(
            'https://drive.google.com/uc?export=download&id=$fileId',
          );
          final req2 = http.Request('GET', publicUrl);
          if (existingBytes > 0) {
            req2.headers['Range'] = 'bytes=$existingBytes-';
          }
          response = await _httpClient
              .send(req2)
              .timeout(const Duration(seconds: 300));
        }

        if (response.statusCode == 404) {
          print('File not found on Drive: $fileId');
          return false;
        }

        if (response.statusCode == 416) {
          // Range Not Satisfiable: file đã hoàn thành hoặc không hỗ trợ range cũ
          print('HTTP 416 (Range Satisfied / Complete) for $fileId');
          return true;
        }

        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception('HTTP ${response.statusCode}');
        }

        if (response.headers['content-type']?.toLowerCase().contains(
              'text/html',
            ) ??
            false) {
          throw Exception(
            'Drive returned an HTML page instead of chapter bytes',
          );
        }

        final isPartial = response.statusCode == 206;
        final total = isPartial
            ? (existingBytes + (response.contentLength ?? 0))
            : (response.contentLength ?? 0);
        int received = isPartial ? existingBytes : 0;

        // Mở file: append nếu 206 (tiếp tục), write nếu 200 (tải lại từ đầu)
        sink = file.openWrite(mode: isPartial ? FileMode.append : FileMode.write);

        DateTime lastProgressTime = DateTime.now();
        if (onProgress != null && total > 0) {
          onProgress(received, total);
        }

        await for (final chunk in response.stream) {
          if (isCancelled != null && isCancelled()) {
            throw Exception('Đã hủy tải truyện');
          }
          sink.add(chunk);
          received += chunk.length;

          final now = DateTime.now();
          if (onProgress != null && total > 0 &&
              (now.difference(lastProgressTime).inMilliseconds >= 100 || received == total)) {
            onProgress(received, total);
            lastProgressTime = now;
          }
        }
        await sink.flush();
        await sink.close();
        sink = null; // Đặt null để finally block không đóng lần 2

        print('Tải file hoàn tất (sink): $fileId ($received bytes)');
        if (onProgress != null && total == 0) onProgress(100, 100);

        return true;
      } catch (e) {
        final errorText = e.toString().toLowerCase();
        if (errorText.contains('cancelled') ||
            errorText.contains('đã hủy tải truyện')) {
          print('Hủy hoặc tạm dừng tải xuống: $fileId (giữ file $file)');
          return false;
        }
        print('Lỗi tải file to sink (Attempt ${retryCount + 1}): $e');
        retryCount++;

        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('not found') || errorStr.contains('404')) {
          return false;
        }

        if (retryCount >= maxRetries) {
          return false;
        }
        await Future.delayed(Duration(seconds: retryCount * 2));
      } finally {
        if (sink != null) {
          try {
            await sink.flush();
            await sink.close();
          } catch (_) {}
        }
      }
    }
    return false;
  }

  // Tải file từ Drive về dạng bytes. Không cần theo dõi tiến độ.
  Future<Uint8List?> downloadFile(String fileId) async {
    return downloadFileWithProgress(fileId);
  }

  // Tải file từ Drive kèm callback tiến độ. Ưu tiên cache, retry tối đa 3 lần với backoff.
  // Trả về null nếu file không tồn tại (404) hoặc tất cả lần retry đều thất bại.
  Future<Uint8List?> downloadFileWithProgress(
    String fileId, {
    Function(int received, int total)? onProgress,
  }) async {
    // Trả về ngay từ cache nếu đã tải trước đó
    if (_fileCache.containsKey(fileId)) {
      print('Lấy từ cache: $fileId');
      if (onProgress != null) onProgress(100, 100);
      return _fileCache[fileId];
    }

    if (_activeDownloadFutures.containsKey(fileId)) {
      print('Đang tải rồi, tái sử dụng Future: $fileId');
      return _activeDownloadFutures[fileId];
    }

    final downloadFuture = _performDownloadFileWithProgress(
      fileId,
      onProgress: onProgress,
    );
    _activeDownloadFutures[fileId] = downloadFuture;

    try {
      return await downloadFuture;
    } finally {
      _activeDownloadFutures.remove(fileId);
    }
  }

  Future<Uint8List?> _performDownloadFileWithProgress(
    String fileId, {
    Function(int received, int total)? onProgress,
  }) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        if (retryCount > 0) {
          print('🔄 Retry download ($retryCount/$maxRetries): $fileId');
        } else {
          print('Đang tải file: $fileId');
        }

        final apiMediaUrl = Uri.parse(
          'https://www.googleapis.com/drive/v3/files/$fileId'
          '?alt=media&key=${DriveConfig.apiKey}',
        );

        http.StreamedResponse response = await _httpClient
            .send(http.Request('GET', apiMediaUrl))
            .timeout(const Duration(seconds: 300));

        if (response.statusCode != 200 ||
            (response.headers['content-type']?.toLowerCase().contains(
                  'text/html',
                ) ??
                false)) {
          final publicUrl = Uri.parse(
            'https://drive.google.com/uc?export=download&id=$fileId',
          );
          response = await _httpClient
              .send(http.Request('GET', publicUrl))
              .timeout(const Duration(seconds: 300));
        }

        if (response.statusCode == 404) {
          print('File not found on Drive: $fileId');
          return null;
        }

        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }

        if (response.headers['content-type']?.toLowerCase().contains(
              'text/html',
            ) ??
            false) {
          throw Exception(
            'Drive returned an HTML page instead of chapter bytes',
          );
        }

        final total = response.contentLength ?? 0;
        int received = 0;
        final bytes = <int>[];

        await for (final chunk in response.stream) {
          bytes.addAll(chunk);
          received += chunk.length;
          if (onProgress != null && total > 0) {
            onProgress(received, total);
          }
        }

        final result = Uint8List.fromList(bytes);

        print('✅ Tải file hoàn tất: $fileId (${result.length} bytes)');
        if (onProgress != null && total == 0) onProgress(100, 100);

        // Lưu vào cache nếu dung lượng < 20MB để tiết kiệm RAM (Chống OOM)
        if (result.length <= 20 * 1024 * 1024) {
          _fileCache[fileId] = result;
          _fileCacheOrder.add(fileId);
          _trimFileCache();
        }

        return result;
      } catch (e) {
        print('❌ Lỗi tải file (Attempt ${retryCount + 1}): $e');
        retryCount++;

        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('not found') || errorStr.contains('404')) {
          return null;
        }

        if (retryCount >= maxRetries) {
          return null;
        }
        await Future.delayed(Duration(seconds: retryCount));
      }
    }
    return null;
  }
}
