import 'dart:collection';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'epub_models.dart';
import 'epub_parser.dart';

typedef EpubChapterParser =
    Future<EpubChapter> Function(EpubChapterReference chapter);

class EpubLazyChapterLoader {
  final ParsedEpubIndex index;
  final int maxCachedChapters;
  late final EpubChapterParser _parser;
  final LinkedHashMap<int, EpubChapter> _cache = LinkedHashMap();
  final Map<int, Future<EpubChapter>> _pending = {};
  
  final Map<String, ArchiveFile> _archive;

  EpubLazyChapterLoader({
    required this.index,
    required Uint8List bytes,
    this.maxCachedChapters = 5,
    EpubChapterParser? parser,
  }) : _archive = EpubParser.decodeFiles(bytes),
       assert(maxCachedChapters > 0) {
    _parser = parser ??
        ((chapter) async {
          // Decode directly in the UI thread for now.
          return EpubParser.buildChapter(_archive, chapter);
        });
  }

  Iterable<int> get cachedChapterIndexes => _cache.keys;

  EpubChapter? peek(int chapterIndex) => _cache[chapterIndex];

  Future<EpubChapter> load(int chapterIndex) async {
    if (chapterIndex < 0 || chapterIndex >= index.chapters.length) {
      throw RangeError.index(chapterIndex, index.chapters, 'chapterIndex');
    }

    final cached = _cache.remove(chapterIndex);
    if (cached != null) {
      _cache[chapterIndex] = cached;
      return cached;
    }

    final existing = _pending[chapterIndex];
    if (existing != null) return existing;

    final future = _parser(index.chapters[chapterIndex]);
    _pending[chapterIndex] = future;
    try {
      final chapter = await future;
      _cache[chapterIndex] = chapter;
      _trimCache();
      return chapter;
    } finally {
      _pending.remove(chapterIndex);
    }
  }

  Future<void> preloadAround(int centerChapter, {int radius = 1}) async {
    for (
      var chapterIndex = centerChapter - radius;
      chapterIndex <= centerChapter + radius;
      chapterIndex++
    ) {
      if (chapterIndex < 0 || chapterIndex >= index.chapters.length) continue;
      await load(chapterIndex);
    }
  }

  void retainAround(int centerChapter, {int radius = 2}) {
    _cache.removeWhere(
      (chapterIndex, _) => (chapterIndex - centerChapter).abs() > radius,
    );
  }

  void clear() {
    _cache.clear();
    _pending.clear();
  }

  void _trimCache() {
    while (_cache.length > maxCachedChapters) {
      _cache.remove(_cache.keys.first);
    }
  }
}