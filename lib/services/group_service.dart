import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models_group.dart';

class GroupService {
  static final GroupService instance = GroupService._();
  GroupService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(Iterable.generate(
        6, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  /// 1. Đăng ký tạo Nhóm dịch mới
  Future<void> registerGroup({
    required String name,
    required String description,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Vui lòng đăng nhập');

    final code = _generateInviteCode();

    await _firestore.collection('scanlation_groups').add({
      'name': name,
      'description': description,
      'leaderId': user.uid,
      'leaderEmail': user.email ?? '', // Email Google để Admin thêm vào Cloud Console test users
      'members': [user.uid],
      'inviteCode': code,
      'status': 'pending', // Cần Admin duyệt
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// 2. Admin duyệt Nhóm dịch
  Future<void> approveGroup(String groupId, String leaderId) async {
    final batch = _firestore.batch();
    
    final groupRef = _firestore.collection('scanlation_groups').doc(groupId);
    batch.update(groupRef, {'status': 'approved'});

    final userRef = _firestore.collection('users').doc(leaderId);
    batch.update(userRef, {'groupId': groupId});

    await batch.commit();
  }

  /// 2.5 Admin từ chối
  Future<void> rejectGroup(String groupId) async {
    await _firestore.collection('scanlation_groups').doc(groupId).update({
      'status': 'rejected',
    });
  }

  /// 3. Xin vào nhóm bằng mã Invite Code
  Future<void> joinGroupByCode(String inviteCode) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Vui lòng đăng nhập');

    final snapshot = await _firestore
        .collection('scanlation_groups')
        .where('inviteCode', isEqualTo: inviteCode)
        .where('status', isEqualTo: 'approved')
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      throw Exception('Mã nhóm không hợp lệ hoặc nhóm chưa được duyệt');
    }

    final groupDoc = snapshot.docs.first;
    final groupId = groupDoc.id;

    final batch = _firestore.batch();

    // Thêm UID vào mảng members
    batch.update(groupDoc.reference, {
      'members': FieldValue.arrayUnion([user.uid])
    });

    // Cập nhật groupId vào User doc
    final userRef = _firestore.collection('users').doc(user.uid);
    batch.set(userRef, {'groupId': groupId}, SetOptions(merge: true));

    await batch.commit();
  }

  /// 4. Làm mới (Reset) Invite Code (Dành cho Trưởng nhóm)
  Future<String> refreshInviteCode(String groupId) async {
    final code = _generateInviteCode();
    await _firestore
        .collection('scanlation_groups')
        .doc(groupId)
        .update({'inviteCode': code});
    return code;
  }

  /// 5. Đuổi thành viên ra khỏi nhóm
  Future<void> removeMember(String groupId, String memberUid) async {
    await _firestore.collection('scanlation_groups').doc(groupId).update({
      'members': FieldValue.arrayRemove([memberUid])
    });

  }

  /// Rời nhóm (Tự nguyện)
  Future<void> leaveGroup(String groupId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final batch = _firestore.batch();
    batch.update(_firestore.collection('scanlation_groups').doc(groupId), {
      'members': FieldValue.arrayRemove([user.uid])
    });
    batch.update(_firestore.collection('users').doc(user.uid), {
      'groupId': FieldValue.delete()
    });
    await batch.commit();
  }

  /// Lấy thông tin nhóm hiện tại
  Stream<ScanlationGroup?> currentGroupStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(null);

    return _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .asyncExpand((userDoc) {
      if (!userDoc.exists) return Stream.value(null);
      final data = userDoc.data() ?? {};
      final groupId = data['groupId'] as String?;
      if (groupId == null) return Stream.value(null);

      return _firestore
          .collection('scanlation_groups')
          .doc(groupId)
          .snapshots()
          .map((groupDoc) {
        if (!groupDoc.exists) return null;
        final group = ScanlationGroup.fromFirestore(groupDoc);
        if (group.status != 'approved') return null;
        
        if (!group.members.contains(user.uid)) {
          // User was removed by leader. Clean up own profile.
          _firestore.collection('users').doc(user.uid).update({'groupId': FieldValue.delete()});
          return null;
        }
        
        return group;
      });
    });
  }
}
