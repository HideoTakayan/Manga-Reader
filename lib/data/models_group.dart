import 'package:cloud_firestore/cloud_firestore.dart';

class ScanlationGroup {
  final String id;
  final String name;
  final String description;
  final String leaderId;
  final String leaderEmail; // Email Google của trưởng nhóm để Admin thêm vào test users
  final List<String> members;
  final String inviteCode;
  final String status; // 'pending', 'approved', 'rejected'
  final DateTime createdAt;

  ScanlationGroup({
    required this.id,
    required this.name,
    required this.description,
    required this.leaderId,
    this.leaderEmail = '',
    required this.members,
    required this.inviteCode,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'leaderId': leaderId,
      'leaderEmail': leaderEmail,
      'members': members,
      'inviteCode': inviteCode,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory ScanlationGroup.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ScanlationGroup(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      leaderId: data['leaderId'] ?? '',
      leaderEmail: data['leaderEmail'] ?? '',
      members: List<String>.from(data['members'] ?? []),
      inviteCode: data['inviteCode'] ?? '',
      status: data['status'] ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
