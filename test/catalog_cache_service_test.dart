import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/features/catalog/catalog_cache_service.dart';

void main() {
  test('catalog normalization makes Vietnamese text accent insensitive', () {
    final normalize = CatalogCacheService.instance.normalize;

    expect(normalize('Võ Luyện Đỉnh Phong'), 'vo luyen dinh phong');
    expect(normalize('vo luyen dinh phong'), 'vo luyen dinh phong');
  });
}
