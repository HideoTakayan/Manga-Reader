import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../../../config/cloudinary_config.dart';

import 'dart:isolate';

class ImageUploadService {
  static Future<String> uploadForumImage(
    File imageFile,
    String uid,
    String postId,
  ) async {
    return _uploadImage(
      imageFile: imageFile,
      folder: CloudinaryConfig.folder,
      publicIdPrefix: 'post_${postId}_$uid',
      maxSizeLimit: 3 * 1024 * 1024, // 3MB
      maxWidth: 1200,
    );
  }

  static Future<String> uploadAvatarImage(File imageFile, String uid) async {
    return _uploadImage(
      imageFile: imageFile,
      folder: 'manga_reader/avatars',
      publicIdPrefix: 'avatar_$uid',
      maxSizeLimit: 5 * 1024 * 1024, // 5MB
      maxWidth: 800,
    );
  }

  static Future<String> _uploadImage({
    required File imageFile,
    required String folder,
    required String publicIdPrefix,
    required int maxSizeLimit,
    required int maxWidth,
  }) async {
    // Guard file: Kiểm tra kích thước file gốc trước khi đưa vào bộ nhớ/isolate để chống OOM
    final fileSize = await imageFile.length();
    if (fileSize > 20 * 1024 * 1024) {
      // 20MB hard limit cho file gốc
      throw Exception(
        'File ảnh quá lớn (trên 20MB). Vui lòng chọn ảnh nhỏ hơn.',
      );
    }

    // Đọc bytes ở luồng chính, truyền vào isolate để tránh lỗi khi pass object File
    final bytes = await imageFile.readAsBytes();

    // Nén và resize ảnh trên luồng nền (Isolate) để không block UI
    final compressedBytes = await Isolate.run(() {
      final decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) {
        throw Exception('Lỗi xử lý ảnh: Không thể đọc được file ảnh này.');
      }

      var processedImage = decodedImage;
      // Chỉ thu nhỏ ảnh nếu chiều rộng lớn hơn maxWidth, không upscale ảnh nhỏ
      if (processedImage.width > maxWidth) {
        processedImage = img.copyResize(processedImage, width: maxWidth);
      }

      return img.encodeJpg(processedImage, quality: 70);
    });

    if (compressedBytes.length > maxSizeLimit) {
      throw Exception(
        'Ảnh quá lớn sau khi nén, vui lòng chọn ảnh có độ phân giải thấp hơn hoặc kích thước nhỏ hơn.',
      );
    }

    // Prepare HTTP request
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudName}/image/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = CloudinaryConfig.uploadPreset
      ..fields['folder'] = folder
      ..fields['public_id'] =
          '${publicIdPrefix}_${DateTime.now().millisecondsSinceEpoch}'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          compressedBytes,
          filename: 'upload.jpg',
        ),
      );

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 30),
    );
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final jsonResponse = jsonDecode(response.body);
      return jsonResponse['secure_url'] as String;
    } else {
      String errorMessage = 'Lỗi upload ảnh: ${response.statusCode}';
      try {
        final errorData = jsonDecode(response.body);
        if (errorData['error'] != null &&
            errorData['error']['message'] != null) {
          errorMessage = 'Lỗi Cloudinary: ${errorData['error']['message']}';
        }
      } catch (_) {}

      throw Exception(errorMessage);
    }
  }
}
