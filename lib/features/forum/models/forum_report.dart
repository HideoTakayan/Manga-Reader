import 'package:cloud_firestore/cloud_firestore.dart';

class ForumReport {
  final String id;
  final String reporterId;
  final String targetType; // 'post', 'comment', 'message'
  final String targetId;
  final String postId;
  final String reason;
  final DateTime createdAt;
  final String status; // 'pending', 'resolved', 'dismissed'

  ForumReport({
    required this.id,
    required this.reporterId,
    required this.targetType,
    required this.targetId,
    required this.postId,
    required this.reason,
    required this.createdAt,
    required this.status,
  });

  factory ForumReport.fromMap(Map<String, dynamic> map, String id) {
    return ForumReport(
      id: id,
      reporterId: map['reporterId'] ?? '',
      targetType: map['targetType'] ?? '',
      targetId: map['targetId'] ?? '',
      postId: map['postId'] ?? '',
      reason: map['reason'] ?? '',
      createdAt: map['createdAt'] is Timestamp 
          ? (map['createdAt'] as Timestamp).toDate() 
          : DateTime.now(),
      status: map['status'] ?? 'pending',
    );
  }

  factory ForumReport.fromFirestore(DocumentSnapshot doc) {
    return ForumReport.fromMap(doc.data() as Map<String, dynamic>, doc.id);
  }
}
