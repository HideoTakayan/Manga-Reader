import 'package:cloud_firestore/cloud_firestore.dart';

class CloudUser {
  final String uid;
  final String name;
  final String email;
  final String avatar;
  final DateTime createdAt;
  final bool isOnline;

  CloudUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.avatar,
    required this.createdAt,
    this.isOnline = false,
  });

  factory CloudUser.fromMap(Map<String, dynamic> map, String id) {
    return CloudUser(
      uid: id,
      name: map['name'] ?? 'Unknown',
      email: map['email'] ?? '',
      avatar: map['avatar'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isOnline: map['isOnline'] ?? false,
    );
  }
}
