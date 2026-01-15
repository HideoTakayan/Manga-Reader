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
import '../services/interaction_service.dart';
import '../services/notification_service.dart';
import '../core/utils/chapter_sort_helper.dart';

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
  Completer<void>? _initCompleter;

  // ========================================
  // CƠ CHẾ CACHE FILE TRONG BỘ NHỚ
  // Lưu trữ tạm thời các file chương truyện để truy cập nhanh
  // Giới hạn 5 file để tối ưu bộ nhớ RAM (~50MB tối đa)
  // ========================================
  final Map<String, Uint8List> _fileCache = {};
  final List<String> _fileCacheOrder = [];
  static const int _maxCacheSize = 5;

  /// Xoá bớt cache cũ nhất khi đạt giới hạn kích thước
  void _trimFileCache() {
    while (_fileCacheOrder.length > _maxCacheSize) {
      final oldestKey = _fileCacheOrder.removeAt(0);
      _fileCache.remove(oldestKey);
      print('🗑️ Đã giải phóng cache: $oldestKey');
    }
  }

  /// Truy xuất file từ bộ nhớ đệm nếu tồn tại
  Uint8List? getCachedFile(String fileId) => _fileCache[fileId];

  /// Xoá toàn bộ bộ nhớ đệm (sử dụng khi thiếu hụt bộ nhớ)
  void clearFileCache() {
    _fileCache.clear();
    _fileCacheOrder.clear();
  }

  // Luồng sự kiện theo dõi trạng thái đăng nhập Google
  final _authController = StreamController<GoogleSignInAccount?>.broadcast();
  Stream<GoogleSignInAccount?> get onAuthStateChanged => _authController.stream;
  GoogleSignInAccount? get currentUser => _currentUser;

  // Cấu hình thư mục gốc lưu trữ dữ liệu trên Drive
  String? _rootFolderId;
  static const String _rootFolderName = 'MangaReader_Data';
  static const String _catalogFileName = 'catalog.json';

  // === CÁC PHƯƠNG THỨC XÁC THỰC NGƯỜI DÙNG ===

  /// Đăng nhập bằng Google Sign In và khởi tạo Drive API
  Future<GoogleSignInAccount?> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      if (_currentUser == null) {
        throw Exception('Người dùng đã huỷ thao tác đăng nhập');
      }
      await _initializeDriveApi();
      _authController.add(_currentUser);
      return _currentUser;
    } catch (e) {
      print('Lỗi đăng nhập Google: $e');
      _currentUser = null;
      _driveApi = null;
      rethrow;
    }
  }

  /// Khôi phục phiên đăng nhập trước đó (đăng nhập im lặng)
  Future<GoogleSignInAccount?> restorePreviousSession() async {
    try {
      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser != null) {
        await _initializeDriveApi();
      }
      _authController.add(_currentUser);
      return _currentUser;
    } catch (e) {
      print('Lỗi khôi phục phiên đăng nhập: $e');
      _currentUser = null;
      _authController.add(null);
      return null;
    }
  }

  /// Khởi tạo Google Drive API client từ tài khoản người dùng
  Future<void> _initializeDriveApi() async {
    if (_currentUser != null) {
      final httpClient = await _googleSignIn.authenticatedClient();
      if (httpClient != null) {
        _driveApi = drive.DriveApi(httpClient);
      }
    }
  }

  /// Đăng xuất khỏi tài khoản Google
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

  // === KHỞI TẠO VÀ QUẢN LÝ THƯ MỤC LƯU TRỮ GỐC ===

  /// Thiết lập thư mục gốc trên Drive để lưu trữ truyện
  Future<void> _initRootFolder() async {
    if (_rootFolderId != null) return;

    if (_driveApi == null) {
      await _initServiceAccount();
    }

    _rootFolderId = DriveConfig.PUBLIC_FOLDER_ID;
    print('✅ Sử dụng thư mục công khai: $_rootFolderId');
  }

  /// Khởi tạo kết nối Service Account để đọc dữ liệu công khai (không cần login User)
  /// Sử dụng Completer để tránh khởi tạo nhiều lần cùng lúc
  Future<void> _initServiceAccount() async {
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    try {
      print('🔐 Đang khởi tạo Service Account...');

      final credentials = auth.ServiceAccountCredentials.fromJson(
        jsonDecode(serviceAccountJson),
      );

      final scopes = [drive.DriveApi.driveReadonlyScope];

      final client = await auth.clientViaServiceAccount(credentials, scopes);
      _authClient = client;
      _driveApi = drive.DriveApi(client);

      print('✅ Service Account đã sẵn sàng');
      _initCompleter!.complete();
    } catch (e) {
      print('❌ Lỗi khởi tạo Service Account: $e');
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  Future<Map<String, String>> get headers async {
    if (_authClient == null) await _initServiceAccount();
    return {
      'Authorization': 'Bearer ${_authClient!.credentials.accessToken.data}',
    };
  }

  // === CÁC PHƯƠNG THỨC QUẢN LÝ TRUYỆN ===

  /// Lấy danh sách toàn bộ truyện từ Drive và đồng bộ lượt xem/thích từ Firestore
  Future<List<CloudComic>> getComics({bool forceRefresh = false}) async {
    // Sử dụng cache nếu không có yêu cầu làm mới
    if (!forceRefresh && _cachedComics != null) return _cachedComics!;

    try {
      await _initRootFolder();
      if (_rootFolderId == null) return [];

      if (_driveApi == null) await _initServiceAccount();

      // 1. Tải file catalog.json chứa danh sách truyện tĩnh từ Drive (Thử lại tối đa 3 lần)
      int retryCount = 0;
      bool success = false;
      List<CloudComic> comics = [];

      while (retryCount < 3 && !success) {
        try {
          final q =
              "name = '$_catalogFileName' and '$_rootFolderId' in parents and trashed = false";
          final fileList = await _driveApi!.files.list(q: q);

          if (fileList.files != null && fileList.files!.isNotEmpty) {
            final fileId = fileList.files!.first.id!;
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
            comics = jsonList.map((e) => CloudComic.fromMap(e)).toList();
            success = true;
          } else {
            success = true; // Không có catalog thì coi như xong
          }
        } catch (e) {
          retryCount++;
          print('⚠️ Lỗi tải catalog (Lần $retryCount): $e');
          if (retryCount >= 3) rethrow;
          await Future.delayed(
            const Duration(seconds: 1),
          ); // Chờ 1s rồi tải lại
        }
      }

      // 2. Lấy dữ liệu thống kê thời gian thực (Views/Likes) từ Firestore
      // Kết hợp dữ liệu tĩnh với dữ liệu động để UI luôn cập nhật mới nhất
      try {
        final statsMap = await InteractionService.instance.getAllComicStats();

        comics = comics.map((c) {
          if (statsMap.containsKey(c.id)) {
            final stats = statsMap[c.id]!;
            return CloudComic(
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
            );
          }
          return c;
        }).toList();
      } catch (e) {
        print('Lỗi khi tải thống kê trực tuyến: $e');
        // Vẫn tiếp tục nếu lỗi thống kê, chỉ hiển thị dữ liệu tĩnh
      }

      _cachedComics = comics;
      return _cachedComics!;
    } catch (e) {
      print('Lỗi khi tải danh sách truyện: $e');
      return [];
    }
  }

  /// Thêm mới một bộ truyện lên Drive (Tạo Folder, Upload Bìa, Upload Info)
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
      throw Exception('Không tìm thấy thư mục gốc.');
    }

    // Bước 1: Tạo thư mục chứa truyện mới
    final folderMeta = drive.File()
      ..name = title
      ..parents = [_rootFolderId!]
      ..mimeType = 'application/vnd.google-apps.folder';

    final folder = await _driveApi!.files.create(folderMeta);
    final folderId = folder.id!;

    // Bước 2: Upload ảnh bìa lên thư mục đó
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

    // Bước 3: Tạo đối tượng truyện
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

    // Bước 4: Tạo file info.json chứa metadata truyện
    final infoMeta = drive.File()
      ..name = 'info.json'
      ..parents = [folderId];

    final infoContent = jsonEncode(comic.toMap());
    final infoBytes = utf8.encode(infoContent);
    final infoMedia = drive.Media(Stream.value(infoBytes), infoBytes.length);
    await _driveApi!.files.create(infoMeta, uploadMedia: infoMedia);

    // Bước 5: Cập nhật lại catalog.json toàn cục
    await _updateCatalog(comic);
  }

  /// Cập nhật file catalog.json trên Drive để đồng bộ danh sách
  Future<void> _updateCatalog(CloudComic newComic) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) throw Exception('Chưa đăng nhập Google Drive');
    if (_rootFolderId == null) await _initRootFolder();

    List<CloudComic> currentList = await getComics();
    currentList.removeWhere((c) => c.id == newComic.id);
    currentList.insert(0, newComic);

    final jsonContent = jsonEncode(currentList.map((e) => e.toMap()).toList());
    final encodedJson = utf8.encode(jsonContent);

    // Tìm file catalog.json hiện có để ghi đè
    String? catalogFileId;
    try {
      final q =
          "name = '$_catalogFileName' and '$_rootFolderId' in parents and trashed = false";
      final fileList = await _driveApi!.files.list(q: q);

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        catalogFileId = fileList.files!.first.id;
      }
    } catch (e) {
      print('Warning finding catalog: $e');
    }

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

  /// Xoá truyện khỏi Drive và cập nhật Catalog
  Future<void> deleteComic(String comicId) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) throw Exception('Chưa đăng nhập Google Drive');

    // Bước 1: Xóa toàn bộ thư mục truyện trên Drive
    try {
      await _driveApi!.files.delete(comicId);
    } catch (e) {
      print('Lỗi khi xoá thư mục: $e');
    }

    // Bước 2: Xóa thông tin khỏi danh sách hiển thị
    List<CloudComic> currentList = await getComics();
    currentList.removeWhere((c) => c.id == comicId);

    // Bước 3: Lưu lại danh sách mới vào Drive
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

  /// Quét lại toàn bộ thư mục dữ liệu để tái tạo file Catalog (dùng khi dữ liệu bị lỗi)
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
      // Bước 1: Liệt kê tất cả thư mục con (truyện)
      final foldersQuery =
          "mimeType = 'application/vnd.google-apps.folder' and '$_rootFolderId' in parents and trashed = false";
      final folderList = await _driveApi!.files.list(q: foldersQuery);

      if (folderList.files == null || folderList.files!.isEmpty) {
        _cachedComics = [];
        await _saveCatalogToDrive([]);
        return;
      }

      // Bước 2: Đọc file info.json trong từng thư mục truyện
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

            final List<int> bytes = [];
            await for (final chunk in media.stream) {
              bytes.addAll(chunk);
            }
            final content = utf8.decode(bytes);
            final Map<String, dynamic> comicMap = jsonDecode(content);
            comics.add(CloudComic.fromMap(comicMap));
          } else {
            print(
              '⚠️ Thiếu info.json cho ${folder.name}, đang tạo file mặc định...',
            );
            final defaultComic = CloudComic(
              id: folder.id!,
              title: folder.name!,
              author: 'Không rõ',
              description: 'Chưa có mô tả.',
              coverFileId: '',
              updatedAt: folder.modifiedTime ?? DateTime.now(),
              genres: [],
              status: 'Không rõ',
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
          print('Lỗi khi đọc info.json của ${folder.name}: $e');
        }
      }

      // Bước 3: Sắp xếp truyện theo thời gian cập nhật
      comics.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      // Bước 4: Lưu catalog mới
      await _saveCatalogToDrive(comics);

      // Bước 5: Cập nhật cache
      _cachedComics = comics;

      print('✅ Đã tái tạo catalog với ${comics.length} truyện');
    } catch (e) {
      print('Lỗi tái tạo catalog: $e');
      rethrow;
    }
  }

  /// Helper để lưu danh sách truyện xuống file catalog.json
  Future<void> _saveCatalogToDrive(List<CloudComic> comics) async {
    final jsonContent = jsonEncode(comics.map((e) => e.toMap()).toList());

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

  /// Cập nhật thông tin của một truyện (tiêu đề, tác giả, ảnh bìa...)
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

    // Bước 2: Upload ảnh bìa mới nếu có
    if (newCoverFile != null) {
      final coverMeta = drive.File()
        ..name = 'cover.${path.extension(newCoverFile.path)}'
        ..parents = [comicId];

      final coverMedia = drive.Media(
        newCoverFile.openRead(),
        newCoverFile.lengthSync(),
      );

      // Xoá ảnh bìa cũ để tiết kiệm dung lượng
      try {
        await _driveApi!.files.delete(currentComic.coverFileId);
      } catch (e) {
        print('Lỗi khi xoá ảnh bìa cũ: $e');
      }

      // Tạo ảnh bìa mới
      final coverResult = await _driveApi!.files.create(
        coverMeta,
        uploadMedia: coverMedia,
      );
      coverFileId = coverResult.id!;
    }

    // Bước 3: Cập nhật object truyện
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

    // Bước 4: Cập nhật file info.json trong thư mục truyện
    try {
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
      } else {
        // Fallback: nếu chưa có info.json thì tạo mới
        final infoMeta = drive.File()
          ..name = 'info.json'
          ..parents = [comicId];
        await _driveApi!.files.create(infoMeta, uploadMedia: infoMedia);
      }
    } catch (e) {
      print('Warning updating info.json: $e');
      // Không throw lỗi ở đây để tránh crash flow chính, chỉ log warning
    }

    // Bước 5: Cập nhật Catalog
    await _updateCatalog(updatedComic);

    // Bước 6: Gửi thông báo nếu trạng thái thay đổi
    if (currentComic.status != status) {
      String msg =
          'Truyện "${currentComic.title}" đã chuyển sang trạng thái $status';
      if (status.toLowerCase().contains('hoàn thành')) {
        msg =
            'Truyện "${currentComic.title}" đã Hoàn Thành. Mời bạn vào đọc trọn bộ!';
      } else if (status.toLowerCase().contains('ngừng') ||
          status.toLowerCase().contains('drop')) {
        msg = 'Truyện "${currentComic.title}" đã bị tạm ngưng.';
      }

      await NotificationService.instance.notifySubscribers(
        comicId: comicId,
        title: 'Cập nhật trạng thái',
        body: msg,
      );
    }
  }

  // === CÁC PHƯƠNG THỨC QUẢN LÝ CHAPTER ===

  /// Lấy danh sách các chapter của truyện từ Drive và đồng bộ lượt xem từ Firestore
  Future<List<CloudChapter>> getChapters(String comicId) async {
    try {
      if (_driveApi == null) await _initServiceAccount();

      // 1. Lấy danh sách file trong thư mục truyện (trừ info.json và cover)
      final q =
          "'$comicId' in parents and trashed = false and name != 'info.json' and not name contains 'cover.'";
      final fileList = await _driveApi!.files.list(
        q: q,
        $fields: 'files(id,name,mimeType,size,createdTime)',
        pageSize: 1000,
      );

      final allFiles = fileList.files ?? [];

      // 2. Lấy thống kê lượt xem từng chapter từ Firestore
      final statsMap = await InteractionService.instance.getChapterViews(
        comicId,
      );

      // 3. Chuyển đổi thành objects CloudChapter
      final files = allFiles.map((f) {
        String type = 'zip';
        if (f.name != null) {
          if (f.name!.endsWith('.epub')) type = 'epub';
          if (f.name!.endsWith('.cbz')) type = 'cbz';
          if (f.name!.endsWith('.pdf')) type = 'pdf';
        }

        // Gán lượt xem nếu có
        final views = statsMap[f.id] ?? 0;

        return CloudChapter(
          id: f.id!,
          title: f.name ?? 'Không rõ',
          fileId: f.id!,
          fileType: type,
          sizeBytes: int.tryParse(f.size ?? '0') ?? 0,
          uploadedAt: f.createdTime ?? DateTime.now(),
          viewCount: views,
        );
      }).toList();

      // Sử dụng ChapterSortHelper để sắp xếp chapter thông minh (Numeric + Extra)
      List<CloudChapter> sortedFiles = ChapterSortHelper.sort(files);

      // Nếu có order thủ công (từ Catalog), áp dụng nó trùm lên (nếu muốn ưu tiên thủ công)
      // Nhưng theo yêu cầu Final, chúng ta sẽ ưu tiên logic parse số chương

      return sortedFiles;
    } catch (e) {
      print('Lỗi lấy danh sách chapter: $e');
      return [];
    }
  }

  /// Upload một chapter mới lên Drive
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

    // Làm sạch tên file
    final safeTitle = title.replaceAll(RegExp(r'[^a-zA-Z0-9\s\-]'), '').trim();
    final ext = path.extension(file.path);
    final fileName = '$safeTitle$ext';

    // Metadata file
    final fileMeta = drive.File()
      ..name = fileName
      ..parents = [comicId];

    final media = drive.Media(file.openRead(), file.lengthSync());
    await _driveApi!.files.create(fileMeta, uploadMedia: media);

    // Gửi thông báo chương mới
    await NotificationService.instance.notifySubscribers(
      comicId: comicId,
      title: 'Chương mới!',
      body: 'Chương "$title" vừa được cập nhật. Đọc ngay!',
    );
  }

  /// Xoá một chapter
  Future<void> deleteChapter(String chapterId) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) {
      throw Exception(
        'Không thể kết nối đến Google Drive. Vui lòng đăng nhập.',
      );
    }

    await _driveApi!.files.delete(chapterId);
  }

  /// Lưu thứ tự chapter mới (dùng cho tính năng sắp xếp)
  Future<void> saveChapterOrder(String comicId, List<String> newOrder) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) return;

    // Bước 1: Cập nhật bộ nhớ đệm
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
    try {
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
      } else {
        final infoMeta = drive.File()
          ..name = 'info.json'
          ..parents = [comicId];
        await _driveApi!.files.create(infoMeta, uploadMedia: media);
      }
    } catch (e) {
      print('Warning save order info.json: $e');
    }

    // Bước 3: Cập nhật Catalog
    await _updateCatalog(updatedComic);
  }

  // === CÁC TITỆN ÍCH HỖ TRỢ ===

  /// Lấy link thumbnail của ảnh từ Drive (Bắt buộc phải công khai hoặc có Access Token)
  String getThumbnailLink(String fileId) {
    return 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media&key=${DriveConfig.API_KEY}';
  }

  /// Lấy thông tin cơ bản của file (id, name, parents)
  Future<Map<String, dynamic>?> getFile(String fileId) async {
    try {
      if (_driveApi == null) await _initServiceAccount();

      final file =
          await _driveApi!.files.get(fileId, $fields: 'id,name,parents')
              as drive.File;

      return {'id': file.id, 'name': file.name, 'parents': file.parents};
    } catch (e) {
      print('Lỗi khi lấy thông tin file: $e');
      return null;
    }
  }

  /// Tải xuống nội dung file từ Drive dưới dạng bytes (Ưu tiên Cache)
  Future<Uint8List?> downloadFile(String fileId) async {
    // Kiểm tra cache trước
    if (_fileCache.containsKey(fileId)) {
      print('⚡ Lấy từ Cache: $fileId');
      return _fileCache[fileId];
    }

    try {
      print('📥 Đang tải file (Service Account): $fileId');

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

      // Lưu vào cache và dọn dẹp nếu đầy
      _fileCache[fileId] = result;
      _fileCacheOrder.add(fileId);
      _trimFileCache();

      return result;
    } catch (e) {
      print('❌ Lỗi tải file: $e');
      return null;
    }
  }
}
