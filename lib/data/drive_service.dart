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

  // Stream to notify auth changes
  final _authController = StreamController<GoogleSignInAccount?>.broadcast();
  Stream<GoogleSignInAccount?> get onAuthStateChanged => _authController.stream;
  GoogleSignInAccount? get currentUser => _currentUser;

  // 🎯 Folder "MangaReader" cố định theo yêu cầu của bạn
  // https://drive.google.com/drive/folders/1hw9znxf4iqqsOWJwSgMl4Q_OcgCfDytL
  String? _rootFolderId = '1hw9znxf4iqqsOWJwSgMl4Q_OcgCfDytL';

  static const String _catalogFileName = 'catalog.json';

  // 1. Auth Methods
  Future<GoogleSignInAccount?> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      await _initializeDriveApi();
      _authController.add(_currentUser);
      return _currentUser;
    } catch (e) {
      print('Google Sign In Error: $e');
      return null;
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
    _authController.add(null);
  }

  Future<Map<String, String>> getHeaders() async {
    final headers = await _currentUser?.authHeaders;
    return headers ?? {};
  }

  // 2. Initialization (Optional check)
  Future<void> _initRootFolder() async {
    // Đã dùng ID cứng, hàm này chỉ để tương thích hoặc check nêus cần
    if (_driveApi != null && _rootFolderId != null) {
      try {
        await _driveApi!.files.get(_rootFolderId!);
        print('✅ Connected to target Drive folder');
      } catch (e) {
        print('⚠️ Cannot access target folder. Check permissions: $e');
      }
    }
  }

  // 3. Comic Management
  Future<List<CloudComic>> getComics() async {
    if (_driveApi == null) await restorePreviousSession();
    if (_driveApi == null || _rootFolderId == null) return [];
    try {
      // Find catalog.json
      final q =
          "name = '$_catalogFileName' and '$_rootFolderId' in parents and trashed = false";
      final fileList = await _driveApi!.files.list(q: q);

      if (fileList.files == null || fileList.files!.isEmpty) {
        return [];
      }

      final fileId = fileList.files!.first.id!;
      final media =
          await _driveApi!.files.get(
                fileId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      final content = await utf8.decodeStream(media.stream);
      final List<dynamic> jsonList = jsonDecode(content);

      return jsonList.map((e) => CloudComic.fromMap(e)).toList();
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
  }) async {
    if (_driveApi == null) await signIn();
    if (_rootFolderId == null) await _initRootFolder();

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
    );

    // 4. Save info.json inside folder
    final infoMeta = drive.File()
      ..name = 'info.json'
      ..parents = [folderId];

    final infoContent = jsonEncode(comic.toMap());
    final infoMedia = drive.Media(
      Stream.value(utf8.encode(infoContent)),
      infoContent.length,
    );
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

    final media = drive.Media(
      Stream.value(utf8.encode(jsonContent)),
      jsonContent.length,
    );

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

  // 4. Chapter Management
  Future<List<CloudChapter>> getChapters(String comicId) async {
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

      return allFiles.map((f) {
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

  // 5. Image & Content Helper
  String getThumbnailLink(String fileId) {
    // Note: This requires the file to be public or use a token in headers
    // Using simple approach: We will use a widget that attaches auth headers
    return 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media';
  }

  // Get File Metadata (e.g. parents)
  Future<drive.File?> getFile(String fileId) async {
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
