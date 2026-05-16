import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import '../../data/drive_service.dart';

// Widget hiển thị ảnh từ Google Drive (ảnh bìa truyện).
// Tự động phân biệt: nếu fileId là đường dẫn file cục bộ thì đọc từ máy,
// còn lại thì fetch qua Drive API public bằng API key.
class DriveImage extends StatefulWidget {
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
  State<DriveImage> createState() => _DriveImageState();
}

class _DriveImageState extends State<DriveImage> {
  int _retryKey = 0; // Thay đổi key để ép CachedNetworkImage render lại

  @override
  Widget build(BuildContext context) {
    if (widget.fileId.startsWith('/') ||
        widget.fileId.contains(Platform.pathSeparator)) {
      final file = File(widget.fileId);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (context, error, stackTrace) {
            return _buildErrorWidget();
          },
        );
      }
    }

    if (widget.fileId.isEmpty) {
      return _buildErrorWidget();
    }

    return CachedNetworkImage(
      key: ValueKey(_retryKey),
      imageUrl: DriveService.instance.mediaUrl(widget.fileId),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      memCacheWidth: (widget.width != null && widget.width!.isFinite)
          ? (widget.width! * 2).toInt()
          : null,
      placeholder: (context, url) => Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey[800],
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white24),
        ),
      ),
      errorWidget: (context, url, error) {
        debugPrint('DriveImage Error [$url]: $error');
        return _buildErrorWidget();
      },
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[900],
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _retryKey++),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.refresh, 
                    color: Colors.grey, 
                    size: constraints.maxHeight < 40 ? 16 : 28,
                  ),
                  if (constraints.maxHeight >= 50) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Lỗi tải ảnh',
                      style: TextStyle(color: Colors.grey, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ]
                ],
              );
            }
          ),
        ),
      ),
    );
  }
}
