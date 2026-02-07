import '../../data/models_cloud.dart';

class ChapterSortHelper {
  /// Sắp xếp danh sách chương theo logic nghiệp vụ manga
  /// Updated with logic ported from Mihon for robust parsing
  static List<CloudChapter> sort(List<CloudChapter> chapters) {
    if (chapters.isEmpty) return [];

    final List<CloudChapter> sortedList = List.from(chapters);

    sortedList.sort((a, b) {
      final infoA = _parseFilename(a.title);
      final infoB = _parseFilename(b.title);
      return infoA.compareTo(infoB);
    });

    // Sau khi sort, chuyển đổi tên file thành "Chương X" để hiển thị
    return sortedList.map((ch) {
      return CloudChapter(
        id: ch.id,
        title: getDisplayTitle(ch.title),
        fileId: ch.fileId,
        fileType: ch.fileType,
        sizeBytes: ch.sizeBytes,
        uploadedAt: ch.uploadedAt,
        viewCount: ch.viewCount,
      );
    }).toList();
  }

  /// Chuyển đổi tên file thành định dạng hiển thị
  static String getDisplayTitle(String filename) {
    final info = _parseFilename(filename);

    if (info.value == double.infinity) {
      // Oneshot, etc.
      return filename.split('.').first;
    }

    // Format double to string without trailing zeros
    // 10.0 -> "10", 10.5 -> "10.5"
    String numberStr = info.value % 1 == 0
        ? info.value.toInt().toString()
        : info.value.toString();

    String display = "Chương $numberStr";
    // Extra handled in value (e.g. .99), but for display we usually keep format
    // But here we standardized to "Chương X".
    // If it was "Extra", info.isExtra is true.
    if (info.isExtra && !display.contains("Extra")) {
      display += " Extra";
    }
    return display;
  }

  // --- Parsing Logic (Ported from Mihon) ---

  static const String _numberPattern = r'([0-9]+)(\.[0-9]+)?(\.?[a-z]+)?';

  // Regex to remove unwanted volume/season info: Vol.1, v1, season 2...
  static final _unwanted = RegExp(
    r'\b(?:v|ver|vol|version|volume|season|s)[^a-z]?[0-9]+',
    caseSensitive: false,
  );

  // Regex to find "ch. 123"
  static final _basic = RegExp(
    r'(?:ch\.|chap\.|chapter\.|c\.|ch|chap|chapter|c)\s*' + _numberPattern,
    caseSensitive: false,
  );

  // Regex to find just number: 123
  static final _number = RegExp(_numberPattern, caseSensitive: false);

  static final _unwantedWhiteSpace = RegExp(
    r'\s(?=extra|special|omake)',
    caseSensitive: false,
  );

  static _ChapterParseInfo _parseFilename(String filename) {
    String cleanName = filename.toLowerCase();

    // 1. Remove commas, hyphens
    cleanName = cleanName.replaceAll(',', '.').replaceAll('-', '.');

    // 2. Remove unwanted white spaces
    cleanName = cleanName.replaceAll(_unwantedWhiteSpace, '');

    bool isExtra =
        cleanName.contains('extra') ||
        cleanName.contains('omake') ||
        cleanName.contains('special');

    // 3. Remove Volume info to avoid false positives (Vol.1 Ch.5 -> Ch.5)
    String nameWithoutVolume = cleanName.replaceAll(_unwanted, '');

    // 4. Try basic match (with prefix) on cleaned string
    var match = _basic.firstMatch(nameWithoutVolume);
    if (match != null) {
      return _getChapterNumberFromMatch(match, isExtra);
    }

    // 5. If not found, look for ANY number in cleaned string
    match = _number.firstMatch(nameWithoutVolume);
    if (match != null) {
      return _getChapterNumberFromMatch(match, isExtra);
    }

    // 6. Fail-safe: Try original string (if volume was the only number, e.g. "Vol. 1")
    match = _basic.firstMatch(cleanName);
    if (match != null) return _getChapterNumberFromMatch(match, isExtra);

    match = _number.firstMatch(cleanName);
    if (match != null) return _getChapterNumberFromMatch(match, isExtra);

    return _ChapterParseInfo(value: double.infinity, isExtra: isExtra);
  }

  static _ChapterParseInfo _getChapterNumberFromMatch(
    RegExpMatch match,
    bool extra,
  ) {
    double initial = double.parse(match.group(1)!);
    String? subDecimal = match.group(2);
    String? subAlpha = match.group(3);

    double addition = _checkForDecimal(subDecimal, subAlpha);

    return _ChapterParseInfo(value: initial + addition, isExtra: extra);
  }

  static double _checkForDecimal(String? decimal, String? alpha) {
    if (decimal != null && decimal.isNotEmpty) {
      return double.parse(decimal);
    }

    if (alpha != null && alpha.isNotEmpty) {
      if (alpha.contains("extra")) return 0.99;
      if (alpha.contains("omake")) return 0.98;
      if (alpha.contains("special")) return 0.97;

      // .a -> .1
      String trimmed = alpha.replaceAll('.', '');
      if (trimmed.length == 1) {
        return _parseAlphaPostFix(trimmed[0]);
      }
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

class _ChapterParseInfo implements Comparable<_ChapterParseInfo> {
  final double value;
  final bool isExtra;

  _ChapterParseInfo({required this.value, required this.isExtra});

  @override
  int compareTo(_ChapterParseInfo other) {
    if (value != other.value) {
      return value.compareTo(other.value);
    }
    return 0;
  }
}
