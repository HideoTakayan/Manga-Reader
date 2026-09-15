import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../config/tenor_config.dart';

class TenorService {
  Future<List<String>> getTrendingGifs() async {
    try {
      // Tenor API v2 (v1 was deprecated and shut down)
      final uri = Uri.https('tenor.googleapis.com', '/v2/featured', {
        'key': TenorConfig.apiKey,
        'limit': '24',
        'media_filter': 'tinygif',
        'contentfilter': 'medium',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return _parseGifsV2(response.body);
      } else {
        throw Exception('Tenor trending failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Lỗi tải danh sách GIF: $e');
    }
  }

  Future<List<String>> searchGifs(String query) async {
    try {
      // Tenor API v2
      final uri = Uri.https('tenor.googleapis.com', '/v2/search', {
        'q': query,
        'key': TenorConfig.apiKey,
        'limit': '24',
        'media_filter': 'tinygif',
        'contentfilter': 'medium',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return _parseGifsV2(response.body);
      } else {
        throw Exception('Tenor search failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Lỗi tìm kiếm GIF: $e');
    }
  }

  // Tenor v2 API: results[].media_formats.tinygif.url
  List<String> _parseGifsV2(String responseBody) {
    final data = jsonDecode(responseBody);
    final results = data['results'] as List? ?? [];

    final urls = <String>[];
    for (final gif in results) {
      try {
        final formats = gif['media_formats'] as Map<String, dynamic>?;
        if (formats != null) {
          // Ưu tiên tinygif (nhỏ hơn), fallback gif
          final url = formats['tinygif']?['url'] ?? formats['gif']?['url'];
          if (url != null) {
            urls.add(url as String);
          }
        }
      } catch (_) {
        // Skip malformed item
      }
    }
    return urls;
  }
}
