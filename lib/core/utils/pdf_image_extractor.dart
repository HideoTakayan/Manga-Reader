import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';

class PdfImageExtractor {
  PdfImageExtractor._();

  static Future<List<String>> extract(String filePath, String chapterId) async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory(p.join(tempDir.path, 'reader_cache', chapterId));

    if (await cacheDir.exists()) {
      final files = cacheDir.listSync().whereType<File>().toList();
      if (files.isNotEmpty) {
        final paths = files.map((f) => f.path).toList();
        paths.sort((a, b) => _naturalCompare(p.basename(a), p.basename(b)));
        debugPrint('? Reusing extracted PDF cache for chapter $chapterId');
        return paths;
      }
      await cacheDir.delete(recursive: true);
    }
    await cacheDir.create(recursive: true);

    debugPrint('? Extracting PDF: $filePath');
    final paths = <String>[];

    try {
      final document = await PdfDocument.openFile(filePath);
      final pageCount = document.pagesCount;

      for (int i = 1; i <= pageCount; i++) {
        final page = await document.getPage(i);
        final pageImage = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: PdfPageImageFormat.jpeg,
        );
        await page.close();

        if (pageImage != null) {
          final outPath = p.join(cacheDir.path, "page_$i.jpg");
          final file = File(outPath);
          await file.writeAsBytes(pageImage.bytes);
          paths.add(outPath);
        }
      }

      // Khong the await close() tren PDF document trong pdfx ban cu neu no bi bug,
      // nhung document.close() thuong k co kieu tra ve hoac khong can thiet trong 1 so ver
      // Tuy nhien toi uu la kieu:
      // await document.close();
    } catch (e) {
      debugPrint('?? PDF Extraction Error: $e');
    }

    paths.sort((a, b) => _naturalCompare(p.basename(a), p.basename(b)));
    return paths;
  }

  static int _naturalCompare(String a, String b) {
    final regex = RegExp(r'(\d+)');
    final matchA = regex.firstMatch(a);
    final matchB = regex.firstMatch(b);

    if (matchA != null && matchB != null) {
      final numA = int.parse(matchA.group(1)!);
      final numB = int.parse(matchB.group(1)!);
      return numA.compareTo(numB);
    }
    return a.compareTo(b);
  }
}
