import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import '../../data/drive_service.dart';

// Widget hiển thị ảnh từ Google Drive (ảnh bìa truyện).
// Tự động phân biệt: nếu fileId là đường dẫn file cục bộ thì đọc từ máy,
// còn lại thì fetch qua Drive API với auth header của Service Account.
class DriveImage extends StatelessWidget {
  final String fileId; // ID file trên Drive, hoặc đường dẫn tuyệt đối trên máy
  final double? width;
  final double? height;
  final BoxFit fit;

  const DriveImage({
    super.key,
    required this.fileId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    // Nếu fileId là đường dẫn file cục bộ (bắt đầu bằng '/' hoặc chứa path separator),
    // đọc thẳng từ ổ cứng bằng Image.file — không cần mạng.
    if (fileId.startsWith('/') || fileId.contains(Platform.pathSeparator)) {
      final file = File(fileId);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: width,
              height: height,
              color: Colors.grey[800],
              child: const Icon(Icons.broken_image, color: Colors.grey),
            );
          },
        );
      }
    }

    // Nếu là file trên Drive: lấy Bearer token từ Service Account trước,
    // rồi dùng CachedNetworkImage fetch ảnh kèm header đó.
    // CachedNetworkImage tự cache ảnh vào bộ nhớ/disk, tránh tải lại mỗi lần scroll.
    return FutureBuilder<Map<String, String>>(
      future: DriveService.instance.headers, // Lấy auth header bất đồng bộ
      builder: (context, snapshot) {
        // Chưa có header thì hiện loading placeholder
        if (!snapshot.hasData) {
          return Container(
            width: width,
            height: height,
            color: Colors.grey[800],
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        return CachedNetworkImage(
          imageUrl:
              'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
          httpHeaders: snapshot.data, // Bearer token để Drive cho phép truy cập
          width: width,
          height: height,
          fit: fit,
          // Giới hạn kích thước cache trong RAM bằng 2x kích thước hiển thị
          // để tránh lưu ảnh quá lớn khi chỉ cần hiển thị nhỏ (VD: thumbnail)
          memCacheWidth: (width != null && width!.isFinite)
              ? (width! * 2).toInt()
              : null,
          placeholder: (context, url) => Container(
            width: width,
            height: height,
            color: Colors.grey[800],
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (context, url, error) {
            return Container(
              width: width,
              height: height,
              color: Colors.grey[800],
              child: const Icon(Icons.broken_image, color: Colors.grey),
            );
          },
        );
      },
    );
  }
}
