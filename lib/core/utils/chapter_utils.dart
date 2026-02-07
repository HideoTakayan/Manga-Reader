import '../../data/models_cloud.dart';
import '../../services/download_cache.dart';
import 'chapter_sort_helper.dart';

class ChapterUtils {
  /// Merges online and offline chapter lists, prioritizing offline (downloaded) chapters.
  /// Also ensures the result is sorted correctly.
  static Future<List<CloudChapter>> mergeChapters(
    List<CloudChapter> online,
    List<CloudChapter> offline,
    String mangaId,
  ) async {
    final List<CloudChapter> finalChapters = [];
    final Set<String> processedTitles = {};
    final Set<String> processedIds = {}; // New: Prevent duplicate objects by ID

    String normalize(String title) {
      // Normalize: lower case, remove invisible chars, trailing punctuation, extra spaces
      var s = title.trim().toLowerCase();
      s = s.replaceAll(
        RegExp(r'[\u200B-\u200D\uFEFF]'),
        '',
      ); // Zero width chars
      s = s.replaceAll(RegExp(r'[.,;:]$'), ''); // Trailing punctuation
      return s.replaceAll(RegExp(r'\s+'), ' ');
    }

    // Debug Log
    print(
      '🔄 MERGE START: Offline=${offline.length}, Online=${online.length} for MangaID: $mangaId',
    );

    final Map<String, CloudChapter> onlineMap = {};
    for (final ch in online) {
      onlineMap[normalize(ch.title)] = ch;
    }

    // 1. Offline (Priority if downloaded)
    // Filter duplicates in input list first
    for (final localCh in offline) {
      // ID check
      if (processedIds.contains(localCh.id)) {
        continue;
      }

      final normTitle = normalize(localCh.title);

      // Title check (if strictly duplicate title)
      if (processedTitles.contains(normTitle)) {
        print('⚠️ Duplicate Title (Offline): "$normTitle" - ID: ${localCh.id}');
        continue;
      }

      // Check download cache efficiently
      bool isDownloaded = false;
      try {
        isDownloaded = await DownloadCache.instance.isChapterDownloaded(
          localCh.id,
          mangaId,
        );
      } catch (e) {
        print('❌ Cache check failed for ${localCh.id}: $e');
      }

      if (isDownloaded) {
        finalChapters.add(localCh);
        processedTitles.add(normTitle);
        processedIds.add(localCh.id);

        // Remove from online map to avoid processing again
        onlineMap.remove(normTitle);
      }
    }

    // 2. Online (If not covered by Offline)
    for (final ch in online) {
      if (processedIds.contains(ch.id)) continue;

      final normTitle = normalize(ch.title);
      if (processedTitles.contains(normTitle)) continue;

      finalChapters.add(ch);
      processedTitles.add(normTitle);
      processedIds.add(ch.id);
    }

    // 3. Remaining Offline (That were NOT downloaded but exist in local DB)
    for (final localCh in offline) {
      if (processedIds.contains(localCh.id)) continue;

      final normTitle = normalize(localCh.title);
      if (processedTitles.contains(normTitle)) continue;

      finalChapters.add(localCh);
      processedTitles.add(normTitle);
      processedIds.add(localCh.id);
    }

    // 4. Sort Ascending
    final result = ChapterSortHelper.sort(finalChapters);

    // 5. Force Deduplication by Chapter Number (Aggressive)
    final uniqueByNumber = <double, CloudChapter>{};
    final finalResult = <CloudChapter>[];

    for (final ch in result) {
      final num = _parseChapterNumber(ch.title);

      // Debug log
      print('🔍 Check Dedupe: "${ch.title}" -> Num: $num (ID: ${ch.id})');

      if (num == -1) {
        // Cannot parse number -> Keep it (e.g. "Oneshot")
        finalResult.add(ch);
      } else {
        if (!uniqueByNumber.containsKey(num)) {
          uniqueByNumber[num] = ch;
          finalResult.add(ch);
        } else {
          // Duplicate number found!
          // Prioritize Downloaded?
          // 'result' is already sorted by ChapterSortHelper which handles sort.
          // However, we want to keep the one that is Downloaded if mixed.
          // The current list 'result' comes from 'finalChapters'.
          // 'finalChapters' prioritized 'Offline' (Downloaded) in step 1.
          // So the Downloaded one should be earlier in the list IF sorting preserves relative order?
          // ChapterSortHelper.sort re-orders based on Number.
          // If we have "Ch. 1" (Down) and "Chapter 1" (Cloud). Both Number 1.
          // Sorting might put "Ch. 1" before or after "Chapter 1".
          // Stable sort? Dart sort is unstable by default?
          // Actually, 'uniqueByNumber' keeps the FIRST one encountered in 'result'.

          print('⚠️ Removed Duplicate Number: $num ("${ch.title}" - ${ch.id})');
        }
      }
    }

    print('✅ MERGE END: Result=${finalResult.length} chapters');
    return finalResult;
  }

  // --- Parsing Logic (Ported from ChapterSortHelper to be standalone) ---
  static double _parseChapterNumber(String filename) {
    final info = _parseFilename(filename);
    return info.value == double.infinity ? -1 : info.value;
  }

  static const String _numberPattern = r'([0-9]+)(\.[0-9]+)?(\.?[a-z]+)?';
  static final _unwanted = RegExp(
    r'\b(?:v|ver|vol|version|volume|season|s)[^a-z]?[0-9]+',
    caseSensitive: false,
  );
  // Vietnamese Support
  static final _basic = RegExp(
    r'(?:ch\.|chap\.|chapter\.|c\.|ch|chap|chapter|c|chương|tập|hồi)\s*' +
        _numberPattern,
    caseSensitive: false,
  );
  static final _number = RegExp(_numberPattern, caseSensitive: false);
  static final _unwantedWhiteSpace = RegExp(
    r'\s(?=extra|special|omake)',
    caseSensitive: false,
  );

  static _ParseInfo _parseFilename(String filename) {
    String cleanName = filename.toLowerCase();
    cleanName = cleanName.replaceAll(',', '.').replaceAll('-', '.');
    cleanName = cleanName.replaceAll(_unwantedWhiteSpace, '');
    bool isExtra =
        cleanName.contains('extra') ||
        cleanName.contains('omake') ||
        cleanName.contains('special');
    String nameWithoutVolume = cleanName.replaceAll(_unwanted, '');

    var match = _basic.firstMatch(nameWithoutVolume);
    if (match != null) return _getChapterNumberFromMatch(match, isExtra);

    match = _number.firstMatch(nameWithoutVolume);
    if (match != null) return _getChapterNumberFromMatch(match, isExtra);

    match = _basic.firstMatch(cleanName);
    if (match != null) return _getChapterNumberFromMatch(match, isExtra);

    match = _number.firstMatch(cleanName);
    if (match != null) return _getChapterNumberFromMatch(match, isExtra);

    return _ParseInfo(value: double.infinity, isExtra: isExtra);
  }

  static _ParseInfo _getChapterNumberFromMatch(RegExpMatch match, bool extra) {
    double initial = double.parse(match.group(1)!);
    String? subDecimal = match.group(2);
    String? subAlpha = match.group(3);
    double addition = _checkForDecimal(subDecimal, subAlpha);
    return _ParseInfo(value: initial + addition, isExtra: extra);
  }

  static double _checkForDecimal(String? decimal, String? alpha) {
    if (decimal != null && decimal.isNotEmpty) return double.parse(decimal);
    if (alpha != null && alpha.isNotEmpty) {
      if (alpha.contains("extra")) return 0.99;
      if (alpha.contains("omake")) return 0.98;
      if (alpha.contains("special")) return 0.97;
      String trimmed = alpha.replaceAll('.', '');
      if (trimmed.length == 1) return _parseAlphaPostFix(trimmed[0]);
    }
    return 0.0;
  }

  static double _parseAlphaPostFix(String char) {
    int code = char.codeUnitAt(0);
    int aCode = 'a'.codeUnitAt(0);
    int number = code - (aCode - 1);
    if (number >= 10) return 0.0;
    return number / 10.0;
  }
}

class _ParseInfo {
  final double value;
  final bool isExtra;
  _ParseInfo({required this.value, required this.isExtra});
}
