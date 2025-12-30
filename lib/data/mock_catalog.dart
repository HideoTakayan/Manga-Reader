import 'package:manga_reader/data/models.dart';

class MockCatalog {
  // ===============================
  // 🧾 Danh sách truyện
  // ===============================
  static final List<Comic> _comics = [
    Comic(
      id: 'op',
      title: 'Đồ Đệ Của Ta Đều Là Trùm Phản Diện',
      coverUrl:
          'https://www.nettruyenup.vn/images/comics/do-de-cua-ta-deu-la-dai-phan-phai.jpg?width=720&q=80',
      author: 'Tác giả A',
      description:
          'Hài hước – phiêu lưu. Nhân vật chính thu nhận đồ đệ, mỗi đồ đệ đều trở thành trùm phản diện khiến thầy đau đầu. Một câu chuyện đầy châm biếm và bất ngờ giữa thiện – ác.',
    ),
    Comic(
      id: 'bd',
      title: 'Đại Quản Gia Là Ma Hoàng',
      coverUrl:
          'https://www.nettruyenup.vn/images/comics/dai-quan-gia-la-ma-hoang.jpg',
      author: 'Đang cập nhật',
      description: 'Đại Quản Gia Là Ma Hoàng..',
    ),
    Comic(
      id: 'mw',
      title: 'Thiết Huyết Kiếm Sĩ Hồi Quy',
      coverUrl:
          'https://www.nettruyenup.vn/images/comics/thiet-huyet-kiem-si-hoi-quy.jpg',
      author: 'Đang cập nhật',
      description:
          'Thiết Huyết Kiếm Sĩ Hồi Quy là một trong những bộ truyện tranh nổi tiếng thuộc thể loại Action, Fantasy, Manhwa, Truyện Màu, Webtoon, Tu Tiên...',
    ),
    Comic(
      id: 'ha',
      title: 'Học Viện Siêu Anh Hùng',
      coverUrl: 'https://cdn.myanimelist.net/images/anime/10/78745.jpg',
      author: 'Kohei Horikoshi',
      description:
          'Thế giới nơi phần lớn con người đều có siêu năng lực – “quirk”. Câu chuyện theo chân Midoriya – một cậu bé không có năng lực nhưng mơ ước trở thành anh hùng vĩ đại.',
    ),
    Comic(
      id: 'onepiece',
      title: 'Đảo Hải Tặc – One Piece',
      coverUrl:
          'https://i.postimg.cc/1zQ7W9M8/14728-dao-hai-tac-one-piece-1.jpg',
      author: 'Eiichiro Oda',
      description:
          'Theo chân Monkey D. Luffy – cậu bé có cơ thể cao su – cùng đồng đội lên đường tìm kho báu One Piece và trở thành Vua Hải Tặc huyền thoại.',
    ),
    Comic(
      id: 'chainsaw',
      title: 'Thợ Săn Quỷ – Chainsaw Man',
      coverUrl:
          'https://i.postimg.cc/pLZc1wSf/14734-tho-san-quy-chainsaw-man-1.jpg',
      author: 'Tatsuki Fujimoto',
      description:
          'Denji – một chàng trai nghèo hợp nhất với quỷ cưa máy và trở thành thợ săn quỷ. Câu chuyện đẫm máu, dữ dội nhưng đầy chiều sâu cảm xúc.',
    ),
  ];

  // ===============================
  // 📚 Danh sách chapter
  // ===============================
  static final Map<String, List<Chapter>> _chaptersByComic = {
    'op': [
      Chapter(
        id: 'op-1',
        comicId: 'op',
        name: 'Chapter 1: Khởi đầu',
        number: 1,
      ),
      Chapter(
        id: 'op-2',
        comicId: 'op',
        name: 'Chapter 2: Cuộc chạm trán',
        number: 2,
      ),
      Chapter(
        id: 'op-3',
        comicId: 'op',
        name: 'Chapter 3: Đồ đệ đầu tiên',
        number: 3,
      ),
    ],
    'bd': [
      Chapter(
        id: 'bd-1',
        comicId: 'bd',
        name: 'Chapter 1: Tỉnh giấc',
        number: 1,
      ),
      Chapter(
        id: 'bd-2',
        comicId: 'bd',
        name: 'Chapter 2: Thử thách đầu tiên',
        number: 2,
      ),
    ],
    'mw': [Chapter(id: 'mw-1', comicId: 'mw', name: 'Chapter 1', number: 1)],
    'ha': [
      Chapter(
        id: 'ha-1',
        comicId: 'ha',
        name: 'Chương 1: Giấc mơ anh hùng',
        number: 1,
      ),
      Chapter(
        id: 'ha-2',
        comicId: 'ha',
        name: 'Chương 2: Quyết tâm của Midoriya',
        number: 2,
      ),
    ],
    'onepiece': [
      Chapter(
        id: 'onepiece-1',
        comicId: 'onepiece',
        name: 'Chương 1: Tôi là Luffy!',
        number: 1,
      ),
      Chapter(
        id: 'onepiece-2',
        comicId: 'onepiece',
        name: 'Chương 2: Ra khơi!',
        number: 2,
      ),
    ],
    'chainsaw': [
      Chapter(
        id: 'chainsaw-1',
        comicId: 'chainsaw',
        name: 'Chương 1: Thợ săn quỷ Denji',
        number: 1,
      ),
      Chapter(
        id: 'chainsaw-2',
        comicId: 'chainsaw',
        name: 'Chương 2: Cưa máy và máu',
        number: 2,
      ),
    ],
  };

  // ===============================
  // 🖼️ Trang ảnh theo chapter
  // ===============================
  static final Map<String, List<PageImage>> _pagesByChapter = {
    'op-1': [
      ...const [
        'https://cdn.truyennganhay.net/90htr/content/281/1898306/2025-04-21/h2nBJa1ilc',
        'https://cdn.truyennganhay.net/90htr/content/281/1898306/2025-04-21/IA1963TnZG',
        'https://cdn.truyennganhay.net/90htr/content/281/1898306/2025-04-21/YC3MJhomul',
        'https://cdn.truyennganhay.net/90htr/content/281/1898306/2025-04-21/QcQG8TIqpO',
      ].asMap().entries.map(
        (e) => PageImage(
          id: 'op1-${e.key}',
          chapterId: 'op-1',
          index: e.key,
          imageUrl: e.value,
        ),
      ),
    ],
    'bd-1': List.generate(
      4,
      (i) => PageImage(
        id: 'bd1-$i',
        chapterId: 'bd-1',
        index: i,
        imageUrl: 'https://picsum.photos/seed/bd1_$i/720/1280.webp',
      ),
    ),
  };

  // ===============================
  // 💬 Bình luận theo truyện
  // ===============================
  static final Map<String, List<Comment>> _commentsByComic = {
    'op': [
      Comment(
        id: 'op-c1',
        comicId: 'op',
        userId: 'u1',
        userName: 'MangaFan123',
        userAvatar: 'https://i.pravatar.cc/40?img=1',
        content: 'Truyện hài hước vl! Đồ đệ nào cũng bá đạo',
        likes: 28,
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        isLiked: false,
      ),
      Comment(
        id: 'op-c2',
        comicId: 'op',
        userId: 'u2',
        userName: 'OtakuGirl',
        userAvatar: 'https://i.pravatar.cc/40?img=2',
        content: 'Thầy giáo khổ quá, chap mới đâu rồi?',
        likes: 15,
        createdAt: DateTime.now().subtract(const Duration(hours: 6)),
        isLiked: true,
      ),
    ],
    'chainsaw': [
      Comment(
        id: 'chainsaw-c1',
        comicId: 'chainsaw',
        userId: 'u4',
        userName: 'DenjiFan',
        userAvatar: 'https://i.pravatar.cc/40?img=4',
        content: 'Máu me kinh dị thật sự! Fujimoto đỉnh cao',
        likes: 52,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        isLiked: false,
      ),
    ],
  };

  // ===============================
  // ⚙️ API mô phỏng
  // ===============================
  static List<Comic> comics() => _comics;

  static Comic? comicById(String id) {
    try {
      return _comics.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  static List<Chapter> chaptersOf(String comicId) =>
      _chaptersByComic[comicId] ?? const [];

  static List<PageImage> pagesOf(String chapterId) =>
      _pagesByChapter[chapterId] ?? const [];

  static String? nextChapterIdOf(String chapterId) {
    final parts = chapterId.split('-');
    if (parts.length < 2) return null;
    final comicId = parts.first;
    final currentNo = int.tryParse(parts.last) ?? 0;

    final chaps = chaptersOf(comicId);
    chaps.sort((a, b) => a.number.compareTo(b.number));
    for (final c in chaps) {
      if (c.number > currentNo) return c.id;
    }
    return null;
  }

  static String? prevChapterIdOf(String chapterId) {
    final parts = chapterId.split('-');
    if (parts.length < 2) return null;
    final comicId = parts.first;
    final currentNo = int.tryParse(parts.last) ?? 0;

    final chaps = chaptersOf(comicId);
    chaps.sort((a, b) => a.number.compareTo(b.number));
    String? prev;
    for (final c in chaps) {
      if (c.number < currentNo) prev = c.id;
      if (c.number >= currentNo) break;
    }
    return prev;
  }

  // ===============================
  // 💬 BÌNH LUẬN – API
  // ===============================

  static void addComment(Comment comment) {
    final list = _commentsByComic.putIfAbsent(comment.comicId, () => []);
    list.insert(0, comment);
  }

  static List<Comment> commentsOf(String comicId) {
    final list = _commentsByComic[comicId] ?? [];
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.from(list);
  }

  static void updateCommentLike(String commentId, bool isLiked) {
    for (final entry in _commentsByComic.entries) {
      final index = entry.value.indexWhere((c) => c.id == commentId);
      if (index != -1) {
        final comment = entry.value[index];
        entry.value[index] = comment.copyWith(
          likes: isLiked ? comment.likes + 1 : comment.likes - 1,
          isLiked: isLiked,
        );
        break;
      }
    }
  }

  // ===============================
  // 👁️ LƯỢT XEM
  // ===============================
  static int viewsOf(String comicId) {
    final views = {
      'op': 12500,
      'bd': 8900,
      'mw': 5000,
      'ha': 15200,
      'onepiece': 98500,
      'chainsaw': 22100,
    };
    return views[comicId] ?? 0;
  }
}
