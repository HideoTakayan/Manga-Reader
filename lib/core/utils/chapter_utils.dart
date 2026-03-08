import '../../data/models_cloud.dart';
import '../../services/download_cache.dart';
import 'chapter_sort_helper.dart';

/// Tiện ích xử lý danh sách chương: gộp nguồn online + offline, lọc trùng lặp và sắp xếp đúng thứ tự.
class ChapterUtils {
  /// Kết hợp danh sách chương từ máy chủ và lưu trữ nội bộ. Ưu tiên các chương đã tải xuống (ngoại tuyến).
  /// Đảm bảo kết quả trả về không bị trùng lặp và được sắp xếp đúng thứ tự.
  static Future<List<CloudChapter>> mergeChapters(
    List<CloudChapter> online,
    List<CloudChapter> offline,
    String mangaId,
  ) async {
    final List<CloudChapter> finalChapters = [];
    final Set<String> processedTitles = {};
    final Set<String> processedIds =
        {}; // Tránh trùng lặp khi dùng đối tượng chapter có cùng ID

    String normalize(String title) {
      // Chuẩn hóa tên chương: đưa về chữ thường, bỏ ký tự ẩn, dấu câu thừa và các khoảng trắng thừa
      var s = title.trim().toLowerCase();
      s = s.replaceAll(
        RegExp(r'[\u200B-\u200D\uFEFF]'),
        '',
      ); // Các ký tự ẩn (zero-width)
      s = s.replaceAll(RegExp(r'[.,;:]$'), ''); // Bỏ dấu chấm phẩy ở cuối
      return s.replaceAll(RegExp(r'\s+'), ' ');
    }

    // Ghi log lỗi để kiểm tra quá trình gộp
    print(
      '🔄 BẮT ĐẦU GỘP: Offline=${offline.length}, Online=${online.length} cho MangaID: $mangaId',
    );

    // Tạo map tên chuẩn hóa -> chapter online để tra cứu nhanh khi xóa trùng
    final Map<String, CloudChapter> onlineMap = {};
    for (final ch in online) {
      onlineMap[normalize(ch.title)] = ch;
    }

    // 1. Xử lý tập tin ngoại tuyến trước (Được ưu tiên nếu đã tải về)
    // Lọc trùng lặp từ đầu vào trước
    for (final localCh in offline) {
      // Kiểm tra bằng ID
      if (processedIds.contains(localCh.id)) {
        continue;
      }

      final normTitle = normalize(localCh.title);

      // Kiểm tra tên (nếu trùng lặp chính xác về tên)
      if (processedTitles.contains(normTitle)) {
        print(
          '⚠️ Trùng lặp Tiêu đề (Ngoại tuyến): "$normTitle" - ID: ${localCh.id}',
        );
        continue;
      }

      // Kiểm tra bộ nhớ cache (Đã tải)
      bool isDownloaded = false;
      try {
        isDownloaded = await DownloadCache.instance.isChapterDownloaded(
          localCh.id,
          mangaId,
        );
      } catch (e) {
        print('❌ Lỗi kiểm tra cache tại id ${localCh.id}: $e');
      }

      if (isDownloaded) {
        finalChapters.add(localCh);
        processedTitles.add(normTitle);
        processedIds.add(localCh.id);

        // Xóa khỏi danh sách online để không lặp lại quá trình xử lý
        onlineMap.remove(normTitle);
      }
    }

    // 2. Xử lý chương Online chưa có trong kết quả (không bị chapter offline chiếm chỗ)
    for (final ch in online) {
      if (processedIds.contains(ch.id)) continue;

      final normTitle = normalize(ch.title);
      if (processedTitles.contains(normTitle)) continue;

      finalChapters.add(ch);
      processedTitles.add(normTitle);
      processedIds.add(ch.id);
    }

    // 3. Xử lý Offline còn lại (Chưa bị tải, nhưng nằm trong data db cục bộ do theo dõi)
    for (final localCh in offline) {
      if (processedIds.contains(localCh.id)) continue;

      final normTitle = normalize(localCh.title);
      if (processedTitles.contains(normTitle)) continue;

      finalChapters.add(localCh);
      processedTitles.add(normTitle);
      processedIds.add(localCh.id);
    }

    // 4. Sắp xếp toàn bộ danh sách theo số chương (tăng dần)
    final result = ChapterSortHelper.sort(finalChapters);

    // 5. Lọc trùng lặp lần cuối theo số chương (đề phòng 2 nguồn có cùng số nhưng khác ID/tên)
    // Bản offline đã được ưu tiên đưa vào trước ở bước 1, nên luôn được giữ lại.
    final uniqueByNumber = <double, CloudChapter>{};
    final finalResult = <CloudChapter>[];

    for (final ch in result) {
      final num = _parseChapterNumber(ch.title);

      // Log kiểm tra
      print('🔍 Kiểm tra Trùng lặp: "${ch.title}" -> Số: $num (ID: ${ch.id})');

      if (num == -1) {
        // Không thể parse -> Giữ nguyên (VD "Oneshot")
        finalResult.add(ch);
      } else {
        if (!uniqueByNumber.containsKey(num)) {
          uniqueByNumber[num] = ch;
          finalResult.add(ch);
        } else {
          // Ghi nhận trùng lặp số liệu!
          // Đã ưu tiên lấy bản `Downloaded` (Tải xuống) chưa?
          // `result` đã được tự động sắp xếp thông qua ChapterSortHelper.
          // Danh sách `finalChapters` đã đưa bản 'Offline' (Tải xuống) tại nhóm số 1 lên để ưu tiên giữ lại.
          // Cho nên bản đã tải về được xếp vào danh sách ưu tiên trước đó.
          // `uniqueByNumber` giữ mục chạm đầu tiên nằm trong danh sách.

          print('⚠️ Bỏ Số Trùng lặp: $num ("${ch.title}" - ${ch.id})');
        }
      }
    }

    print('✅ HOÀN TẤT GỘP: Kết quả=${finalResult.length} chương');
    return finalResult;
  }

  // --- Các hàm phân tích tên chương nội bộ ---
  // (Tái sử dụng logic từ ChapterSortHelper nhưng trả về double thay vì _ChapterParseInfo
  //  để dùng độc lập mà không phụ thuộc vào class nội bộ của ChapterSortHelper)

  /// Chuyển tên chương thành số thực để so sánh trùng lặp.
  /// Trả về -1 nếu không thể phân tích (VD: "Oneshot").
  static double _parseChapterNumber(String filename) {
    final info = _parseFilename(filename);
    return info.value == double.infinity ? -1 : info.value;
  }

  static const String _numberPattern = r'([0-9]+)(\.[0-9]+)?(\.?[a-z]+)?';
  static final _unwanted = RegExp(
    r'\b(?:v|ver|vol|version|volume|season|s)[^a-z]?[0-9]+',
    caseSensitive: false,
  );
  // Regex nhận diện tiền tố chương bằng cả Tiếng Anh và Tiếng Việt
  static final _basic = RegExp(
    r'(?:ch\.|chap\.|chapter\.|c\.|ch|chap|chapter|c|chương|tập|hồi)\s*' +
        _numberPattern,
    caseSensitive: false,
  );
  // Regex tìm số thuần túy khi không có tiền tố
  static final _number = RegExp(_numberPattern, caseSensitive: false);
  // Regex loại bỏ khoảng trắng trước các từ khóa đặc biệt
  static final _unwantedWhiteSpace = RegExp(
    r'\s(?=extra|special|omake)',
    caseSensitive: false,
  );

  /// Phân tích tên file thô thành _ParseInfo chứa số chương dạng float.
  static _ParseInfo _parseFilename(String filename) {
    String cleanName = filename.toLowerCase();
    // Chuẩn hóa ký tự ngăn cách
    cleanName = cleanName.replaceAll(',', '.').replaceAll('-', '.');
    // Bỏ khoảng trắng trước Extra/Special/Omake để không bị nhận nhầm thành 2 từ
    cleanName = cleanName.replaceAll(_unwantedWhiteSpace, '');
    // Kiểm tra xem có phải chương đặc biệt không
    bool isExtra =
        cleanName.contains('extra') ||
        cleanName.contains('omake') ||
        cleanName.contains('special');
    // Loại bỏ thông tin Volume để không nhầm số Vol với số Chapter
    String nameWithoutVolume = cleanName.replaceAll(_unwanted, '');

    // Thử khớp có tiền tố (ch., chương...) trên chuỗi đã lọc Volume
    var match = _basic.firstMatch(nameWithoutVolume);
    if (match != null) return _getChapterNumberFromMatch(match, isExtra);

    // Thử tìm số thuần túy
    match = _number.firstMatch(nameWithoutVolume);
    if (match != null) return _getChapterNumberFromMatch(match, isExtra);

    // Thử lại trên chuỗi gốc (đề phòng volume bị xóa lầm mất số chapter)
    match = _basic.firstMatch(cleanName);
    if (match != null) return _getChapterNumberFromMatch(match, isExtra);

    match = _number.firstMatch(cleanName);
    if (match != null) return _getChapterNumberFromMatch(match, isExtra);

    // Không phân tích được (VD: "Oneshot") -> trả về infinity
    return _ParseInfo(value: double.infinity, isExtra: isExtra);
  }

  /// Trích xuất số chương từ kết quả Regex và cộng phần phụ (thập phân/hậu tố).
  static _ParseInfo _getChapterNumberFromMatch(RegExpMatch match, bool extra) {
    double initial = double.parse(match.group(1)!);
    String? subDecimal = match.group(2); // Phần thập phân VD: ".5"
    String? subAlpha = match.group(3); // Hậu tố chữ cái VD: "a", "extra"
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

  /// Chuyển hậu tố chữ cái thành số thập phân nhỏ (a=0.1, b=0.2...) để sắp xếp phân biệt.
  static double _parseAlphaPostFix(String char) {
    int code = char.codeUnitAt(0);
    int aCode = 'a'.codeUnitAt(0);
    int number = code - (aCode - 1); // a=1, b=2, c=3...
    if (number >= 10) return 0.0; // Chữ cái ngoài phạm vi -> bỏ qua
    return number / 10.0;
  }
}

/// Class nội bộ lưu kết quả phân tích tên chương (chỉ dùng trong ChapterUtils).
class _ParseInfo {
  final double value; // Số chương dưới dạng float
  final bool isExtra; // Có phải chương Extra/Oneshot không
  _ParseInfo({required this.value, required this.isExtra});
}
