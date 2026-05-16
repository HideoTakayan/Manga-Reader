import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

// PermissionService: xử lý quyền ghi thư mục MangaReader công khai.
class PermissionService {
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Yêu cầu quyền Manage External Storage trước (dành cho Android 11+)
    // Nếu thiết bị Android < 11, quyền này tự động trả về denied/permanentlyDenied
    var manageStatus = await Permission.manageExternalStorage.request();
    if (manageStatus.isGranted) return true;

    // Fallback cho Android 10 trở xuống
    var storageStatus = await Permission.storage.request();
    return storageStatus.isGranted;
  }

  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;

    if (await Permission.manageExternalStorage.isGranted) return true;
    
    return await Permission.storage.isGranted;
  }
}
