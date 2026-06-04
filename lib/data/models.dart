import 'dart:convert';

/// --------------------
/// 📚 Manga Model
/// --------------------
/// Model đại diện cho một bộ truyện lưu trong SQLite cục bộ.
/// Dùng để cache thông tin truyện dưới dạng bảng `comics` trong file comics.db.
class Manga {
  final String id;
  final String title;
  final String coverUrl;
  final String author;
  final String description;
  final List<String> genres;

  const Manga({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.author,
    required this.description,
    this.genres = const [],
  });

  // === JSON ===
  /// Tạo đối tượng Manga từ JSON (VD: đọc từ catalog.json trên Google Drive).
  factory Manga.fromJson(Map<String, dynamic> json) {
    return Manga(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      genres: _parseGenres(json['genres']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'coverUrl': coverUrl,
    'author': author,
    'description': description,
    'genres': genres,
  };

  // === SQLite ===
  /// Chuyển đối tượng Manga sang Map để lưu vào SQLite.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'coverUrl': coverUrl,
      'author': author,
      'description': description,
      'genres': jsonEncode(genres),
    };
  }

  /// Tạo đối tượng Manga từ Map đọc ra từ SQLite.
  factory Manga.fromMap(Map<String, dynamic> map) {
    final rawGenres = map['genres'];
    return Manga(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      coverUrl: map['coverUrl']?.toString() ?? '',
      author: map['author']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      genres: _parseGenres(rawGenres),
    );
  }

  /// Phân tích trường genres từ nhiều dạng dữ liệu khác nhau:
  /// - List (JSON array) → dùng thẳng
  /// - String JSON → decode rồi dùng
  /// - String phân cách bởi dấu phẩy/|/; → split rồi dùng
  static List<String> _parseGenres(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
      return raw
          .split(RegExp(r'[,\|;]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return [];
  }

  /// Tạo bản sao có cập nhật một số trường (Immutable pattern).
  Manga copyWith({
    String? id,
    String? title,
    String? coverUrl,
    String? author,
    String? description,
    List<String>? genres,
  }) {
    return Manga(
      id: id ?? this.id,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      author: author ?? this.author,
      description: description ?? this.description,
      genres: genres ?? this.genres,
    );
  }

  /// Hai Manga được coi là giống nhau nếu cùng ID.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Manga && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode; // Dùng id làm khóa hash
}

/// --------------------
/// 📖 Chapter Model
/// --------------------
/// Model đại diện cho một chương truyện lưu trong SQLite cục bộ.
/// Bảng `chapters` trong comics.db, liên kết với bảng `comics` qua `mangaId`.
class Chapter {
  final String id;
  final String mangaId;
  final String name;
  final int number;

  const Chapter({
    required this.id,
    required this.mangaId,
    required this.name,
    required this.number,
  });

  /// Tạo Chapter từ JSON. Hỗ trợ cả key `mangaId` và `comicId` để tương thích ngược.
  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
    id: json['id']?.toString() ?? '',
    mangaId: (json['mangaId'] ?? json['comicId'])?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    number: (json['number'] is int)
        ? json['number']
        : int.tryParse(json['number']?.toString() ?? '0') ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'mangaId': mangaId,
    'comicId': mangaId, // Khả năng tương thích ngược
    'name': name,
    'number': number,
  };

  Map<String, dynamic> toMap() => toJson();

  factory Chapter.fromMap(Map<String, dynamic> map) => Chapter.fromJson(map);

  /// Hai Chapter được coi là giống nhau nếu cùng ID.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Chapter && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// --------------------
/// 💬 Comment Model
/// --------------------
/// Model đại diện cho bình luận của người dùng.
/// Hỗ trợ cả reply (bình luận lồng nhau) và like/unlike.
class Comment {
  final String id;
  final String mangaId;
  final String userId;
  final String userName;
  final String userAvatar;
  final String content;
  final int likes;
  final DateTime createdAt;
  final bool isLiked;
  final List<Comment>? replies;

  const Comment({
    required this.id,
    required this.mangaId,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.content,
    this.likes = 0,
    required this.createdAt,
    this.isLiked = false,
    this.replies,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    final rawReplies = json['replies'];
    return Comment(
      id: json['id']?.toString() ?? '',
      mangaId: (json['mangaId'] ?? json['comicId'])?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      userName: json['userName']?.toString() ?? 'Ẩn danh',
      userAvatar:
          json['userAvatar']?.toString() ?? 'https://i.pravatar.cc/150?u=anon',
      content: json['content']?.toString() ?? '',
      likes: json['likes'] is int
          ? json['likes']
          : int.tryParse(json['likes']?.toString() ?? '0') ?? 0,
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt']) ?? DateTime.now()
          : DateTime.now(),
      isLiked: json['isLiked'] == true,
      replies: rawReplies is List
          ? rawReplies
                .whereType<Map<String, dynamic>>()
                .map(Comment.fromJson)
                .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final map = {
      'id': id,
      'mangaId': mangaId,
      'comicId': mangaId, // Khả năng tương thích ngược
      'userId': userId,
      'userName': userName,
      'userAvatar': userAvatar,
      'content': content,
      'likes': likes,
      'createdAt': createdAt.toIso8601String(),
      'isLiked': isLiked,
    };
    if (replies != null) {
      map['replies'] = replies!.map((r) => r.toJson()).toList();
    }
    return map;
  }

  /// Bật/tắt trạng thái like: tăng/giảm `likes` và đảo `isLiked`.
  Comment toggleLike() =>
      copyWith(likes: isLiked ? likes - 1 : likes + 1, isLiked: !isLiked);

  /// Thêm một reply vào danh sách replies của comment này.
  Comment addReply(Comment reply) {
    final newReplies = [...?replies, reply];
    return copyWith(replies: newReplies);
  }

  Comment copyWith({
    String? id,
    String? mangaId,
    String? userId,
    String? userName,
    String? userAvatar,
    String? content,
    int? likes,
    DateTime? createdAt,
    bool? isLiked,
    List<Comment>? replies,
  }) {
    return Comment(
      id: id ?? this.id,
      mangaId: mangaId ?? this.mangaId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      content: content ?? this.content,
      likes: likes ?? this.likes,
      createdAt: createdAt ?? this.createdAt,
      isLiked: isLiked ?? this.isLiked,
      replies: replies ?? this.replies,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Comment && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// --------------------
/// 🕰️ Reading History Model
/// --------------------
/// Model lưu lịch sử đọc truyện của người dùng trong SQLite (bảng `history`).
/// Dùng để nhớ người dùng đang đọc dở chương nào, trang mấy.
class ReadingHistory {
  final String userId;
  final String mangaId;
  final String chapterId;
  final String? chapterTitle;
  final int lastPageIndex;
  final int totalPages;
  final DateTime updatedAt;

  const ReadingHistory({
    required this.userId,
    required this.mangaId,
    required this.chapterId,
    this.chapterTitle,
    required this.lastPageIndex,
    this.totalPages = 1,
    required this.updatedAt,
  });

  factory ReadingHistory.fromMap(Map<String, dynamic> map) {
    return ReadingHistory(
      userId: map['userId']?.toString() ?? 'guest',
      mangaId: (map['mangaId'] ?? map['comicId'])?.toString() ?? '',
      chapterId: map['chapterId']?.toString() ?? '',
      chapterTitle: map['chapterTitle']?.toString(),
      lastPageIndex: _readInt(map['lastPageIndex']),
      totalPages: _readInt(map['totalPages']) > 0
          ? _readInt(map['totalPages'])
          : 1,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        _readInt(map['updatedAt']),
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'mangaId': mangaId,
      'comicId': mangaId, // Khả năng tương thích ngược cho CSDL/Đám mây
      'chapterId': chapterId,
      'chapterTitle': chapterTitle,
      'lastPageIndex': lastPageIndex,
      'totalPages': totalPages,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class ReaderProgress {
  final String mangaId;
  final String chapterId;
  final int pageIndex;
  final double scrollOffset;
  final String? epubCfi;
  final double progressPercent;
  final DateTime updatedAt;

  const ReaderProgress({
    required this.mangaId,
    required this.chapterId,
    this.pageIndex = 0,
    this.scrollOffset = 0,
    this.epubCfi,
    this.progressPercent = 0,
    required this.updatedAt,
  });

  factory ReaderProgress.fromMap(Map<String, dynamic> map) {
    return ReaderProgress(
      mangaId: map['mangaId']?.toString() ?? '',
      chapterId: map['chapterId']?.toString() ?? '',
      pageIndex: _readInt(map['pageIndex']),
      scrollOffset: _readDouble(map['scrollOffset']),
      epubCfi: map['epubCfi']?.toString(),
      progressPercent: _readDouble(map['progressPercent']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        _readInt(map['updatedAt']),
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'mangaId': mangaId,
      'chapterId': chapterId,
      'pageIndex': pageIndex,
      'scrollOffset': scrollOffset,
      'epubCfi': epubCfi,
      'progressPercent': progressPercent,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _readDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class ReadingActivity {
  final String id;
  final String userId;
  final String mangaId;
  final String chapterId;
  final String? chapterTitle;
  final int pageIndex;
  final int totalPages;
  final double progressPercent;
  final String dateKey;
  final DateTime readAt;

  const ReadingActivity({
    required this.id,
    required this.userId,
    required this.mangaId,
    required this.chapterId,
    this.chapterTitle,
    this.pageIndex = 0,
    this.totalPages = 1,
    this.progressPercent = 0,
    required this.dateKey,
    required this.readAt,
  });

  factory ReadingActivity.create({
    required String userId,
    required String mangaId,
    required String chapterId,
    String? chapterTitle,
    int pageIndex = 0,
    int totalPages = 1,
    double progressPercent = 0,
    DateTime? readAt,
  }) {
    final resolvedReadAt = readAt ?? DateTime.now();
    final key = dateKeyFor(resolvedReadAt);
    return ReadingActivity(
      id: '$userId|$mangaId|$chapterId|$key',
      userId: userId,
      mangaId: mangaId,
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      pageIndex: pageIndex,
      totalPages: totalPages > 0 ? totalPages : 1,
      progressPercent: progressPercent.clamp(0, 1).toDouble(),
      dateKey: key,
      readAt: resolvedReadAt,
    );
  }

  factory ReadingActivity.fromMap(Map<String, dynamic> map) {
    return ReadingActivity(
      id: map['id']?.toString() ?? '',
      userId: map['userId']?.toString() ?? 'guest',
      mangaId: map['mangaId']?.toString() ?? '',
      chapterId: map['chapterId']?.toString() ?? '',
      chapterTitle: map['chapterTitle']?.toString(),
      pageIndex: _readInt(map['pageIndex']),
      totalPages: _readInt(map['totalPages']) > 0
          ? _readInt(map['totalPages'])
          : 1,
      progressPercent: _readDouble(map['progressPercent']).clamp(0, 1),
      dateKey: map['dateKey']?.toString() ?? '',
      readAt: DateTime.fromMillisecondsSinceEpoch(_readInt(map['readAt'])),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'mangaId': mangaId,
      'chapterId': chapterId,
      'chapterTitle': chapterTitle,
      'pageIndex': pageIndex,
      'totalPages': totalPages,
      'progressPercent': progressPercent,
      'dateKey': dateKey,
      'readAt': readAt.millisecondsSinceEpoch,
    };
  }

  static String dateKeyFor(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _readDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class ReaderBookmark {
  final String id;
  final String mangaId;
  final String chapterId;
  final int pageIndex;
  final double scrollOffset;
  final String? epubCfi;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ReaderBookmark({
    required this.id,
    required this.mangaId,
    required this.chapterId,
    this.pageIndex = 0,
    this.scrollOffset = 0,
    this.epubCfi,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReaderBookmark.fromMap(Map<String, dynamic> map) {
    return ReaderBookmark(
      id: map['id']?.toString() ?? '',
      mangaId: map['mangaId']?.toString() ?? '',
      chapterId: map['chapterId']?.toString() ?? '',
      pageIndex: _readInt(map['pageIndex']),
      scrollOffset: _readDouble(map['scrollOffset']),
      epubCfi: map['epubCfi']?.toString(),
      note: map['note']?.toString(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        _readInt(map['createdAt']),
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        _readInt(map['updatedAt']),
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'mangaId': mangaId,
      'chapterId': chapterId,
      'pageIndex': pageIndex,
      'scrollOffset': scrollOffset,
      'epubCfi': epubCfi,
      'note': note,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _readDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
