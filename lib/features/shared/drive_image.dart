import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import '../../data/drive_service.dart';

class DriveImage extends StatelessWidget {
  final String fileId;
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
    // Check if it's a local file path
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

    return FutureBuilder<Map<String, String>>(
      future: DriveService.instance.headers,
      builder: (context, snapshot) {
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
          httpHeaders: snapshot.data,
          width: width,
          height: height,
          fit: fit,
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
