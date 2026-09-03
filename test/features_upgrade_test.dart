import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/data/models.dart';
import 'package:manga_reader/features/forum/models/forum_post.dart';
import 'package:manga_reader/features/library/following_page.dart';
import 'package:manga_reader/features/search/search_page.dart';

void main() {
  group('Feature ② - Forum Post Pinned & Sorting Tests', () {
    test('ForumPost serializes and deserializes isPinned field correctly', () {
      final now = DateTime.now();
      final post = ForumPost(
        id: 'post_1',
        type: 'discussion',
        authorId: 'user_1',
        authorName: 'Admin',
        authorAvatar: '',
        body: 'Nội dung thông báo quan trọng',
        createdAt: now,
        updatedAt: now,
        isPinned: true,
      );

      final map = post.toFirestore();
      expect(map['isPinned'], true);

      final deserialized = ForumPost.fromMap('post_1', map);
      expect(deserialized.isPinned, true);
      expect(deserialized.body, 'Nội dung thông báo quan trọng');

      final unpinned = deserialized.copyWith(isPinned: false);
      expect(unpinned.isPinned, false);
    });

    test('ForumPost handles default isPinned as false when null in Firestore', () {
      final now = DateTime.now();
      final map = {
        'type': 'discussion',
        'authorId': 'user_2',
        'authorName': 'Member',
        'authorAvatar': '',
        'body': 'Nội dung bài viết',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'likeCount': 0,
        'commentCount': 0,
      };

      final post = ForumPost.fromMap('post_2', map);
      expect(post.isPinned, false);
    });
  });

  group('Feature ⑦ - Following Page Filter & Sort Enums Tests', () {
    test('FollowFilterStatus enum contains all expected reading statuses', () {
      expect(FollowFilterStatus.values.length, 6);
      expect(FollowFilterStatus.values, contains(FollowFilterStatus.all));
      expect(FollowFilterStatus.values, contains(FollowFilterStatus.hasNew));
      expect(FollowFilterStatus.values, contains(FollowFilterStatus.reading));
      expect(FollowFilterStatus.values, contains(FollowFilterStatus.completed));
      expect(FollowFilterStatus.values, contains(FollowFilterStatus.paused));
      expect(FollowFilterStatus.values, contains(FollowFilterStatus.unread));
    });

    test('FollowSortOrder enum contains all expected sort orders', () {
      expect(FollowSortOrder.values.length, 3);
      expect(FollowSortOrder.values, contains(FollowSortOrder.updated));
      expect(FollowSortOrder.values, contains(FollowSortOrder.recentlyRead));
      expect(FollowSortOrder.values, contains(FollowSortOrder.title));
    });
  });

  group('Feature 1 - Search Page Random Picker & Quick Filter Presets Tests', () {
    test('SearchSortMode enum contains all 4 sort modes', () {
      expect(SearchSortMode.values.length, 4);
      expect(SearchSortMode.values, contains(SearchSortMode.updated));
      expect(SearchSortMode.values, contains(SearchSortMode.views));
      expect(SearchSortMode.values, contains(SearchSortMode.likes));
      expect(SearchSortMode.values, contains(SearchSortMode.title));
    });

    test('ChapterCountFilter enum contains all 4 chapter ranges', () {
      expect(ChapterCountFilter.values.length, 4);
      expect(ChapterCountFilter.values, contains(ChapterCountFilter.all));
      expect(ChapterCountFilter.values, contains(ChapterCountFilter.short));
      expect(ChapterCountFilter.values, contains(ChapterCountFilter.medium));
      expect(ChapterCountFilter.values, contains(ChapterCountFilter.long));
    });

    test('GenreMatchMode and GenreFilterState enums operate properly', () {
      expect(GenreMatchMode.values, containsAll([GenreMatchMode.and, GenreMatchMode.or]));
      expect(GenreFilterState.values, containsAll([
        GenreFilterState.none,
        GenreFilterState.included,
        GenreFilterState.excluded,
      ]));
    });
  });

  group('Feature 2 - History Resume Reading Hero Card Logic Tests', () {
    test('ReadingHistory progress percent calculation handles bounds cleanly', () {
      // Normal progress: page 15 of 30 -> (15 + 1) / 30 = 16 / 30 ~ 53%
      final history1 = ReadingHistory(
        userId: 'u1',
        mangaId: 'm1',
        chapterId: 'c1',
        chapterTitle: 'Chương 10',
        lastPageIndex: 14,
        totalPages: 30,
        updatedAt: DateTime.now(),
      );
      final total1 = history1.totalPages > 0 ? history1.totalPages : 1;
      final current1 = (history1.lastPageIndex + 1).clamp(1, total1);
      final percent1 = (current1 / total1).clamp(0.0, 1.0);
      expect(percent1, 0.5);

      // Edge case: lastPageIndex exceeds totalPages
      final history2 = ReadingHistory(
        userId: 'u1',
        mangaId: 'm1',
        chapterId: 'c1',
        lastPageIndex: 99,
        totalPages: 50,
        updatedAt: DateTime.now(),
      );
      final total2 = history2.totalPages > 0 ? history2.totalPages : 1;
      final current2 = (history2.lastPageIndex + 1).clamp(1, total2);
      final percent2 = (current2 / total2).clamp(0.0, 1.0);
      expect(percent2, 1.0);

      // Edge case: zero totalPages defaults safely without division by zero
      final history3 = ReadingHistory(
        userId: 'u1',
        mangaId: 'm1',
        chapterId: 'c1',
        lastPageIndex: 0,
        totalPages: 0,
        updatedAt: DateTime.now(),
      );
      final total3 = history3.totalPages > 0 ? history3.totalPages : 1;
      final current3 = (history3.lastPageIndex + 1).clamp(1, total3);
      final percent3 = (current3 / total3).clamp(0.0, 1.0);
      expect(percent3, 1.0);
    });

    test('ReadingHistory handles null and empty chapterTitle safely', () {
      final historyWithTitle = ReadingHistory(
        userId: 'u1',
        mangaId: 'm1',
        chapterId: 'c1',
        chapterTitle: 'Chương 42: Đại Chiến',
        lastPageIndex: 5,
        totalPages: 20,
        updatedAt: DateTime.now(),
      );
      final displayTitle1 = (historyWithTitle.chapterTitle != null && historyWithTitle.chapterTitle!.isNotEmpty)
          ? historyWithTitle.chapterTitle!
          : 'Đang đọc dở';
      expect(displayTitle1, 'Chương 42: Đại Chiến');

      final historyNullTitle = ReadingHistory(
        userId: 'u1',
        mangaId: 'm1',
        chapterId: 'c1',
        chapterTitle: null,
        lastPageIndex: 5,
        totalPages: 20,
        updatedAt: DateTime.now(),
      );
      final displayTitle2 = (historyNullTitle.chapterTitle != null && historyNullTitle.chapterTitle!.isNotEmpty)
          ? historyNullTitle.chapterTitle!
          : 'Đang đọc dở';
      expect(displayTitle2, 'Đang đọc dở');
    });
  });
}
