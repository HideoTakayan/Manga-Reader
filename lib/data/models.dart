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
      replies: json['replies'] is List
          ? (json['replies'] as List)
                .map((e) => Comment.fromJson(e as Map<String, dynamic>))
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
  final DateTime updatedAt;

  const ReadingHistory({
    required this.userId,
    required this.mangaId,
    required this.chapterId,
    this.chapterTitle,
    required this.lastPageIndex,
    required this.updatedAt,
  });

  factory ReadingHistory.fromMap(Map<String, dynamic> map) {
    return ReadingHistory(
      userId: map['userId'] as String? ?? 'guest',
      mangaId: (map['mangaId'] ?? map['comicId']) as String,
      chapterId: map['chapterId'] as String,
      chapterTitle: map['chapterTitle'] as String?,
      lastPageIndex: map['lastPageIndex'] as int? ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int),
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
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }
}
