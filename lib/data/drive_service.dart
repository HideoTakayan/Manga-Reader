import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:path/path.dart' as path;
import 'models_cloud.dart';
import '../config/drive_config.dart';
import '../config/service_account_credentials.dart';

class DriveService {
  static final DriveService instance = DriveService._internal();
  DriveService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveScope],
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  auth.AutoRefreshingAuthClient? _authClient;
  List<CloudComic>? _cachedComics;

  // ========================================
  // OPTIMIZATION: In-memory file cache
  // Stores downloaded chapter files for fast access
  // Max 5 items to avoid memory issues (~50MB max)
  // ========================================
  final Map<String, Uint8List> _fileCache = {};
  final List<String> _fileCacheOrder = [];
  static const int _maxCacheSize = 5;

  /// Clear old cache entries when limit is reached
  void _trimFileCache() {
    while (_fileCacheOrder.length > _maxCacheSize) {
      final oldestKey = _fileCacheOrder.removeAt(0);
      _fileCache.remove(oldestKey);
      print('🗑️ Evicted from cache: $oldestKey');
    }
  }

  /// Get cached file if available
  Uint8List? getCachedFile(String fileId) => _fileCache[fileId];

  /// Clear entire file cache (useful when memory is low)
  void clearFileCache() {
    _fileCache.clear();
    _fileCacheOrder.clear();
  }

  // Stream thông báo thay đổi trạng thái đăng nhập
  final _authController = StreamController<GoogleSignInAccount?>.broadcast();
  Stream<GoogleSignInAccount?> get onAuthStateChanged => _authController.stream;
  GoogleSignInAccount? get currentUser => _currentUser;

  // Folder gốc chứa dữ liệu truyện
  String? _rootFolderId;
  static const String _rootFolderName = 'MangaReader_Data';
  static const String _catalogFileName = 'catalog.json';

  // === PHƯƠNG THỨC XÁC THỰC ===
  Future<GoogleSignInAccount?> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      if (_currentUser == null) {
        throw Exception('Đăng nhập bị hủy bởi người dùng');
      }
      await _initializeDriveApi();
      _authController.add(_currentUser);
      return _currentUser;
    } catch (e) {
      print('Google Sign In Error: $e');
      _currentUser = null;
      _driveApi = null;
      rethrow;
    }
  }

  Future<GoogleSignInAccount?> restorePreviousSession() async {
    try {
      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser != null) {
        await _initializeDriveApi();
      }
      _authController.add(_currentUser);
      return _currentUser;
    } catch (e) {
      print('Silent Sign In Error: $e');
      _currentUser = null;
      _authController.add(null);
      return null;
    }
  }

  Future<void> _initializeDriveApi() async {
    if (_currentUser != null) {
      final httpClient = await _googleSignIn.authenticatedClient();
      if (httpClient != null) {
        _driveApi = drive.DriveApi(httpClient);
      }
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _driveApi = null;
    _rootFolderId = null;
    _authController.add(null);
  }

  Future<Map<String, String>> getHeaders() async {
    final headers = await _currentUser?.authHeaders;
    return headers ?? {};
  }

  // === KHỞI TẠO & QUẢN LÝ FOLDER GỐC ===
  Future<void> _initRootFolder() async {
    if (_rootFolderId != null) return;

    if (_driveApi == null) {
      await _initServiceAccount();
    }

    _rootFolderId = DriveConfig.PUBLIC_FOLDER_ID;
    print('✅ Using public folder: $_rootFolderId');
  }

  // Khởi tạo xác thực Service Account
  Future<void> _initServiceAccount() async {
    try {
      print('🔐 Initializing Service Account...');

      final credentials = auth.ServiceAccountCredentials.fromJson(
        jsonDecode(serviceAccountJson),
      );

      final scopes = [drive.DriveApi.driveReadonlyScope];

      final client = await auth.clientViaServiceAccount(credentials, scopes);
      _authClient = client;
      _driveApi = drive.DriveApi(client);

      print('✅ Service Account initialized');
    } catch (e) {
      print('❌ Error initializing Service Account: $e');
      rethrow;
    }
  }

  Future<Map<String, String>> get headers async {
    if (_authClient == null) await _initServiceAccount();
    return {
      'Authorization': 'Bearer ${_authClient!.credentials.accessToken.data}',
    };
  }

  // === QUẢN LÝ TRUYỆN ===
  Future<List<CloudComic>> getComics({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedComics != null) return _cachedComics!;

    try {
      await _initRootFolder();
      if (_rootFolderId == null) return [];

      if (_driveApi == null) await _initServiceAccount();

      final q =
          "name = '$_catalogFileName' and '$_rootFolderId' in parents and trashed = false";
      final fileList = await _driveApi!.files.list(q: q);

      if (fileList.files == null || fileList.files!.isEmpty) {
        _cachedComics = [];
        return [];
      }

      final fileId = fileList.files!.first.id!;

      // Download catalog.json content using Service Account
      final media =
          await _driveApi!.files.get(
                fileId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      final List<int> bytes = [];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }

      final content = utf8.decode(bytes);
      final List<dynamic> jsonList = jsonDecode(content);

      _cachedComics = jsonList.map((e) => CloudComic.fromMap(e)).toList();
      return _cachedComics!;
    } catch (e) {
      print('Error getting comics: $e');
      return [];
    }
  }

  Future<void> addComic({
    required String title,
    required String author,
    required String description,
    required File coverFile,
    required List<String> genres,
    required String status,
  }) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) {
      throw Exception(
        'Không thể kết nối đến Google Drive. Vui lòng đăng nhập.',
      );
    }

    await _initRootFolder();
    if (_rootFolderId == null) {
      throw Exception('Không thể tạo thư mục gốc lưu trữ.');
    }

    // Bước 1: Tạo folder truyện
    final folderMeta = drive.File()
      ..name = title
      ..parents = [_rootFolderId!]
      ..mimeType = 'application/vnd.google-apps.folder';

    final folder = await _driveApi!.files.create(folderMeta);
    final folderId = folder.id!;

    // Bước 2: Upload ảnh bìa
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
    );

    // Bước 3: Tạo đối tượng CloudComic
    final comic = CloudComic(
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
    );

    // Bước 4: Lưu info.json vào folder
    final infoMeta = drive.File()
      ..name = 'info.json'
      ..parents = [folderId];

    final infoContent = jsonEncode(comic.toMap());
    final infoBytes = utf8.encode(infoContent);
    final infoMedia = drive.Media(Stream.value(infoBytes), infoBytes.length);
    await _driveApi!.files.create(infoMeta, uploadMedia: infoMedia);

    // Bước 5: Cập nhật catalog.json
    await _updateCatalog(comic);
  }

  Future<void> _updateCatalog(CloudComic newComic) async {
    List<CloudComic> currentList = await getComics();
    currentList.removeWhere((c) => c.id == newComic.id);
    currentList.insert(0, newComic);

    final jsonContent = jsonEncode(currentList.map((e) => e.toMap()).toList());

    // Tìm catalog.json để ghi đè hoặc tạo mới
    String? catalogFileId;
    final q =
        "name = '$_catalogFileName' and '$_rootFolderId' in parents and trashed = false";
    final fileList = await _driveApi!.files.list(q: q);

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
      );
    } else {
      final fileMeta = drive.File()
        ..name = _catalogFileName
        ..parents = [_rootFolderId!];
      await _driveApi!.files.create(fileMeta, uploadMedia: media);
    }
    _cachedComics = currentList;
  }

  Future<void> deleteComic(String comicId) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) throw Exception('Chưa đăng nhập Google Drive');

    // Bước 1: Xóa folder trên Drive
    try {
      await _driveApi!.files.delete(comicId);
    } catch (e) {
      print('Error deleting folder: $e');
    }

    // Bước 2: Xóa khỏi catalog
    List<CloudComic> currentList = await getComics();
    currentList.removeWhere((c) => c.id == comicId);

    // Bước 3: Lưu catalog
    final jsonContent = jsonEncode(currentList.map((e) => e.toMap()).toList());

    String? catalogFileId;
    final q =
        "name = '$_catalogFileName' and '$_rootFolderId' in parents and trashed = false";
    final fileList = await _driveApi!.files.list(q: q);

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
      );
    } else {
      final fileMeta = drive.File()
        ..name = _catalogFileName
        ..parents = [_rootFolderId!];
      await _driveApi!.files.create(fileMeta, uploadMedia: media);
    }

    _cachedComics = currentList;
  }

  // Quét tất cả folder trong MangaReader_Data và tái tạo catalog.json
  Future<void> rebuildCatalog() async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) {
      throw Exception(
        'Không thể kết nối đến Google Drive. Vui lòng đăng nhập.',
      );
    }

    await _initRootFolder();
    if (_rootFolderId == null) return;

    try {
      // Bước 1: Lấy tất cả folder trong MangaReader_Data
      final foldersQuery =
          "mimeType = 'application/vnd.google-apps.folder' and '$_rootFolderId' in parents and trashed = false";
      final folderList = await _driveApi!.files.list(q: foldersQuery);

      if (folderList.files == null || folderList.files!.isEmpty) {
        _cachedComics = [];
        await _saveCatalogToDrive([]);
        return;
      }

      // Bước 2: Với mỗi folder, đọc info.json
      final List<CloudComic> comics = [];
      for (final folder in folderList.files!) {
        try {
          final infoQuery =
              "name = 'info.json' and '${folder.id}' in parents and trashed = false";
          final infoFiles = await _driveApi!.files.list(q: infoQuery);

          if (infoFiles.files != null && infoFiles.files!.isNotEmpty) {
            final infoFileId = infoFiles.files!.first.id!;
            final media =
                await _driveApi!.files.get(
                      infoFileId,
                      downloadOptions: drive.DownloadOptions.fullMedia,
                    )
                    as drive.Media;

            // Đọc stream không cần dựa vào contentLength
            final List<int> bytes = [];
            await for (final chunk in media.stream) {
              bytes.addAll(chunk);
            }
            final content = utf8.decode(bytes);
            final Map<String, dynamic> comicMap = jsonDecode(content);
            comics.add(CloudComic.fromMap(comicMap));
          } else {
            print(
              '⚠️ Không tìm thấy info.json cho ${folder.name}, tạo mặc định...',
            );
            final defaultComic = CloudComic(
              id: folder.id!,
              title: folder.name!,
              author: 'Unknown',
              description: 'No description available.',
              coverFileId: '',
              updatedAt: folder.modifiedTime ?? DateTime.now(),
              genres: [],
              status: 'Unknown',
            );

            // Upload info.json mặc định
            final infoMeta = drive.File()
              ..name = 'info.json'
              ..parents = [folder.id!];
            final infoContent = jsonEncode(defaultComic.toMap());
            final infoBytes = utf8.encode(infoContent);
            final infoMedia = drive.Media(
              Stream.value(infoBytes),
              infoBytes.length,
            );
            await _driveApi!.files.create(infoMeta, uploadMedia: infoMedia);

            comics.add(defaultComic);
          }
        } catch (e) {
          print('Error reading info.json for folder ${folder.name}: $e');
        }
      }

      // Bước 3: Sắp xếp theo updatedAt (mới nhất trước)
      comics.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      // Bước 4: Lưu vào catalog.json
      await _saveCatalogToDrive(comics);

      // Bước 5: Cập nhật cache
      _cachedComics = comics;

      print('✅ Rebuilt catalog with ${comics.length} comics');
    } catch (e) {
      print('Error rebuilding catalog: $e');
      rethrow;
    }
  }

  Future<void> _saveCatalogToDrive(List<CloudComic> comics) async {
    final jsonContent = jsonEncode(comics.map((e) => e.toMap()).toList());

    // Tìm catalog.json để ghi đè hoặc tạo mới
    String? catalogFileId;
    final q =
        "name = '$_catalogFileName' and '$_rootFolderId' in parents and trashed = false";
    final fileList = await _driveApi!.files.list(q: q);

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
      );
    } else {
      final fileMeta = drive.File()
        ..name = _catalogFileName
        ..parents = [_rootFolderId!];
      await _driveApi!.files.create(fileMeta, uploadMedia: media);
    }
  }

  Future<void> updateComic({
    required String comicId,
    required String title,
    required String author,
    required String description,
    required List<String> genres,
    required String status,
    File? newCoverFile,
  }) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) {
      throw Exception(
        'Không thể kết nối đến Google Drive. Vui lòng đăng nhập.',
      );
    }

    // Bước 1: Lấy thông tin truyện hiện tại
    final currentComics = await getComics();
    final currentComic = currentComics.firstWhere((c) => c.id == comicId);

    String coverFileId = currentComic.coverFileId;

    // Bước 2: Nếu có ảnh bìa mới, upload lên
    if (newCoverFile != null) {
      final coverMeta = drive.File()
        ..name = 'cover.${path.extension(newCoverFile.path)}'
        ..parents = [comicId];

      final coverMedia = drive.Media(
        newCoverFile.openRead(),
        newCoverFile.lengthSync(),
      );

      // Xóa ảnh bìa cũ
      try {
        await _driveApi!.files.delete(currentComic.coverFileId);
      } catch (e) {
        print('Error deleting old cover: $e');
      }

      // Upload ảnh bìa mới
      final coverResult = await _driveApi!.files.create(
        coverMeta,
        uploadMedia: coverMedia,
      );
      coverFileId = coverResult.id!;
    }

    // Bước 3: Tạo đối tượng CloudComic đã cập nhật
    final updatedComic = CloudComic(
      id: comicId,
      title: title,
      author: author,
      description: description,
      coverFileId: coverFileId,
      updatedAt: DateTime.now(),
      genres: genres,
      status: status,
      viewCount: currentComic.viewCount,
      likeCount: currentComic.likeCount,
      chapterOrder: currentComic.chapterOrder,
    );

    // Bước 4: Cập nhật info.json trong folder truyện
    final infoQuery =
        "name = 'info.json' and '$comicId' in parents and trashed = false";
    final infoFiles = await _driveApi!.files.list(q: infoQuery);

    final infoContent = jsonEncode(updatedComic.toMap());
    final infoBytes = utf8.encode(infoContent);
    final infoMedia = drive.Media(Stream.value(infoBytes), infoBytes.length);

    if (infoFiles.files != null && infoFiles.files!.isNotEmpty) {
      await _driveApi!.files.update(
        drive.File(),
        infoFiles.files!.first.id!,
        uploadMedia: infoMedia,
      );
    }

    // Bước 5: Cập nhật catalog.json
    await _updateCatalog(updatedComic);
  }

  // === QUẢN LÝ CHAPTER ===
  Future<List<CloudChapter>> getChapters(String comicId) async {
    try {
      if (_driveApi == null) await _initServiceAccount();

      final q =
          "'$comicId' in parents and trashed = false and name != 'info.json' and not name contains 'cover.'";
      final fileList = await _driveApi!.files.list(
        q: q,
        $fields: 'files(id,name,mimeType,size,createdTime)',
        pageSize: 1000,
      );

      final allFiles = fileList.files ?? [];

      final files = allFiles.map((f) {
        String type = 'zip';
        if (f.name != null) {
          if (f.name!.endsWith('.epub')) type = 'epub';
          if (f.name!.endsWith('.cbz')) type = 'cbz';
          if (f.name!.endsWith('.pdf')) type = 'pdf';
        }

        return CloudChapter(
          id: f.id!,
          title: f.name ?? 'Unknown',
          fileId: f.id!,
          fileType: type,
          sizeBytes: int.tryParse(f.size ?? '0') ?? 0,
          uploadedAt: f.createdTime ?? DateTime.now(),
        );
      }).toList();

      // Sort chapters
      List<String> order = [];
      if (_cachedComics != null) {
        try {
          final comic = _cachedComics!.firstWhere((c) => c.id == comicId);
          order = comic.chapterOrder;
        } catch (_) {}
      }

      if (order.isNotEmpty) {
        final orderMap = {for (var i = 0; i < order.length; i++) order[i]: i};
        files.sort((a, b) {
          if (orderMap.containsKey(a.id) && orderMap.containsKey(b.id)) {
            return orderMap[a.id]!.compareTo(orderMap[b.id]!);
          }
          if (orderMap.containsKey(a.id)) return -1;
          if (orderMap.containsKey(b.id)) return 1;
          return b.title.compareTo(a.title);
        });
      } else {
        files.sort((a, b) => b.title.compareTo(a.title));
      }

      return files;
    } catch (e) {
      print('Error getting chapters: $e');
      return [];
    }
  }

  Future<void> addChapter({
    required String comicId,
    required String title,
    required File file,
  }) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) {
      throw Exception(
        'Không thể kết nối đến Google Drive. Vui lòng đăng nhập.',
      );
    }

    final safeTitle = title.replaceAll(RegExp(r'[^a-zA-Z0-9\s\-]'), '').trim();
    final ext = path.extension(file.path);
    final fileName = '$safeTitle$ext';

    final fileMeta = drive.File()
      ..name = fileName
      ..parents = [comicId];

    final media = drive.Media(file.openRead(), file.lengthSync());
    await _driveApi!.files.create(fileMeta, uploadMedia: media);
  }

  Future<void> deleteChapter(String chapterId) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) {
      throw Exception(
        'Không thể kết nối đến Google Drive. Vui lòng đăng nhập.',
      );
    }

    await _driveApi!.files.delete(chapterId);
  }

  Future<void> saveChapterOrder(String comicId, List<String> newOrder) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) return;

    // Bước 1: Lấy thông tin truyện hiện tại để cập nhật
    final currentComics = await getComics();
    final index = currentComics.indexWhere((c) => c.id == comicId);
    if (index == -1) return;

    final currentComic = currentComics[index];
    final updatedComic = CloudComic(
      id: currentComic.id,
      title: currentComic.title,
      author: currentComic.author,
      description: currentComic.description,
      coverFileId: currentComic.coverFileId,
      updatedAt: currentComic.updatedAt,
      genres: currentComic.genres,
      status: currentComic.status,
      viewCount: currentComic.viewCount,
      likeCount: currentComic.likeCount,
      chapterOrder: newOrder,
    );

    // Bước 2: Cập nhật info.json
    final infoQuery =
        "name = 'info.json' and '$comicId' in parents and trashed = false";
    final infoFiles = await _driveApi!.files.list(q: infoQuery);

    final infoContent = jsonEncode(updatedComic.toMap());
    final encodedJson = utf8.encode(infoContent);
    final media = drive.Media(Stream.value(encodedJson), encodedJson.length);

    if (infoFiles.files != null && infoFiles.files!.isNotEmpty) {
      await _driveApi!.files.update(
        drive.File(),
        infoFiles.files!.first.id!,
        uploadMedia: media,
      );
    }

    // Bước 3: Cập nhật Catalog (Cache & Drive)
    await _updateCatalog(updatedComic);
  }

  // === TRỢ GIÚP ẢNH & NỘI DUNG ===
  String getThumbnailLink(String fileId) {
    return 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media&key=${DriveConfig.API_KEY}';
  }

  // Lấy metadata của file (ví dụ: parents)
  Future<Map<String, dynamic>?> getFile(String fileId) async {
    try {
      if (_driveApi == null) await _initServiceAccount();

      final file =
          await _driveApi!.files.get(fileId, $fields: 'id,name,parents')
              as drive.File;

      return {'id': file.id, 'name': file.name, 'parents': file.parents};
    } catch (e) {
      print('Error getting file: $e');
      return null;
    }
  }

  // Tải nội dung file dưới dạng bytes
  Future<Uint8List?> downloadFile(String fileId) async {
    // Check cache first for instant access
    if (_fileCache.containsKey(fileId)) {
      print('⚡ Cache hit: $fileId');
      return _fileCache[fileId];
    }

    try {
      print('📥 Downloading file (Service Account): $fileId');

      if (_driveApi == null) await _initServiceAccount();

      final media =
          await _driveApi!.files.get(
                fileId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      final List<int> bytes = [];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }

      final result = Uint8List.fromList(bytes);
      print('📦 Size: ${result.length} bytes');

      // Cache the downloaded file
      _fileCache[fileId] = result;
      _fileCacheOrder.add(fileId);
      _trimFileCache();
      print('💾 Cached: $fileId (${_fileCacheOrder.length}/$_maxCacheSize)');

      return result;
    } catch (e) {
      print('💥 Error downloading file: $e');
      return null;
    }
  }
}
