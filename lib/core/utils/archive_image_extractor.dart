import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

class ArchiveImageExtractor {
  ArchiveImageExtractor._();

  static Future<List<Uint8List>> extract(Uint8List bytes) async {
    return compute(_extractZipImages, bytes);
  }
}

List<Uint8List> _extractZipImages(Uint8List bytes) {
  final images = <Uint8List>[];
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final sortedFiles = archive.files.toList()
      ..sort((a, b) => _naturalCompare(a.name, b.name));

    for (final file in sortedFiles) {
      if (!file.isFile) continue;
      final name = file.name.toLowerCase();
      if (!_isSupportedImage(name)) continue;

      final content = file.content;
      if (content is Uint8List) {
        images.add(content);
      } else if (content is List<int>) {
        images.add(Uint8List.fromList(content));
      } else {
        continue;
      }
    }
  } catch (_) {}
  return images;
}

bool _isSupportedImage(String name) {
  return name.endsWith('.jpg') ||
      name.endsWith('.jpeg') ||
      name.endsWith('.png') ||
      name.endsWith('.webp');
}

int _naturalCompare(String a, String b) {
  final regExp = RegExp(r'(\d+)|(\D+)');
  final am = regExp.allMatches(a.toLowerCase()).toList();
  final bm = regExp.allMatches(b.toLowerCase()).toList();

  for (int i = 0; i < am.length && i < bm.length; i++) {
    final ap = am[i].group(0)!;
    final bp = bm[i].group(0)!;
    if (ap == bp) continue;

    final ai = int.tryParse(ap);
    final bi = int.tryParse(bp);
    if (ai != null && bi != null) return ai.compareTo(bi);
    return ap.compareTo(bp);
  }

  return a.length.compareTo(b.length);
}
