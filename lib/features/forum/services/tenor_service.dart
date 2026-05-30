import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../config/tenor_config.dart';

class TenorService {
  Future<List<String>> getTrendingGifs() async {
    try {
      final uri = Uri.https('api.tenor.com', '/v1/trending', {
        'key': TenorConfig.apiKey,
        'limit': '20',
        'media_filter': 'minimal',
      });
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        return _parseGifs(response.body);
      } else {
        throw Exception('Tenor trending failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching GIFs: $e');
    }
  }

  Future<List<String>> searchGifs(String query) async {
    try {
      final uri = Uri.https('api.tenor.com', '/v1/search', {
        'q': query,
        'key': TenorConfig.apiKey,
        'limit': '20',
        'media_filter': 'minimal',
      });
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        return _parseGifs(response.body);
      } else {
        throw Exception('Tenor search failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error searching GIFs: $e');
    }
  }

  List<String> _parseGifs(String responseBody) {
    final data = jsonDecode(responseBody);
    final results = data['results'] as List? ?? [];

    final urls = <String>[];
    for (final gif in results) {
      try {
        final media = gif['media'] as List?;
        if (media != null && media.isNotEmpty) {
          final url = media[0]['tinygif']?['url'] ?? media[0]['gif']?['url'];
          if (url != null) {
            urls.add(url as String);
          }
        }
      } catch (e) {
        // Skip malformed item
      }
    }
    return urls;
  }
}
