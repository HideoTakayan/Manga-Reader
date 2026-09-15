import '../../data/models_cloud.dart';

class ChapterSortHelper {
  /// Sắp xếp danh sách chương theo logic nghiệp vụ manga
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
      // Xử lý các chương đặc biệt như Oneshot
      return filename.split('.').first;
    }

    String display = "Chương ${info.displayValue}";
    if (info.extraLabel != null) {
      display += " ${info.extraLabel}";
    } else if (info.isExtra && !display.contains("Extra")) {
      display += " Extra";
    }
    return display;
  }

  // --- Xử lý cắt chuỗi ---

  // Mẫu Regex cốt lõi: bắt nhóm số nguyên, phần thập phân và hậu tố chữ cái
  // Ví dụ: "10.5a" -> nhóm 1="10", nhóm 2=".5", nhóm 3="a"
  static const String _numberPattern = r'([0-9]+)(\.[0-9]+)?(\.?[a-z]+)?';

  // Biểu thức chính quy bỏ qua các thông tin volume/season: Vol.1, v1, season 2...
  static final _unwanted = RegExp(
    r'\b(?:v|ver|vol|version|volume|season|s)[^a-z]?[0-9]+',
    caseSensitive: false,
  );

  // Biểu thức tìm chuỗi như "ch. 123", "chương 123", "tập 123"...
  static final _basic = RegExp(
    r'(?:ch\.|chap\.|chapter\.|c\.|ch|chap|chapter|c|chương|tập|hồi)\s*' +
        _numberPattern,
    caseSensitive: false,
  );

  // Biểu thức tìm số đơn thuần: 123
  static final _number = RegExp(_numberPattern, caseSensitive: false);

  // Loại bỏ khoảng trắng thừa trước các từ khóa
  static final _unwantedWhiteSpace = RegExp(
    r'\s(?=extra|special|omake)',
    caseSensitive: false,
  );

  /// Phân tích tên file thô và trả về thông tin số chương dạng số thực
  /// để có thể so sánh và sắp xếp chính xác.
  static _ChapterParseInfo _parseFilename(String filename) {
    String cleanName = filename.toLowerCase();

    // 1. Loại bỏ dấu phẩy, dấu gạch ngang
    cleanName = cleanName.replaceAll(',', '.').replaceAll('-', '.');

    // 2. Loại bỏ các khoảng trắng nối với từ khóa
    cleanName = cleanName.replaceAll(_unwantedWhiteSpace, '');

    bool isExtra =
        cleanName.contains('extra') ||
        cleanName.contains('omake') ||
        cleanName.contains('special');

    // 3. Loại bỏ thông tin phần (Volume) để tránh nhận diện nhầm số (hiện trạng Vol.1 Ch.5 -> Ch.5)
    String nameWithoutVolume = cleanName.replaceAll(_unwanted, '');

    // 4. Thử khớp cơ bản (có tiền tố) trên chuỗi đã lọc
    var match = _basic.firstMatch(nameWithoutVolume);
    if (match != null) {
      return _getChapterNumberFromMatch(match, isExtra, cleanName);
    }

    // 5. Nếu không thấy, tìm XEM CÓ BẤT CỨ SỐ NÀO trong chuỗi không
    match = _number.firstMatch(nameWithoutVolume);
    if (match != null) {
      return _getChapterNumberFromMatch(match, isExtra, cleanName);
    }

    // 6. Trường hợp an toàn (Fail-safe): Thử lại trên chuỗi ban đầu (đề phòng số duy nhất bị xóa lầm như "Vol. 1")
    match = _basic.firstMatch(cleanName);
    if (match != null) return _getChapterNumberFromMatch(match, isExtra, cleanName);

    match = _number.firstMatch(cleanName);
    if (match != null) return _getChapterNumberFromMatch(match, isExtra, cleanName);

    return _ChapterParseInfo(value: double.infinity, isExtra: isExtra, displayValue: '');
  }

  /// Trích xuất số chương từ kết quả khớp Regex và trả về _ChapterParseInfo.
  /// Kết hợp phần nguyên + phần thập phân + hậu tố chữ cái thành một số thực duy nhất.
  static _ChapterParseInfo _getChapterNumberFromMatch(
    RegExpMatch match,
    bool extra,
    String cleanName,
  ) {
    double initial = double.parse(match.group(1)!);
    String? subDecimal = match.group(2);
    String? subAlpha = match.group(3);

    String? extraLabel;
    if (cleanName.contains("extra")) {
      extraLabel = "Extra";
    } else if (cleanName.contains("omake")) {
      extraLabel = "Omake";
    } else if (cleanName.contains("special")) {
      extraLabel = "Special";
    }

    double addition = _checkForDecimal(subDecimal, subAlpha);

    String displayNum;
    if (subDecimal != null && subDecimal.isNotEmpty) {
      // 10.5 -> "10.5"
      final fullNum = initial + double.parse(subDecimal);
      displayNum = fullNum % 1 == 0 ? fullNum.toInt().toString() : fullNum.toString();
    } else if (subAlpha != null && subAlpha.replaceAll('.', '').length == 1 && RegExp(r'[a-zA-Z]').hasMatch(subAlpha)) {
      displayNum = "${initial.toInt()}${subAlpha.replaceAll('.', '')}";
    } else {
      displayNum = initial.toInt().toString();
    }

    return _ChapterParseInfo(
      value: initial + addition,
      isExtra: extra,
      displayValue: displayNum,
      extraLabel: extraLabel,
    );
  }

  /// Chuyển đổi phần phụ (thập phân hoặc hậu tố chữ cái) thành giá trị số nhỏ để cộng vào số chương.
  /// Extra=0.99, Omake=0.98, Special=0.97, chữ cái a-i tương ứng 0.1-0.9.
  static double _checkForDecimal(String? decimal, String? alpha) {
    if (decimal != null && decimal.isNotEmpty) {
      return double.parse(decimal);
    }

    if (alpha != null && alpha.isNotEmpty) {
      if (alpha.contains("extra")) return 0.99;
      if (alpha.contains("omake")) return 0.98;
      if (alpha.contains("special")) return 0.97;

      // Kí tự chữ a -> .1
      String trimmed = alpha.replaceAll('.', '');
      if (trimmed.length == 1) {
        return _parseAlphaPostFix(trimmed[0]);
      }
    }
    return 0.0;
  }

  /// Chuyển hậu tố chữ cái (a, b, c...) thành số thập phân nhỏ (0.1, 0.2, 0.3...).
  /// Dùng để phân biệt "Chương 10a" vs "Chương 10b" khi sắp xếp.
  static double _parseAlphaPostFix(String char) {
    int code = char.codeUnitAt(0);
    int aCode = 'a'.codeUnitAt(0);
    int number = code - (aCode - 1);
    if (number < 1 || number >= 10) return 0.0;
    return number / 10.0;
  }
}

/// Class nội bộ lưu kết quả phân tích tên chương.
/// [value]: Số chương dưới dạng số thực (VD: 10.5, 10.99 cho Extra).
/// [isExtra]: Có phải chương đặc biệt (Extra/Omake/Special) không.
/// [displayValue]: Chuỗi số định dạng chuẩn để hiển thị UI (VD: "10", "10.5", "10a").
/// [extraLabel]: Hậu tố đặc biệt nếu có ("Extra", "Omake", "Special").
class _ChapterParseInfo implements Comparable<_ChapterParseInfo> {
  final double value;
  final bool isExtra;
  final String displayValue;
  final String? extraLabel;

  _ChapterParseInfo({
    required this.value,
    required this.isExtra,
    required this.displayValue,
    this.extraLabel,
  });

  /// So sánh 2 chương theo số thực để phục vụ việc sắp xếp.
  @override
  int compareTo(_ChapterParseInfo other) {
    if (value != other.value) {
      return value.compareTo(other.value); // Sắp xếp tăng dần theo số
    }
    if (isExtra != other.isExtra) {
      return isExtra ? 1 : -1;
    }
    return 0; // Bằng nhau thì giữ nguyên vị trí
  }
}
