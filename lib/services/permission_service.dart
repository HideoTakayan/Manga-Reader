import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

// PermissionService: xử lý storage permission cho các phiên bản Android khác nhau.
// Android chia làm 3 nhóm API:
class PermissionService {
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid)
      return true; 

    if (await Permission.manageExternalStorage.status.isGranted) return true;

    if (await Permission.manageExternalStorage.request().isGranted) return true;

    if (await _isAndroid13OrHigher()) {
      final status = await Permission.photos.request();
      return status.isGranted;
    }

    final status = await Permission.storage.request();
    return status.isGranted;
  }

  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await _isAndroid13OrHigher()) return await Permission.photos.isGranted;
    return await Permission.storage.isGranted;
  }

  static Future<bool> _isAndroid13OrHigher() async {
    return false;
  }
}
