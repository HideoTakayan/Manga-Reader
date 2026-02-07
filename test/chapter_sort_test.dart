import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/core/utils/chapter_sort_helper.dart';
import 'package:manga_reader/data/models_cloud.dart';

void main() {
  group('ChapterSortHelper Tests', () {
    // Helper to create dummy chapters
    CloudChapter createChapter(String id, String title) {
      return CloudChapter(
        id: id,
        title: title,
        fileId: '',
        fileType: '',
        uploadedAt: DateTime.now(),
        viewCount: 0,
      );
    }

    test('Basic Parsing', () {
      final chapters = [
        createChapter('1', 'Chapter 2'),
        createChapter('2', 'Chapter 1'),
        createChapter('3', 'Chapter 10'),
      ];
      final sorted = ChapterSortHelper.sort(chapters);
      expect(sorted[0].title, contains('1')); // Chapter 1
      expect(sorted[1].title, contains('2')); // Chapter 2
      expect(sorted[2].title, contains('10')); // Chapter 10
    });

    test('Decimal Parsing', () {
      final chapters = [
        createChapter('1', 'Chapter 10.5'),
        createChapter('2', 'Chapter 10'),
        createChapter('3', 'Chapter 10.1'),
      ];
      final sorted = ChapterSortHelper.sort(chapters);
      // Expected: 10, 10.1, 10.5
      expect(sorted[0].title, contains('10'));
      expect(sorted[1].title, contains('10.1'));
      expect(sorted[2].title, contains('10.5'));
    });

    test('Volume Mixed (The Bug)', () {
      final chapters = [
        createChapter('1', 'Vol 1 Ch 5'), // Should be 5
        createChapter('2', 'Vol 2 Ch 1'), // Should be 1
      ];
      final sorted = ChapterSortHelper.sort(chapters);

      // Logic mới (Mihon): Tìm "Ch 1" -> 1. Tìm "Ch 5" -> 5.
      // Vậy 1 < 5.
      // Thứ tự: Chapter 1 (Vol 2) -> Chapter 5 (Vol 1).
      // ID: 2 -> 1.
      expect(sorted[0].id, '2');
      expect(sorted[1].id, '1');
      // ignore: avoid_print
      print('Sorted Volume Mixed: ${sorted.map((e) => e.title).toList()}');
    });

    test('Complex Alpha Parsing', () {
      final chapters = [
        createChapter('1', 'Chapter 10a'), // Should be 10.1
        createChapter('2', 'Chapter 10'), // 10.0
      ];
      final sorted = ChapterSortHelper.sort(chapters);

      // Expected: 10.0 < 10.1
      // ID: 2 -> 1
      expect(sorted[0].id, '2');
      expect(sorted[1].id, '1');
      // ignore: avoid_print
      print('Sorted Alpha: ${sorted.map((e) => e.title).toList()}');
    });
  });
}
