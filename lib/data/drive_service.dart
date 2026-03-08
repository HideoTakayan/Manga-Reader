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

// Singleton kết nối với Google Drive API.
// Xử lý toàn bộ việc đọc/ghi file truyện: lấy danh sách, upload chapter, download để đọc.
// Người dùng thường → đọc qua Service Account (không cần đăng nhập).
// Admin → đăng nhập Google (OAuth) để được quyền ghi lên Drive.
class DriveService {
  static final DriveService instance = DriveService._internal();
  DriveService._internal();

  // _googleSignIn: dùng cho luồng Admin (OAuth, có quyền ghi).
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveScope],
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  auth.AutoRefreshingAuthClient? _authClient; // Client của Service Account
  List<CloudManga>? _cachedMangas;
  Completer<void>? _initCompleter; // Chặn khởi tạo Service Account song song

  // Cache file ZIP/CBZ trong RAM để không phải tải lại khi chuyển chapter.
  // Giới hạn 5 file (~50MB) để tránh dùng quá nhiều RAM.
  final Map<String, Uint8List> _fileCache = {};
  final List<String> _fileCacheOrder = []; // Theo dõi thứ tự để xóa cái cũ nhất
  static const int _maxCacheSize = 5;

  // Xóa file cũ nhất trong cache khi vượt giới hạn.
  void _trimFileCache() {
    while (_fileCacheOrder.length > _maxCacheSize) {
      final oldestKey = _fileCacheOrder.removeAt(0);
      _fileCache.remove(oldestKey);
      print('🗑️ Đã giải phóng cache: $oldestKey');
    }
  }

  // Trả về file đang cache nếu có, null nếu chưa tải.
  Uint8List? getCachedFile(String fileId) => _fileCache[fileId];

  // Xóa toàn bộ cache RAM (dùng khi thiếu bộ nhớ).
  void clearFileCache() {
    _fileCache.clear();
    _fileCacheOrder.clear();
  }

  // Stream phát sự kiện khi trạng thái đăng nhập Google thay đổi.
  final _authController = StreamController<GoogleSignInAccount?>.broadcast();
  Stream<GoogleSignInAccount?> get onAuthStateChanged => _authController.stream;
  GoogleSignInAccount? get currentUser => _currentUser;

  // ID folder gốc trên Drive chứa toàn bộ dữ liệu app.
  String? _rootFolderId;
  static const String _rootFolderName = 'MangaReader_Data';
  static const String _catalogFileName = 'catalog.json'; // File danh mục tổng

  // ── XÁC THỰC NGƯỜI DÙNG (ADMIN) ────────────────────────────────────────────

  // Đăng nhập Google (OAuth) để lấy quyền ghi Drive. Chỉ Admin cần gọi.
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

  // Thử khôi phục phiên đăng nhập cũ khi mở app (im lặng, không hiện popup).
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

  // Khởi tạo Drive API client từ token của user đã đăng nhập (Admin).
  Future<void> _initializeDriveApi() async {
    if (_currentUser != null) {
      final httpClient = await _googleSignIn.authenticatedClient();
      if (httpClient != null) {
        _driveApi = drive.DriveApi(httpClient);
      }
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

  // Lấy/tạo folder gốc. Dùng ID cố định trong config thay vì tìm kiếm động.
  Future<void> _initRootFolder() async {
    if (_rootFolderId != null) return;
    if (_driveApi == null) {
      await _initServiceAccount();
    }
    _rootFolderId = DriveConfig.PUBLIC_FOLDER_ID;
    print('✅ Sử dụng thư mục công khai: $_rootFolderId');
  }

  // Khởi tạo Service Account để đọc dữ liệu mà không cần user đăng nhập.
  // Dùng Completer để tránh nhiều nơi gọi đồng thời gây khởi tạo song song.
  Future<void> _initServiceAccount() async {
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    try {
      print('🔐 Đang khởi tạo Service Account...');

      final credentials = auth.ServiceAccountCredentials.fromJson(
        jsonDecode(serviceAccountJson),
      );

      // driveReadonlyScope: chỉ đọc, không ghi — phù hợp cho user thường.
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

  // Lấy Bearer Token của Service Account để dùng trong HTTP request thủ công.
  Future<Map<String, String>> get headers async {
    if (_authClient == null) await _initServiceAccount();
    return {
      'Authorization': 'Bearer ${_authClient!.credentials.accessToken.data}',
    };
  }

  // ── QUẢN LÝ TRUYỆN ─────────────────────────────────────────────────────────

  // Lấy danh sách toàn bộ truyện từ file catalog.json trên Drive.
  // Kết hợp với lượt xem/thích từ Firestore. Có cache và retry tối đa 3 lần.
  Future<List<CloudManga>> getMangas({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedMangas != null) return _cachedMangas!;

    try {
      await _initRootFolder();
      if (_rootFolderId == null) return [];
      if (_driveApi == null) await _initServiceAccount();

      // Tải catalog.json — retry tối đa 3 lần, dừng ngay nếu mất mạng hẳn.
      int retryCount = 0;
      bool success = false;
      List<CloudManga> mangas = [];

      while (retryCount < 3 && !success) {
        try {
          final q =
              "name = '$_catalogFileName' and '$_rootFolderId' in parents and trashed = false";
          final fileList = await _driveApi!.files
              .list(q: q)
              .timeout(const Duration(seconds: 10));

          if (fileList.files != null && fileList.files!.isNotEmpty) {
            final fileId = fileList.files!.first.id!;
            final media =
                await _driveApi!.files.get(
                      fileId,
                      downloadOptions: drive.DownloadOptions.fullMedia,
                    )
                    as drive.Media;

            final List<int> bytes = [];
            await for (final chunk in media.stream.timeout(
              const Duration(seconds: 15),
            )) {
              bytes.addAll(chunk);
            }

            final content = utf8.decode(bytes);
            final List<dynamic> jsonList = jsonDecode(content);
            mangas = jsonList.map((e) => CloudManga.fromMap(e)).toList();
            success = true;
          } else {
            success = true;
          }
        } catch (e) {
          retryCount++;
          print('⚠️ Lỗi tải catalog (Lần $retryCount): $e');

          // Mất mạng hẳn thì không retry vô ích
          if (e.toString().contains('SocketException') ||
              e.toString().contains('Failed host lookup') ||
              e.toString().contains('HandshakeException')) {
            print('🚫 Mất kết nối mạng. Dừng thử lại.');
            break;
          }

          if (retryCount >= 3) rethrow;
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      // Ghép thống kê lượt xem/thích từ Firestore vào danh sách (bỏ qua nếu lỗi).
      try {
        final statsMap = await InteractionService.instance.getAllMangaStats();
        mangas = mangas.map((c) {
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
            );
          }
          return c;
        }).toList();
      } catch (e) {
        print('Lỗi khi tải thống kê trực tuyến: $e');
      }

      _cachedMangas = mangas;
      return _cachedMangas!;
    } catch (e) {
      print('Lỗi khi tải danh sách truyện: $e');
      return [];
    }
  }

  // Thêm bộ truyện mới lên Drive: tạo folder → upload bìa → ghi info.json → cập nhật catalog.json.
  Future<void> addManga({
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
    if (_rootFolderId == null) throw Exception('Không tìm thấy thư mục gốc.');

    // Bước 1: Tạo folder truyện trong thư mục gốc
    final folderMeta = drive.File()
      ..name = title
      ..parents = [_rootFolderId!]
      ..mimeType = 'application/vnd.google-apps.folder';
    final folder = await _driveApi!.files.create(folderMeta);
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
    );

    // Bước 4: Ghi info.json chứa metadata vào folder truyện
    final infoMeta = drive.File()
      ..name = 'info.json'
      ..parents = [folderId];
    final infoContent = jsonEncode(manga.toMap());
    final infoBytes = utf8.encode(infoContent);
    final infoMedia = drive.Media(Stream.value(infoBytes), infoBytes.length);
    await _driveApi!.files.create(infoMeta, uploadMedia: infoMedia);

    // Bước 5: Thêm truyện mới vào catalog.json tổng để user khác thấy ngay
    await _updateCatalog(manga);
  }

  // Cập nhật catalog.json: tải về, thêm/thay thế bản ghi, ghi đè lại lên Drive.
  Future<void> _updateCatalog(CloudManga newManga) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) throw Exception('Chưa đăng nhập Google Drive');
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
      final fileList = await _driveApi!.files.list(q: q);
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
      );
    } else {
      final fileMeta = drive.File()
        ..name = _catalogFileName
        ..parents = [_rootFolderId!];
      await _driveApi!.files.create(fileMeta, uploadMedia: media);
    }
    _cachedMangas = currentList;
  }

  // Xóa folder truyện trên Drive và cập nhật catalog.json.
  Future<void> deleteManga(String mangaId) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) throw Exception('Chưa đăng nhập Google Drive');

    if (_cachedMangas == null) await getMangas();

    // Xóa khỏi cache trước để UI phản hồi nhanh
    _cachedMangas?.removeWhere((m) => m.id == mangaId);

    try {
      try {
        await _driveApi!.files.delete(mangaId);
      } catch (e) {
        print('Warning: Lỗi khi xoá thư mục trên Drive: $e');
        // Vẫn tiếp tục để cập nhật catalog ngay cả khi folder đã mất
      }

      if (_cachedMangas != null) {
        await _saveCatalogToDrive(_cachedMangas!);
      }
      print('✅ Đã xóa Manga $mangaId và cập nhật catalog');
    } catch (e) {
      print('Lỗi quy trình xóa manga: $e');
      rethrow;
    }
  }

  // Quét lại toàn bộ folder để tái tạo catalog.json từ đầu (dùng khi catalog bị lỗi/mất).
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
      // Liệt kê tất cả folder con (mỗi folder = 1 bộ truyện)
      final foldersQuery =
          "mimeType = 'application/vnd.google-apps.folder' and '$_rootFolderId' in parents and trashed = false";
      final folderList = await _driveApi!.files.list(q: foldersQuery);

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
            await for (final chunk in media.stream) bytes.addAll(chunk);
            final content = utf8.decode(bytes);
            mangas.add(CloudManga.fromMap(jsonDecode(content)));
          } else {
            // Không có info.json → tạo bản ghi mặc định để không bị bỏ sót
            print(
              '⚠️ Thiếu info.json cho ${folder.name}, đang tạo file mặc định...',
            );
            final defaultManga = CloudManga(
              id: folder.id!,
              title: folder.name!,
              author: 'Không rõ',
              description: 'Chưa có mô tả.',
              coverFileId: '',
              updatedAt: folder.modifiedTime ?? DateTime.now(),
              genres: [],
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
      print('✅ Đã tái tạo catalog với ${mangas.length} truyện');
    } catch (e) {
      print('Lỗi tái tạo catalog: $e');
      rethrow;
    }
  }

  // Ghi danh sách truyện vào file catalog.json trên Drive (ghi đè nếu đã có).
  Future<void> _saveCatalogToDrive(List<CloudManga> mangas) async {
    final jsonContent = jsonEncode(mangas.map((e) => e.toMap()).toList());

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
  }) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) {
      throw Exception(
        'Không thể kết nối đến Google Drive. Vui lòng đăng nhập.',
      );
    }

    final currentMangas = await getMangas();
    final currentManga = currentMangas.firstWhere((c) => c.id == mangaId);
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
        await _driveApi!.files.delete(currentManga.coverFileId);
      } catch (e) {
        print('Lỗi khi xoá ảnh bìa cũ: $e');
      }

      final coverResult = await _driveApi!.files.create(
        coverMeta,
        uploadMedia: coverMedia,
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
    );

    // Cập nhật info.json trong folder truyện
    try {
      final infoQuery =
          "name = 'info.json' and '$mangaId' in parents and trashed = false";
      final infoFiles = await _driveApi!.files.list(q: infoQuery);
      final infoContent = jsonEncode(updatedManga.toMap());
      final infoBytes = utf8.encode(infoContent);
      final infoMedia = drive.Media(Stream.value(infoBytes), infoBytes.length);

      if (infoFiles.files != null && infoFiles.files!.isNotEmpty) {
        await _driveApi!.files.update(
          drive.File(),
          infoFiles.files!.first.id!,
          uploadMedia: infoMedia,
        );
      } else {
        final infoMeta = drive.File()
          ..name = 'info.json'
          ..parents = [mangaId];
        await _driveApi!.files.create(infoMeta, uploadMedia: infoMedia);
      }
    } catch (e) {
      print('Cảnh báo khi cập nhật info.json: $e');
    }

    await _updateCatalog(updatedManga);

    // Gửi thông báo nếu trạng thái truyện thay đổi
    if (currentManga.status != status) {
      String msg =
          'Truyện "${currentManga.title}" đã chuyển sang trạng thái $status';
      if (status.toLowerCase().contains('hoàn thành')) {
        msg =
            'Truyện "${currentManga.title}" đã Hoàn Thành. Mời bạn vào đọc trọn bộ!';
      } else if (status.toLowerCase().contains('ngừng') ||
          status.toLowerCase().contains('drop')) {
        msg = 'Truyện "${currentManga.title}" đã bị tạm ngưng.';
      }
      await NotificationService.instance.notifySubscribers(
        mangaId: mangaId,
        title: 'Cập nhật trạng thái',
        body: msg,
      );
    }
  }

  // ── QUẢN LÝ CHAPTER ────────────────────────────────────────────────────────

  // Lấy danh sách chapter của một truyện từ Drive (loại bỏ info.json và cover).
  // Ghép thêm lượt xem từ Firestore, rồi sắp xếp bằng ChapterSortHelper.
  Future<List<CloudChapter>> getChapters(String mangaId) async {
    try {
      if (_driveApi == null) await _initServiceAccount();

      final q =
          "'$mangaId' in parents and trashed = false and name != 'info.json' and not name contains 'cover.'";

      final fileList = await _driveApi!.files
          .list(
            q: q,
            $fields: 'files(id,name,mimeType,size,createdTime)',
            pageSize: 1000,
          )
          .timeout(const Duration(seconds: 10));

      final allFiles = fileList.files ?? [];

      // Lấy lượt xem chapter từ Firestore (bỏ qua nếu lỗi)
      Map<String, int> statsMap = {};
      try {
        statsMap = await InteractionService.instance
            .getChapterViews(mangaId)
            .timeout(const Duration(seconds: 5));
      } catch (_) {}

      final files = allFiles.map((f) {
        // Xác định định dạng file từ đuôi mở rộng
        String type = 'zip';
        if (f.name != null) {
          if (f.name!.endsWith('.epub')) type = 'epub';
          if (f.name!.endsWith('.cbz')) type = 'cbz';
          if (f.name!.endsWith('.pdf')) type = 'pdf';
        }

        return CloudChapter(
          id: f.id!,
          title: f.name ?? 'Không rõ',
          fileId: f.id!,
          fileType: type,
          sizeBytes: int.tryParse(f.size ?? '0') ?? 0,
          uploadedAt: f.createdTime ?? DateTime.now(),
          viewCount: statsMap[f.id] ?? 0,
        );
      }).toList();

      return ChapterSortHelper.sort(files);
    } catch (e) {
      print('Lỗi lấy danh sách chapter: $e');
      // Rethrow lỗi mạng để UI biết mà chuyển sang chế độ offline
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('TimeoutException')) {
        rethrow;
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
    if (_driveApi == null) await signIn();
    if (_driveApi == null) {
      throw Exception(
        'Không thể kết nối đến Google Drive. Vui lòng đăng nhập.',
      );
    }

    // Làm sạch tên file trước khi upload (bỏ ký tự đặc biệt)
    final safeTitle = title.replaceAll(RegExp(r'[^a-zA-Z0-9\s\-]'), '').trim();
    final ext = path.extension(file.path);
    final fileName = '$safeTitle$ext';

    final fileMeta = drive.File()
      ..name = fileName
      ..parents = [mangaId];

    final media = drive.Media(file.openRead(), file.lengthSync());
    await _driveApi!.files.create(fileMeta, uploadMedia: media);

    await NotificationService.instance.notifySubscribers(
      mangaId: mangaId,
      title: 'Chương mới!',
      body: 'Chương "$title" vừa được cập nhật. Đọc ngay!',
    );
  }

  // Xóa một chapter khỏi Drive theo fileId.
  Future<void> deleteChapter(String chapterId) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) {
      throw Exception(
        'Không thể kết nối đến Google Drive. Vui lòng đăng nhập.',
      );
    }
    await _driveApi!.files.delete(chapterId);
  }

  // Cập nhật thứ tự chapter mới (Admin kéo thả để sắp xếp lại).
  // Cập nhật RAM cache trước để UI phản hồi ngay, rồi ghi info.json và catalog.json.
  Future<void> saveChapterOrder(String mangaId, List<String> newOrder) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) return;

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
    );

    // Cập nhật cache RAM trước để UI không thấy lag
    currentMangas[index] = updatedManga;
    _cachedMangas = currentMangas;

    // Ghi info.json cập nhật thứ tự chương
    try {
      final infoQuery =
          "name = 'info.json' and '$mangaId' in parents and trashed = false";
      final infoFiles = await _driveApi!.files.list(q: infoQuery);
      final infoContent = jsonEncode(updatedManga.toMap());
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
          ..parents = [mangaId];
        await _driveApi!.files.create(infoMeta, uploadMedia: media);
      }
    } catch (e) {
      print('Warning save order info.json: $e');
    }

    await _updateCatalog(updatedManga);
  }

  // ── TIỆN ÍCH ───────────────────────────────────────────────────────────────

  // Tạo URL thumbnail public của ảnh trên Drive (dùng API key tĩnh).
  String getThumbnailLink(String fileId) {
    return 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media&key=${DriveConfig.API_KEY}';
  }

  // Lấy thông tin cơ bản của file Drive (id, name, parents).
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
      print('⚡ Lấy từ Cache: $fileId');
      if (onProgress != null) onProgress(100, 100);
      return _fileCache[fileId];
    }

    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        if (retryCount > 0) {
          print('🔄 Retry download ($retryCount/$maxRetries): $fileId');
        } else {
          print('📥 Đang tải file (Service Account): $fileId');
        }

        if (_driveApi == null) await _initServiceAccount();

        final media =
            await _driveApi!.files.get(
                  fileId,
                  downloadOptions: drive.DownloadOptions.fullMedia,
                )
                as drive.Media;

        final List<int> bytes = [];
        int received = 0;
        final total = media.length ?? 0;

        // Đọc file theo từng chunk, gọi callback tiến độ sau mỗi chunk
        await for (final chunk in media.stream) {
          bytes.addAll(chunk);
          received += chunk.length;
          if (onProgress != null && total > 0) {
            onProgress(received, total);
          }
        }

        final result = Uint8List.fromList(bytes);

        // Lưu vào cache và xóa bớt nếu đã đầy
        _fileCache[fileId] = result;
        _fileCacheOrder.add(fileId);
        _trimFileCache();

        return result;
      } catch (e) {
        print('⚠️ Lỗi tải file (Attempt ${retryCount + 1}): $e');
        retryCount++;

        // Không retry nếu file không tồn tại trên Drive
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('not found') || errorStr.contains('404')) {
          print('❌ File not found on Drive, stopping retries.');
          return null;
        }

        if (retryCount >= maxRetries) {
          print('❌ Download failed ultimately after $maxRetries attempts.');
          return null;
        }

        // Exponential backoff: lần 1 chờ 1s, lần 2 chờ 2s, lần 3 chờ 3s
        await Future.delayed(Duration(seconds: retryCount));
      }
    }
    return null;
  }
}
