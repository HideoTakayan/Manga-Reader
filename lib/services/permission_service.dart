import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

/// Service quản lý permissions
class PermissionService {
  /// Request storage permission
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Android 11+ (API 30+) dùng MANAGE_EXTERNAL_STORAGE
    // Note: Cần check SDK version chính xác, ở đây ta thử request luôn
    if (await Permission.manageExternalStorage.status.isGranted) {
      return true;
    }

    // Thử request Manage External Storage
    // Sẽ hiện màn hình setting cho user bật "Allow access to manage all files"
    if (await Permission.manageExternalStorage.request().isGranted) {
      return true;
    }

    // Android 13+ (API 33+) images/video
    if (await _isAndroid13OrHigher()) {
      final status = await Permission.photos.request();
      return status.isGranted;
    }

    // Android 10- (API 29-)
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  /// Check if storage permission is granted
  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;

    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }

    if (await _isAndroid13OrHigher()) {
      return await Permission.photos.isGranted;
    }

    return await Permission.storage.isGranted;
  }

  /// Check if Android 13+
  static Future<bool> _isAndroid13OrHigher() async {
    // Simplified check - in production, use device_info_plus
    return false; // Default to false for now
  }
}
