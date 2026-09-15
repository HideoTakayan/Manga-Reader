import 'dart:io';
import 'dart:convert';
import 'dart:isolate';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import '../../../config/cloudinary_config.dart';

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
  static Future<String> uploadChatImage(
    File imageFile,
    String uid,
  ) async {
    return _uploadImage(
      imageFile: imageFile,
      folder: 'manga_reader/chats',
      publicIdPrefix: 'chat_$uid',
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
    final fileSize = await imageFile.length();
    if (fileSize > 20 * 1024 * 1024) {
      throw Exception('File ảnh quá lớn (trên 20MB). Vui lòng chọn ảnh nhỏ hơn.');
    }

    final bytes = await imageFile.readAsBytes();
    final isGif = _isGifBytes(bytes);

    late List<int> uploadBytes;
    late String filename;
    late String contentType;

    if (isGif) {
      // GIF: bỏ qua bước decode/encode để giữ nguyên animation
      uploadBytes = bytes;
      filename = 'upload.gif';
      contentType = 'image/gif';
    } else {
      // Ảnh tĩnh: nén và resize trên Isolate để không block UI
      uploadBytes = await Isolate.run(() {
        final decodedImage = img.decodeImage(bytes);
        if (decodedImage == null) {
          throw Exception('Lỗi xử lý ảnh: Không thể đọc được file ảnh này.');
        }

        var processedImage = decodedImage;
        if (processedImage.width > maxWidth) {
          processedImage = img.copyResize(processedImage, width: maxWidth);
        }

        return img.encodeJpg(processedImage, quality: 70);
      });

      if (uploadBytes.length > maxSizeLimit) {
        throw Exception('Ảnh quá lớn sau khi nén, vui lòng chọn ảnh có độ phân giải thấp hơn.');
      }

      filename = 'upload.jpg';
      contentType = 'image/jpeg';
    }

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
          uploadBytes,
          filename: filename,
          contentType: MediaType.parse(contentType),
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

  /// Kiểm tra magic bytes của GIF: GIF87a hoặc GIF89a
  static bool _isGifBytes(List<int> bytes) {
    if (bytes.length < 6) return false;
    // GIF magic: 47 49 46 38 (GIF8)
    return bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38;
  }
}
