import 'package:cloud_firestore/cloud_firestore.dart';

class ForumMessage {
  final String id;
  final String authorId;
  final String authorName;
  final String authorAvatar;
  final String body;
  final String? gifUrl;
  final String? imageUrl;
  final bool isDeleted;
  final DateTime createdAt;
  final bool authorIsAdmin;

  // Reply-to fields
  final String? replyToMessageId;
  final String? replyToAuthorName;
  final String? replyToBody;

  ForumMessage({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorAvatar,
    required this.body,
    this.gifUrl,
    this.imageUrl,
    this.isDeleted = false,
    required this.createdAt,
    this.authorIsAdmin = false,
    this.replyToMessageId,
    this.replyToAuthorName,
    this.replyToBody,
  });

  factory ForumMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ForumMessage(
      id: doc.id,
      authorId: data['authorId'] ?? '',
      authorName: data['authorName'] ?? 'Người dùng',
      authorAvatar: data['authorAvatar'] ?? '',
      body: data['body'] ?? '',
      gifUrl: data['gifUrl'],
      imageUrl: data['imageUrl'],
      isDeleted: data['isDeleted'] ?? false,
      authorIsAdmin: data['authorIsAdmin'] ?? false,
      createdAt: _parseTimestamp(data['createdAt']),
      replyToMessageId: data['replyToMessageId'],
      replyToAuthorName: data['replyToAuthorName'],
      replyToBody: data['replyToBody'],
    );
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  Map<String, dynamic> toFirestore() {
    return {
      'authorId': authorId,
      'authorName': authorName,
      'authorAvatar': authorAvatar,
      'body': body,
      if (gifUrl != null) 'gifUrl': gifUrl,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'isDeleted': isDeleted,
      'authorIsAdmin': authorIsAdmin,
      'createdAt': FieldValue.serverTimestamp(),
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
      if (replyToAuthorName != null) 'replyToAuthorName': replyToAuthorName,
      if (replyToBody != null) 'replyToBody': replyToBody,
    };
  }
}
