import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/data/content_type.dart';

void main() {
  group('parseContentType', () {
    test('defaults missing values to manga', () {
      expect(parseContentType(null), MangaContentType.manga);
      expect(parseContentType(''), MangaContentType.manga);
    });

    test('parses explicit manga and novel values', () {
      expect(parseContentType('manga'), MangaContentType.manga);
      expect(parseContentType('comic'), MangaContentType.manga);
      expect(parseContentType('novel'), MangaContentType.novel);
      expect(parseContentType('light_novel'), MangaContentType.novel);
    });

    test('infers novel from legacy genre values', () {
      expect(
        parseContentType(null, genres: ['Action', 'Truyện chữ']),
        MangaContentType.novel,
      );
      expect(
        parseContentType(null, genres: ['Web Novel']),
        MangaContentType.novel,
      );
      expect(
        parseContentType(null, genres: ['Fantasy']),
        MangaContentType.manga,
      );
    });
  });
}
