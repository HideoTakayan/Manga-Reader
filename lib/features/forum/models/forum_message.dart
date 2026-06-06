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
    return ForumMessage.fromMap(doc.id, data);
  }

  factory ForumMessage.fromMap(String id, Map<String, dynamic> data) {
    return ForumMessage(
      id: id,
      authorId: _readString(data['authorId']),
      authorName: _readString(data['authorName'], fallback: 'Người dùng'),
      authorAvatar: _readString(data['authorAvatar']),
      body: _readString(data['body']),
      gifUrl: _readNullableString(data['gifUrl']),
      imageUrl: _readNullableString(data['imageUrl']),
      isDeleted: data['isDeleted'] is bool ? data['isDeleted'] as bool : false,
      authorIsAdmin: data['authorIsAdmin'] is bool
          ? data['authorIsAdmin'] as bool
          : false,
      createdAt: _parseTimestamp(data['createdAt']),
      replyToMessageId: _readNullableString(data['replyToMessageId']),
      replyToAuthorName: _readNullableString(data['replyToAuthorName']),
      replyToBody: _readNullableString(data['replyToBody']),
    );
  }

  static String _readString(dynamic value, {String fallback = ''}) =>
      value is String ? value : fallback;

  static String? _readNullableString(dynamic value) =>
      value is String ? value : null;

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
