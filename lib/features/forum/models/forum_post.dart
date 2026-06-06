import 'package:cloud_firestore/cloud_firestore.dart';

class ForumPost {
  final String id;
  final String type; // 'discussion' or 'manga_share'
  final String authorId;
  final String authorName;
  final String authorAvatar;
  final String body;
  final String? gifUrl;
  final String? imageUrl;

  // For manga_share type
  final String? sharedMangaId;
  final String? sharedMangaTitle;
  final String? sharedMangaCoverUrl;
  final String? sharedMangaAuthor;

  final int likeCount;
  final int commentCount;
  final int viewCount;
  final int reportCount;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  ForumPost({
    required this.id,
    required this.type,
    required this.authorId,
    required this.authorName,
    required this.authorAvatar,
    required this.body,
    this.gifUrl,
    this.imageUrl,
    this.sharedMangaId,
    this.sharedMangaTitle,
    this.sharedMangaCoverUrl,
    this.sharedMangaAuthor,
    this.likeCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.reportCount = 0,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ForumPost.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ForumPost.fromMap(doc.id, data);
  }

  factory ForumPost.fromMap(String id, Map<String, dynamic> data) {
    return ForumPost(
      id: id,
      type: _readString(data['type'], fallback: 'discussion'),
      authorId: _readString(data['authorId']),
      authorName: _readString(data['authorName'], fallback: 'Unknown'),
      authorAvatar: _readString(data['authorAvatar']),
      body: _readString(data['body']),
      gifUrl: _readNullableString(data['gifUrl']),
      imageUrl: _readNullableString(data['imageUrl']),
      sharedMangaId: _readNullableString(data['sharedMangaId']),
      sharedMangaTitle: _readNullableString(data['sharedMangaTitle']),
      sharedMangaCoverUrl: _readNullableString(data['sharedMangaCoverUrl']),
      sharedMangaAuthor: _readNullableString(data['sharedMangaAuthor']),
      likeCount: _readInt(data['likeCount']),
      commentCount: _readInt(data['commentCount']),
      viewCount: _readInt(data['viewCount']),
      reportCount: _readInt(data['reportCount']),
      isDeleted: data['isDeleted'] is bool ? data['isDeleted'] as bool : false,
      createdAt: _readDateTime(data['createdAt']),
      updatedAt: _readDateTime(data['updatedAt']),
    );
  }

  static String _readString(dynamic value, {String fallback = ''}) =>
      value is String ? value : fallback;

  static String? _readNullableString(dynamic value) =>
      value is String ? value : null;

  static int _readInt(dynamic value) => value is num ? value.toInt() : 0;

  static DateTime _readDateTime(dynamic value) =>
      value is Timestamp ? value.toDate() : DateTime.now();

  Map<String, dynamic> toFirestore() {
    return {
      'type': type,
      'authorId': authorId,
      'authorName': authorName,
      'authorAvatar': authorAvatar,
      'body': body,
      if (gifUrl != null) 'gifUrl': gifUrl,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (sharedMangaId != null) 'sharedMangaId': sharedMangaId,
      if (sharedMangaTitle != null) 'sharedMangaTitle': sharedMangaTitle,
      if (sharedMangaCoverUrl != null)
        'sharedMangaCoverUrl': sharedMangaCoverUrl,
      if (sharedMangaAuthor != null) 'sharedMangaAuthor': sharedMangaAuthor,
      'likeCount': likeCount,
      'commentCount': commentCount,
      'viewCount': viewCount,
      'reportCount': reportCount,
      'isDeleted': isDeleted,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
