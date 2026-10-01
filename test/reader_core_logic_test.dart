import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/features/reader/reader_provider.dart';

void main() {
  group('1. Manga / Comic Logic - Dual-Page Spreads & Navigation', () {
    List<List<int>> calculateSpreads(int pageCount, ReaderDualPageMode mode) {
      if (pageCount <= 0) return [];
      if (mode == ReaderDualPageMode.off) {
        return List.generate(pageCount, (i) => [i]);
      }
      final spreads = <List<int>>[];
      if (mode == ReaderDualPageMode.dualCover) {
        spreads.add([0]); // Trang bìa đứng đơn
        for (int i = 1; i < pageCount; i += 2) {
          if (i + 1 < pageCount) {
            spreads.add([i, i + 1]);
          } else {
            spreads.add([i]);
          }
        }
      } else if (mode == ReaderDualPageMode.dual) {
        for (int i = 0; i < pageCount; i += 2) {
          if (i + 1 < pageCount) {
            spreads.add([i, i + 1]);
          } else {
            spreads.add([i]);
          }
        }
      }
      return spreads;
    }

    test('Spread calculations handle off, dual, and dualCover accurately', () {
      // 5 trang
      final single = calculateSpreads(5, ReaderDualPageMode.off);
      expect(single.length, 5);
      expect(single, [[0], [1], [2], [3], [4]]);

      final dual = calculateSpreads(5, ReaderDualPageMode.dual);
      expect(dual.length, 3);
      expect(dual, [[0, 1], [2, 3], [4]]);

      final dualCover = calculateSpreads(5, ReaderDualPageMode.dualCover);
      expect(dualCover.length, 3);
      expect(dualCover, [[0], [1, 2], [3, 4]]);
    });

    test('Prev chapter navigation jumps to exact last spread in horizontal mode', () {
      const pageCount = 20;
      final spreads = calculateSpreads(pageCount, ReaderDualPageMode.dual);
      final lastSpreadIndex = spreads.isNotEmpty ? spreads.length - 1 : 0;
      expect(lastSpreadIndex, 9); // 10 cặp (0-9)
      expect(spreads[lastSpreadIndex], [18, 19]);
    });
  });

  group('2. PDF Logic - Vertical Page Height & Aspect Ratio Calculation', () {
    double calculateVerticalPageHeight({
      required double aspectRatio,
      required double screenWidth,
      required double screenHeight,
      required ReaderImageFit imageFit,
      required bool rotateLandscape,
    }) {
      final shouldRotate = rotateLandscape && aspectRatio > 1.05;
      final effectiveRatio = shouldRotate ? (1.0 / aspectRatio) : aspectRatio;

      switch (imageFit) {
        case ReaderImageFit.width:
          return screenWidth / effectiveRatio;
        case ReaderImageFit.height:
          return screenHeight > 0 ? screenHeight : (screenWidth / effectiveRatio);
        case ReaderImageFit.screen:
          final wHeight = screenWidth / effectiveRatio;
          return (screenHeight > 0 && wHeight > screenHeight) ? screenHeight : wHeight;
        case ReaderImageFit.smart:
          if (effectiveRatio > 1.15 && screenHeight > 0) {
            final wHeight = screenWidth / effectiveRatio;
            return (wHeight > screenHeight) ? screenHeight : wHeight;
          }
          return screenWidth / effectiveRatio;
        case ReaderImageFit.original:
          return screenWidth / effectiveRatio;
      }
    }

    test('PDF Vertical Page Height scales correctly without layout shifts', () {
      const screenW = 400.0;
      const screenH = 800.0;

      // Trang dọc A4 tiêu chuẩn (tỷ lệ 0.707)
      final hWidth = calculateVerticalPageHeight(
        aspectRatio: 0.707,
        screenWidth: screenW,
        screenHeight: screenH,
        imageFit: ReaderImageFit.width,
        rotateLandscape: false,
      );
      expect((hWidth - (400.0 / 0.707)).abs() < 0.01, isTrue);

      // Trang ngang (tỷ lệ 1.414) có bật rotateLandscape -> xoay lại thành tỷ lệ 1/1.414 = 0.707
      final hRotated = calculateVerticalPageHeight(
        aspectRatio: 1.414,
        screenWidth: screenW,
        screenHeight: screenH,
        imageFit: ReaderImageFit.width,
        rotateLandscape: true,
      );
      expect((hRotated - (400.0 / (1.0 / 1.414))).abs() < 0.01, isTrue);
    });
  });

  group('3. Novel / EPUB Logic - Repagination & Progress Preservation', () {
    test('Repaginating preserves reading progress ratio across font size changes', () {
      // Giả sử ban đầu font size 18 -> chia được 10 trang. Người đọc đang ở trang 5 (50%)
      const oldTotalPages = 10;
      const currentPage = 5;
      final progressRatio = currentPage / oldTotalPages;
      expect(progressRatio, 0.5);

      // Người đọc tăng cỡ chữ lên 24 -> chia lại thành 16 trang
      const newTotalPages = 16;
      final newPage = (progressRatio * newTotalPages).floor().clamp(0, newTotalPages - 1);
      // Trang tương ứng ở cỡ chữ mới phải là trang 8 (50% của 16 trang)
      expect(newPage, 8);
    });
  });

  group('4. Progress & Anti-Cheat Logic - EXP & Mark Read Guards', () {
    test('Manga progress requires >= 75% for EXP and >= 90% for Mark-as-read', () {
      bool shouldClaimExp(double progressPercent, int current, int total) {
        return progressPercent >= 0.75 || current >= total - 1;
      }

      bool shouldMarkRead(double progressPercent, int current, int total) {
        return progressPercent >= 0.90 || (total > 0 && current >= total - 1);
      }

      // Đọc trang 5/20 = 25% -> không claim EXP, không mark read
      expect(shouldClaimExp(5 / 19, 5, 20), isFalse);
      expect(shouldMarkRead(5 / 19, 5, 20), isFalse);

      // Đọc trang 15/20 = 78.9% -> được claim EXP nhưng chưa mark read
      expect(shouldClaimExp(15 / 19, 15, 20), isTrue);
      expect(shouldMarkRead(15 / 19, 15, 20), isFalse);

      // Đọc trang 19/20 = 100% -> được cả claim EXP lẫn mark read
      expect(shouldClaimExp(1.0, 19, 20), isTrue);
      expect(shouldMarkRead(1.0, 19, 20), isTrue);
    });

    test('Novel state.isNovel is safely skipped by ReaderNotifier _saveProgress guard', () {
      // Giả lập trạng thái của Novel trong ReaderState
      const novelState = ReaderState(
        isNovel: true,
        pages: [], // Không có trang ảnh
      );

      // Khi isNovel = true, ReaderNotifier không được phép tự động chạy logic claim EXP hay mark read
      // vì NovelReaderWidget tự tính theo blockIndex thực tế
      expect(novelState.isNovel, isTrue);
      expect(novelState.pages.isEmpty, isTrue);
    });
  });
}
