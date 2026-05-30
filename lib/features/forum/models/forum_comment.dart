import 'package:cloud_firestore/cloud_firestore.dart';

class ForumComment {
  final String id;
  final String authorId;
  final String authorName;
  final String authorAvatar;
  final String body;
  final String? gifUrl;
  final int likeCount;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? replyToCommentId;
  final String? replyToAuthorName;
  final String? replyToUserId;

  ForumComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorAvatar,
    required this.body,
    this.gifUrl,
    this.likeCount = 0,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
    this.replyToCommentId,
    this.replyToAuthorName,
    this.replyToUserId,
  });

  factory ForumComment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ForumComment(
      id: doc.id,
      authorId: data['authorId'] ?? '',
      authorName: data['authorName'] ?? 'Unknown',
      authorAvatar: data['authorAvatar'] ?? '',
      body: data['body'] ?? '',
      gifUrl: data['gifUrl'],
      likeCount: data['likeCount'] ?? 0,
      isDeleted: data['isDeleted'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      replyToCommentId: data['replyToCommentId'],
      replyToAuthorName: data['replyToAuthorName'],
      replyToUserId: data['replyToUserId'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'authorId': authorId,
      'authorName': authorName,
      'authorAvatar': authorAvatar,
      'body': body,
      if (gifUrl != null) 'gifUrl': gifUrl,
      'likeCount': likeCount,
      'isDeleted': isDeleted,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (replyToCommentId != null) 'replyToCommentId': replyToCommentId,
      if (replyToAuthorName != null) 'replyToAuthorName': replyToAuthorName,
      if (replyToUserId != null) 'replyToUserId': replyToUserId,
    };
  }
}
