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
    return ForumComment.fromMap(doc.id, data);
  }

  factory ForumComment.fromMap(String id, Map<String, dynamic> data) {
    return ForumComment(
      id: id,
      authorId: _readString(data['authorId']),
      authorName: _readString(data['authorName'], fallback: 'Unknown'),
      authorAvatar: _readString(data['authorAvatar']),
      body: _readString(data['body']),
      gifUrl: _readNullableString(data['gifUrl']),
      likeCount: _readInt(data['likeCount']),
      isDeleted: data['isDeleted'] is bool ? data['isDeleted'] as bool : false,
      createdAt: _readDateTime(data['createdAt']),
      updatedAt: _readDateTime(data['updatedAt']),
      replyToCommentId: _readNullableString(data['replyToCommentId']),
      replyToAuthorName: _readNullableString(data['replyToAuthorName']),
      replyToUserId: _readNullableString(data['replyToUserId']),
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
