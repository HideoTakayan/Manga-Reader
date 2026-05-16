import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/core/utils/archive_image_extractor.dart';

void main() {
  test('extracts supported images in natural order', () async {
    final archive = Archive()
      ..addFile(ArchiveFile('10.jpg', 3, [10, 10, 10]))
      ..addFile(ArchiveFile('2.png', 2, [2, 2]))
      ..addFile(ArchiveFile('readme.txt', 1, [1]));

    final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
    final images = await ArchiveImageExtractor.extract(bytes);

    expect(images.length, 2);
    expect(images[0], Uint8List.fromList([2, 2]));
    expect(images[1], Uint8List.fromList([10, 10, 10]));
  });

  test('returns empty list for invalid archive bytes', () async {
    final images = await ArchiveImageExtractor.extract(
      Uint8List.fromList([1, 2, 3]),
    );

    expect(images, isEmpty);
  });
}
