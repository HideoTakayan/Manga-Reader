import 'package:flutter/material.dart';
import '../../data/drive_service.dart';

class DriveImage extends StatelessWidget {
  final String fileId;
  final double? width;
  final double? height;
  final BoxFit fit;

  const DriveImage({
    Key? key,
    required this.fileId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: DriveService.instance.getHeaders(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            width: width,
            height: height,
            color: Colors.grey[300],
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        return Image.network(
          'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
          headers: snapshot.data,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: width,
              height: height,
              color: Colors.grey,
              child: const Icon(Icons.broken_image),
            );
          },
        );
      },
    );
  }
}
