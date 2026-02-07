import 'dart:convert';

/// --------------------
/// 📚 Manga Model
/// --------------------
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Manga && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// --------------------
/// 📖 Chapter Model
/// --------------------
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
    'comicId': mangaId, // Backward compatibility
    'name': name,
    'number': number,
  };

  Map<String, dynamic> toMap() => toJson();

  factory Chapter.fromMap(Map<String, dynamic> map) => Chapter.fromJson(map);

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
      'comicId': mangaId, // Backward compatibility
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

  Comment toggleLike() =>
      copyWith(likes: isLiked ? likes - 1 : likes + 1, isLiked: !isLiked);

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
      'comicId': mangaId, // Backward compatibility for DB/Cloud
      'chapterId': chapterId,
      'chapterTitle': chapterTitle,
      'lastPageIndex': lastPageIndex,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }
}
