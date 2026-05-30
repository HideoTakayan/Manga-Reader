import 'package:cloud_firestore/cloud_firestore.dart';

class ForumMessage {
  final String id;
  final String authorId;
  final String authorName;
  final String authorAvatar;
  final String body;
  final String? gifUrl;
  final bool isDeleted;
  final DateTime createdAt;

  ForumMessage({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorAvatar,
    required this.body,
    this.gifUrl,
    this.isDeleted = false,
    required this.createdAt,
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
      isDeleted: data['isDeleted'] ?? false,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'authorId': authorId,
      'authorName': authorName,
      'authorAvatar': authorAvatar,
      'body': body,
      if (gifUrl != null) 'gifUrl': gifUrl,
      'isDeleted': isDeleted,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
