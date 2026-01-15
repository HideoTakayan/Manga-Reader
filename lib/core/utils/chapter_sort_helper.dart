import '../../data/models_cloud.dart';

class ChapterSortHelper {
  /// Sắp xếp danh sách chương theo logic nghiệp vụ manga
  static List<CloudChapter> sort(List<CloudChapter> chapters) {
    if (chapters.isEmpty) return [];

    // Tạo bản sao để tránh thay đổi danh sách gốc nếu cần
    final List<CloudChapter> sortedList = List.from(chapters);

    sortedList.sort((a, b) {
      final infoA = _parseFilename(a.title);
      final infoB = _parseFilename(b.title);

      if (infoA.isExtra != infoB.isExtra) {
        return infoA.isExtra ? 1 : -1;
      }
      if (infoA.main != infoB.main) {
        return infoA.main.compareTo(infoB.main);
      }
      if (infoA.sub != infoB.sub) {
        return infoA.sub.compareTo(infoB.sub);
      }
      return a.title.compareTo(b.title);
    });

    // Sau khi sort, chuyển đổi tên file thành "Chương X" để hiển thị
    return sortedList.map((ch) {
      return CloudChapter(
        id: ch.id,
        title: getDisplayTitle(ch.title), // Đổi tên ở đây
        fileId: ch.fileId,
        fileType: ch.fileType,
        sizeBytes: ch.sizeBytes,
        uploadedAt: ch.uploadedAt,
        viewCount: ch.viewCount,
      );
    }).toList();
  }

  /// Chuyển đổi tên file thành định dạng: Chương X [Extra]
  static String getDisplayTitle(String filename) {
    final info = _parseFilename(filename);

    if (info.main == double.infinity) {
      // Nếu không parse được số (Oneshot, Preview...), giữ nguyên tên file bỏ đuôi
      return filename.split('.').first;
    }

    // Định dạng số chương (bỏ .0 nếu là số nguyên)
    String numberStr = info.main % 1 == 0
        ? info.main.toInt().toString()
        : info.main.toString();
    if (info.sub > 0) {
      numberStr += ".${info.sub}";
    }

    String display = "Chương $numberStr";
    if (info.isExtra) {
      display += " Extra";
    }

    return display;
  }

  static _ChapterParseInfo _parseFilename(String filename) {
    final lowerName = filename.toLowerCase();

    // Kiểm tra Extra/Omake/Special
    bool isExtra = false;
    if (lowerName.contains('extra') ||
        lowerName.contains('omake') ||
        lowerName.contains('special')) {
      isExtra = true;
    }

    // Tìm số chương sau từ khóa (ch, chap, chapter, c, extra, omake, special)
    // RegExp hỗ trợ: chap 1, ch.1, c. 01, chapter 26.1, extra 2
    final regExp = RegExp(
      r'(?:ch|chap|chapter|c|extra|omake|special)\.?\s*(\d+(?:\.\d+)?)',
      caseSensitive: false,
    );

    final match = regExp.firstMatch(filename);

    if (match != null) {
      final numberStr = match.group(1)!;
      return _normalizeNumber(numberStr, isExtra);
    }

    // Fallback: Nếu không tìm thấy từ khóa, thử tìm số đầu tiên trong chuỗi
    final fallbackRegExp = RegExp(r'(\d+(?:\.\d+)?)');
    final fallbackMatch = fallbackRegExp.firstMatch(filename);
    if (fallbackMatch != null) {
      return _normalizeNumber(fallbackMatch.group(1)!, isExtra);
    }

    // Trường hợp xấu nhất: Không có số nào (Oneshot, Preview...) -> Đẩy xuống cuối (+Infinity)
    return _ChapterParseInfo(isExtra: isExtra, main: double.infinity, sub: 0);
  }

  static _ChapterParseInfo _normalizeNumber(String numberStr, bool isExtra) {
    if (numberStr.contains('.')) {
      final parts = numberStr.split('.');
      final mainPart = double.tryParse(parts[0]) ?? 0;
      // Lấy phần sau dấu chấm và parse thành int để bỏ số 0 vô nghĩa (01 -> 1)
      final subPart = int.tryParse(parts[1]) ?? 0;
      return _ChapterParseInfo(isExtra: isExtra, main: mainPart, sub: subPart);
    } else {
      final mainPart = double.tryParse(numberStr) ?? 0;
      return _ChapterParseInfo(isExtra: isExtra, main: mainPart, sub: 0);
    }
  }
}

class _ChapterParseInfo {
  final bool isExtra;
  final double main;
  final int sub;

  _ChapterParseInfo({
    required this.isExtra,
    required this.main,
    required this.sub,
  });
}
