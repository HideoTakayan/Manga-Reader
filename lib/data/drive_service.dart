// This was intended for ReaderProvider but I'm switching to DriveService first.
// Please ignore this or empty it, but I must provide valid arguments.
// Actually I will just update DriveService here.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:path/path.dart' as path;
import 'models_cloud.dart';

class DriveService {
  static final DriveService instance = DriveService._internal();
  DriveService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveScope],
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  List<CloudComic>? _cachedComics; // Cache for comics list

  // Stream to notify auth changes
  final _authController = StreamController<GoogleSignInAccount?>.broadcast();
  Stream<GoogleSignInAccount?> get onAuthStateChanged => _authController.stream;
  GoogleSignInAccount? get currentUser => _currentUser;

  // 🎯 Folder "MangaReader_Data" dynamic
  String? _rootFolderId;
  static const String _rootFolderName = 'MangaReader_Data';
  static const String _catalogFileName = 'catalog.json';

  // 1. Auth Methods
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
      rethrow; // Throw the error so caller can handle it
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
      // If restore fails, we should treat as signed out
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

  // 2. Initialization & Root Folder
  Future<void> _initRootFolder() async {
    if (_driveApi == null) return;
    if (_rootFolderId != null) return; // Already initialized

    try {
      // Search for folder
      final q =
          "name = '$_rootFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
      final fileList = await _driveApi!.files.list(q: q);

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        _rootFolderId = fileList.files!.first.id;
        print('✅ Found existing root folder: $_rootFolderId');
      } else {
        // Create folder
        final folderMeta = drive.File()
          ..name = _rootFolderName
          ..mimeType = 'application/vnd.google-apps.folder';
        final folder = await _driveApi!.files.create(folderMeta);
        _rootFolderId = folder.id;
        print('✅ Created new root folder: $_rootFolderId');
      }
    } catch (e) {
      print('⚠️ Error initializing root folder: $e');
      throw Exception('Không thể khởi tạo thư mục lưu trữ trên Drive.');
    }
  }

  // 3. Comic Management
  Future<List<CloudComic>> getComics({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedComics != null) return _cachedComics!;

    if (_driveApi == null) await restorePreviousSession();
    if (_driveApi == null) return [];

    try {
      await _initRootFolder();
      if (_rootFolderId == null) return [];

      // Find catalog.json
      final q =
          "name = '$_catalogFileName' and '$_rootFolderId' in parents and trashed = false";
      final fileList = await _driveApi!.files.list(q: q);

      if (fileList.files == null || fileList.files!.isEmpty) {
        _cachedComics = [];
        return [];
      }

      final fileId = fileList.files!.first.id!;
      final media =
          await _driveApi!.files.get(
                fileId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      // Read stream
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

      // If error contains "Content size" or similar, rebuild catalog
      if (e.toString().contains('Content size') ||
          e.toString().contains('ClientException')) {
        print('🔄 Detected corrupted catalog, rebuilding...');
        try {
          await rebuildCatalog();
          return _cachedComics ?? [];
        } catch (rebuildError) {
          print('Error rebuilding catalog: $rebuildError');
          return [];
        }
      }
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

    // 1. Create Comic Folder
    final folderMeta = drive.File()
      ..name = title
      ..parents = [_rootFolderId!]
      ..mimeType = 'application/vnd.google-apps.folder';

    final folder = await _driveApi!.files.create(folderMeta);
    final folderId = folder.id!;

    // 2. Upload Cover
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

    // 3. Create CloudComic Object
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

    // 4. Save info.json inside folder
    final infoMeta = drive.File()
      ..name = 'info.json'
      ..parents = [folderId];

    final infoContent = jsonEncode(comic.toMap());
    final infoBytes = utf8.encode(infoContent);
    final infoMedia = drive.Media(Stream.value(infoBytes), infoBytes.length);
    await _driveApi!.files.create(infoMeta, uploadMedia: infoMedia);

    // 5. Update catalog.json
    await _updateCatalog(comic);
  }

  Future<void> _updateCatalog(CloudComic newComic) async {
    List<CloudComic> currentList = await getComics();
    // Remove if exists (update)
    currentList.removeWhere((c) => c.id == newComic.id);
    currentList.insert(0, newComic); // Add to top

    final jsonContent = jsonEncode(currentList.map((e) => e.toMap()).toList());

    // Find catalog.json to overwrite or create new
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
    // Update Cache
    _cachedComics = currentList;
  }

  Future<void> deleteComic(String comicId) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) throw Exception('Chưa đăng nhập Google Drive');

    // 1. Delete folder on Drive
    try {
      await _driveApi!.files.delete(comicId);
    } catch (e) {
      print('Error deleting folder: $e');
      // Even if delete fails (e.g. not found), we should remove from catalog
    }

    // 2. Remove from catalog
    List<CloudComic> currentList = await getComics();
    currentList.removeWhere((c) => c.id == comicId);

    // 3. Save catalog
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

  /// Scan all folders in MangaReader_Data and rebuild catalog.json
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
      // 1. Get all folders in MangaReader_Data
      final foldersQuery =
          "mimeType = 'application/vnd.google-apps.folder' and '$_rootFolderId' in parents and trashed = false";
      final folderList = await _driveApi!.files.list(q: foldersQuery);

      if (folderList.files == null || folderList.files!.isEmpty) {
        // No folders, create empty catalog
        _cachedComics = [];
        await _saveCatalogToDrive([]);
        return;
      }

      // 2. For each folder, try to read info.json
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

            // Read stream without relying on contentLength
            final List<int> bytes = [];
            await for (final chunk in media.stream) {
              bytes.addAll(chunk);
            }
            final content = utf8.decode(bytes);
            final Map<String, dynamic> comicMap = jsonDecode(content);
            comics.add(CloudComic.fromMap(comicMap));
          } else {
            // No info.json? Create a default one!
            print('⚠️ No info.json for ${folder.name}, creating default...');
            final defaultComic = CloudComic(
              id: folder.id!,
              title: folder.name!,
              author: 'Unknown',
              description: 'No description available.',
              coverFileId: '', // Ideally find an image file, but empty for now
              updatedAt: folder.modifiedTime ?? DateTime.now(),
              genres: [],
              status: 'Unknown',
            );

            // Upload the default info.json
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
          // Skip this folder if info.json is invalid
        }
      }

      // 3. Sort by updatedAt (newest first)
      comics.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      // 4. Save to catalog.json
      await _saveCatalogToDrive(comics);

      // 5. Update cache
      _cachedComics = comics;

      print('✅ Rebuilt catalog with ${comics.length} comics');
    } catch (e) {
      print('Error rebuilding catalog: $e');
      rethrow;
    }
  }

  Future<void> _saveCatalogToDrive(List<CloudComic> comics) async {
    final jsonContent = jsonEncode(comics.map((e) => e.toMap()).toList());

    // Find catalog.json to overwrite or create new
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

    // 1. Get current comic info
    final currentComics = await getComics();
    final currentComic = currentComics.firstWhere((c) => c.id == comicId);

    String coverFileId = currentComic.coverFileId;

    // 2. If new cover provided, upload it
    if (newCoverFile != null) {
      final coverMeta = drive.File()
        ..name = 'cover.${path.extension(newCoverFile.path)}'
        ..parents = [comicId];

      final coverMedia = drive.Media(
        newCoverFile.openRead(),
        newCoverFile.lengthSync(),
      );

      // Delete old cover
      try {
        await _driveApi!.files.delete(currentComic.coverFileId);
      } catch (e) {
        print('Error deleting old cover: $e');
      }

      // Upload new cover
      final coverResult = await _driveApi!.files.create(
        coverMeta,
        uploadMedia: coverMedia,
      );
      coverFileId = coverResult.id!;
    }

    // 3. Create updated CloudComic object
    final updatedComic = CloudComic(
      id: comicId,
      title: title,
      author: author,
      description: description,
      coverFileId: coverFileId,
      updatedAt: DateTime.now(),
      genres: genres,
      status: status,
      viewCount: currentComic.viewCount, // Preserve existing
      likeCount: currentComic.likeCount, // Preserve existing
      chapterOrder: currentComic.chapterOrder, // Preserve existing
    );

    // 4. Update info.json in comic folder
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

    // 5. Update catalog.json
    await _updateCatalog(updatedComic);
  }

  // 4. Chapter Management
  Future<List<CloudChapter>> getChapters(String comicId) async {
    if (_driveApi == null) await restorePreviousSession();
    if (_driveApi == null) return [];
    try {
      // List all files in comic folder that are NOT info.json or cover
      final q =
          "'$comicId' in parents and trashed = false and name != 'info.json' and not name contains 'cover.'";

      final List<drive.File> allFiles = [];
      String? pageToken;

      do {
        final fileList = await _driveApi!.files.list(
          q: q,
          $fields:
              'nextPageToken, files(id, name, mimeType, size, createdTime)',
          pageToken: pageToken,
          pageSize: 1000,
        );

        if (fileList.files != null) {
          allFiles.addAll(fileList.files!);
        }
        pageToken = fileList.nextPageToken;
      } while (pageToken != null);

      final files = allFiles.map((f) {
        String type = 'zip';
        if (f.name!.endsWith('.epub')) type = 'epub';
        if (f.name!.endsWith('.cbz')) type = 'cbz';

        return CloudChapter(
          id: f.id!,
          title: f.name!, // Simplification: File name is title
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
          // If both have order, compare index
          if (orderMap.containsKey(a.id) && orderMap.containsKey(b.id)) {
            return orderMap[a.id]!.compareTo(orderMap[b.id]!);
          }
          // If only a has order, it comes first (or last?) -> Let's put unordered at top or bottom
          // Usually unordered = new. Newest should be at top?
          // If we are Manually Ordering, specific order takes precedence. Unordered ... ?
          // Let's put unordered files at the END.
          if (orderMap.containsKey(a.id)) return -1;
          if (orderMap.containsKey(b.id)) return 1;

          // Both unordered -> Sort by Name
          return b.title.compareTo(a.title);
        });
      } else {
        // Default sort by Name (Chap 10, Chap 9...)
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

    // We normally don't need to update catalog for chapter changes in this simple design,
    // unless we want to show "Latest Chapter" in the list.
    // For now, let's just upload.
  }

  Future<void> deleteChapter(String chapterId) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) {
      throw Exception(
        'Không thể kết nối đến Google Drive. Vui lòng đăng nhập.',
      );
    }

    // Move file to trash
    await _driveApi!.files.delete(chapterId);
    // Move file to trash
    await _driveApi!.files.delete(chapterId);
  }

  Future<void> saveChapterOrder(String comicId, List<String> newOrder) async {
    if (_driveApi == null) await signIn();
    if (_driveApi == null) return;

    // 1. Get current comic info to update object
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

    // 2. Update info.json
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

    // 3. Update Catalog (Cache & Drive)
    await _updateCatalog(updatedComic);
  }

  // 5. Image & Content Helper
  String getThumbnailLink(String fileId) {
    // Note: This requires the file to be public or use a token in headers
    // Using simple approach: We will use a widget that attaches auth headers
    return 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media';
  }

  // Get File Metadata (e.g. parents)
  Future<drive.File?> getFile(String fileId) async {
    if (_driveApi == null) await restorePreviousSession();
    if (_driveApi == null) await signIn();
    try {
      return await _driveApi!.files.get(fileId, $fields: 'id, name, parents')
          as drive.File;
    } catch (e) {
      print('Error getting file: $e');
      return null;
    }
  }

  // Download file content as bytes
  Future<Uint8List?> downloadFile(String fileId) async {
    if (_driveApi == null) await restorePreviousSession();
    if (_driveApi == null) await signIn();
    try {
      final media =
          await _driveApi!.files.get(
                fileId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      final List<int> dataStore = [];
      await for (final data in media.stream) {
        dataStore.addAll(data);
      }
      return Uint8List.fromList(dataStore);
    } catch (e) {
      print('Error downloading file: $e');
      return null;
    }
  }
}
