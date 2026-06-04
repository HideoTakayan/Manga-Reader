import 'dart:io';


import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/core/utils/archive_image_extractor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  setUpAll(() {
    // Mock path_provider for unit tests
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return Directory.systemTemp.path;
      },
    );
  });

  test('extracts supported images in natural order', () async {
    final archive = Archive()
      ..addFile(ArchiveFile('10.jpg', 3, [10, 10, 10]))
      ..addFile(ArchiveFile('2.png', 2, [2, 2]))
      ..addFile(ArchiveFile('readme.txt', 1, [1]));

    final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
    final imagePaths = await ArchiveImageExtractor.extract(bytes, 'test_chapter');

    expect(imagePaths.length, 2);
    expect(File(imagePaths[0]).readAsBytesSync(), [2, 2]);
    expect(File(imagePaths[1]).readAsBytesSync(), [10, 10, 10]);
  });

  test('returns empty list for invalid archive bytes', () async {
    final imagePaths = await ArchiveImageExtractor.extract(
      Uint8List.fromList([1, 2, 3]),
      'test_chapter',
    );

    expect(imagePaths, isEmpty);
  });
}
