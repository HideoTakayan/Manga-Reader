import 'package:cloud_firestore/cloud_firestore.dart';
import 'forum_poll.dart';

class ForumPost {
  final String id;
  final String type; // 'discussion' or 'manga_share'
  final String authorId;
  final String authorName;
  final String authorAvatar;
  final int authorLevel;
  final String body;
  final String? gifUrl;
  final String? imageUrl;

  // For manga_share type
  final String? sharedMangaId;
  final String? sharedMangaTitle;
  final String? sharedMangaCoverUrl;
  final String? sharedMangaAuthor;

  // Interactive Poll
  final ForumPoll? poll;

  // Dynamic User Hashtags (#skibidi, #review, #spoil, etc.)
  final List<String> tags;

  final int likeCount;
  final int commentCount;
  final int viewCount;
  final int reportCount;
  final bool isDeleted;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  ForumPost({
    required this.id,
    required this.type,
    required this.authorId,
    required this.authorName,
    required this.authorAvatar,
    this.authorLevel = 1,
    required this.body,
    this.gifUrl,
    this.imageUrl,
    this.sharedMangaId,
    this.sharedMangaTitle,
    this.sharedMangaCoverUrl,
    this.sharedMangaAuthor,
    this.poll,
    this.tags = const [],
    this.likeCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.reportCount = 0,
    this.isDeleted = false,
    this.isPinned = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ForumPost.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ForumPost.fromMap(doc.id, data);
  }

  factory ForumPost.fromMap(String id, Map<String, dynamic> data) {
    final bodyStr = _readString(data['body']);
    List<String> parsedTags = [];
    if (data['tags'] is List) {
      parsedTags = (data['tags'] as List)
          .map((e) => e.toString().toLowerCase().trim().replaceAll('#', ''))
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
    }
    if (parsedTags.isEmpty && bodyStr.isNotEmpty) {
      parsedTags = extractHashtags(bodyStr);
    }

    return ForumPost(
      id: id,
      type: _readString(data['type'], fallback: 'discussion'),
      authorId: _readString(data['authorId']),
      authorName: _readString(data['authorName'], fallback: 'Unknown'),
      authorAvatar: _readString(data['authorAvatar']),
      authorLevel: _readInt(data['authorLevel']) > 0 ? _readInt(data['authorLevel']) : 1,
      body: bodyStr,
      gifUrl: _readNullableString(data['gifUrl']),
      imageUrl: _readNullableString(data['imageUrl']),
      sharedMangaId: _readNullableString(data['sharedMangaId']),
      sharedMangaTitle: _readNullableString(data['sharedMangaTitle']),
      sharedMangaCoverUrl: _readNullableString(data['sharedMangaCoverUrl']),
      sharedMangaAuthor: _readNullableString(data['sharedMangaAuthor']),
      poll: data['poll'] is Map<String, dynamic>
          ? ForumPoll.fromMap(data['poll'] as Map<String, dynamic>)
          : null,
      tags: parsedTags,
      likeCount: _readInt(data['likeCount']),
      commentCount: _readInt(data['commentCount']),
      viewCount: _readInt(data['viewCount']),
      reportCount: _readInt(data['reportCount']),
      isDeleted: data['isDeleted'] is bool ? data['isDeleted'] as bool : false,
      isPinned: data['isPinned'] is bool ? data['isPinned'] as bool : false,
      createdAt: _readDateTime(data['createdAt']),
      updatedAt: _readDateTime(data['updatedAt']),
    );
  }

  /// Trích xuất danh sách hashtag từ văn bản (VD: "#skibidi #anime" -> ["skibidi", "anime"])
  static List<String> extractHashtags(String text) {
    final regExp = RegExp(r'#([a-zA-Z0-9_\u00C0-\u1EF9]+)');
    final matches = regExp.allMatches(text);
    final set = <String>{};
    for (final m in matches) {
      final tag = m.group(1)?.toLowerCase().trim();
      if (tag != null && tag.isNotEmpty) {
        set.add(tag);
      }
    }
    return set.toList();
  }

  static String _readString(dynamic value, {String fallback = ''}) =>
      value is String ? value : fallback;

  static String? _readNullableString(dynamic value) =>
      value is String ? value : null;

  static int _readInt(dynamic value) => value is num ? value.toInt() : 0;

  static DateTime _readDateTime(dynamic value) =>
      value is Timestamp ? value.toDate() : DateTime.now();

  ForumPost copyWith({
    String? id,
    String? type,
    String? authorId,
    String? authorName,
    String? authorAvatar,
    int? authorLevel,
    String? body,
    String? gifUrl,
    String? imageUrl,
    String? sharedMangaId,
    String? sharedMangaTitle,
    String? sharedMangaCoverUrl,
    String? sharedMangaAuthor,
    ForumPoll? poll,
    List<String>? tags,
    int? likeCount,
    int? commentCount,
    int? viewCount,
    int? reportCount,
    bool? isDeleted,
    bool? isPinned,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ForumPost(
      id: id ?? this.id,
      type: type ?? this.type,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      authorAvatar: authorAvatar ?? this.authorAvatar,
      authorLevel: authorLevel ?? this.authorLevel,
      body: body ?? this.body,
      gifUrl: gifUrl ?? this.gifUrl,
      imageUrl: imageUrl ?? this.imageUrl,
      sharedMangaId: sharedMangaId ?? this.sharedMangaId,
      sharedMangaTitle: sharedMangaTitle ?? this.sharedMangaTitle,
      sharedMangaCoverUrl: sharedMangaCoverUrl ?? this.sharedMangaCoverUrl,
      sharedMangaAuthor: sharedMangaAuthor ?? this.sharedMangaAuthor,
      poll: poll ?? this.poll,
      tags: tags ?? this.tags,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      viewCount: viewCount ?? this.viewCount,
      reportCount: reportCount ?? this.reportCount,
      isDeleted: isDeleted ?? this.isDeleted,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': type,
      'authorId': authorId,
      'authorName': authorName,
      'authorAvatar': authorAvatar,
      'authorLevel': authorLevel,
      'body': body,
      if (gifUrl != null) 'gifUrl': gifUrl,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (sharedMangaId != null) 'sharedMangaId': sharedMangaId,
      if (sharedMangaTitle != null) 'sharedMangaTitle': sharedMangaTitle,
      if (sharedMangaCoverUrl != null)
        'sharedMangaCoverUrl': sharedMangaCoverUrl,
      if (sharedMangaAuthor != null) 'sharedMangaAuthor': sharedMangaAuthor,
      if (poll != null) 'poll': poll!.toMap(),
      if (tags.isNotEmpty) 'tags': tags,
      'likeCount': likeCount,
      'commentCount': commentCount,
      'viewCount': viewCount,
      'reportCount': reportCount,
      'isDeleted': isDeleted,
      'isPinned': isPinned,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
