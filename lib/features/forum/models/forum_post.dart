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
    return ForumPost(
      id: doc.id,
      type: data['type'] ?? 'discussion',
      authorId: data['authorId'] ?? '',
      authorName: data['authorName'] ?? 'Unknown',
      authorAvatar: data['authorAvatar'] ?? '',
      body: data['body'] ?? '',
      gifUrl: data['gifUrl'],
      imageUrl: data['imageUrl'],
      sharedMangaId: data['sharedMangaId'],
      sharedMangaTitle: data['sharedMangaTitle'],
      sharedMangaCoverUrl: data['sharedMangaCoverUrl'],
      sharedMangaAuthor: data['sharedMangaAuthor'],
      likeCount: data['likeCount'] ?? 0,
      commentCount: data['commentCount'] ?? 0,
      viewCount: data['viewCount'] ?? 0,
      reportCount: data['reportCount'] ?? 0,
      isDeleted: data['isDeleted'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

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
