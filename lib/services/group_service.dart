import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models_group.dart';

class GroupService {
  static final GroupService instance = GroupService._();
  GroupService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, ScanlationGroup> _groupCache = {};

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

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw Exception('Tên nhóm không được để trống');
    if (trimmedName.length > 50) throw Exception('Tên nhóm tối đa 50 ký tự');
    final trimmedDesc = description.trim();
    if (trimmedDesc.length > 500) throw Exception('Mô tả nhóm tối đa 500 ký tự');

    final code = _generateInviteCode();

    await _firestore.collection('scanlation_groups').add({
      'name': trimmedName,
      'description': trimmedDesc,
      'leaderId': user.uid,
      'leaderEmail': user.email ?? '', // Email Google để Admin thêm vào Cloud Console test users
      'members': [user.uid],
      'inviteCode': code,
      'status': 'pending', // Cần Admin duyệt
      'followerCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 2. Admin duyệt Nhóm dịch
  Future<void> approveGroup(String groupId, String leaderId) async {
    final batch = _firestore.batch();
    
    final groupRef = _firestore.collection('scanlation_groups').doc(groupId);
    batch.update(groupRef, {
      'status': 'approved',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final userRef = _firestore.collection('users').doc(leaderId);
    batch.set(userRef, {
      'groupId': groupId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// 2.5 Admin từ chối
  Future<void> rejectGroup(String groupId) async {
    await _firestore.collection('scanlation_groups').doc(groupId).update({
      'status': 'rejected',
      'updatedAt': FieldValue.serverTimestamp(),
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

    // 1. Thêm UID vào mảng members trước (thỏa mãn rule isSelfJoin)
    await groupDoc.reference.update({
      'members': FieldValue.arrayUnion([user.uid])
    });

    // 2. Cập nhật groupId vào User doc sau khi đã nằm trong members
    // (thỏa mãn rule isValidGroupId: request.auth.uid in get(group).data.members)
    final userRef = _firestore.collection('users').doc(user.uid);
    await userRef.set({
      'groupId': groupId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 4. Làm mới (Reset) Invite Code (Dành cho Trưởng nhóm)
  Future<String> refreshInviteCode(String groupId) async {
    final code = _generateInviteCode();
    await _firestore
        .collection('scanlation_groups')
        .doc(groupId)
        .update({
          'inviteCode': code,
          'updatedAt': FieldValue.serverTimestamp(),
        });
    return code;
  }

  /// 5. Đuổi thành viên ra khỏi nhóm
  Future<void> removeMember(String groupId, String memberUid) async {
    final groupDoc = await _firestore.collection('scanlation_groups').doc(groupId).get();
    if (!groupDoc.exists) return;
    final leaderId = groupDoc.data()?['leaderId'] as String?;
    if (leaderId == memberUid) {
      throw Exception('Không thể xóa Trưởng nhóm khỏi nhóm.');
    }

    final batch = _firestore.batch();
    batch.update(groupDoc.reference, {
      'members': FieldValue.arrayRemove([memberUid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_firestore.collection('users').doc(memberUid), {
      'groupId': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Rời nhóm (Tự nguyện)
  Future<void> leaveGroup(String groupId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    // 1. Xóa groupId ở User doc trước
    final userRef = _firestore.collection('users').doc(user.uid);
    await userRef.update({
      'groupId': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Sau đó xóa khỏi members của nhóm (thỏa mãn rule isSelfLeave)
    await _firestore.collection('scanlation_groups').doc(groupId).update({
      'members': FieldValue.arrayRemove([user.uid])
    });
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

  /// Lấy thông tin nhóm theo ID (dành cho người xem công khai, có cache trong bộ nhớ)
  Future<ScanlationGroup?> getGroupById(String groupId) async {
    if (_groupCache.containsKey(groupId)) {
      return _groupCache[groupId];
    }
    try {
      final doc = await _firestore.collection('scanlation_groups').doc(groupId).get();
      if (!doc.exists) return null;
      final group = ScanlationGroup.fromFirestore(doc);
      _groupCache[groupId] = group;
      return group;
    } catch (_) {
      return null;
    }
  }

  /// 5. Theo dõi nhóm dịch
  Stream<bool> isFollowingGroup(String groupId) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(false);

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('following_groups')
        .doc(groupId)
        .snapshots()
        .map((doc) => doc.exists);
  }

  Future<void> followGroup(String groupId, String groupName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Vui lòng đăng nhập');

    final batch = _firestore.batch();
    final followRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('following_groups')
        .doc(groupId);

    batch.set(followRef, {
      'groupId': groupId,
      'groupName': groupName,
      'followedAt': FieldValue.serverTimestamp(),
    });

    final groupRef = _firestore.collection('scanlation_groups').doc(groupId);
    batch.update(groupRef, {
      'followerCount': FieldValue.increment(1),
    });

    await batch.commit();
  }

  Future<void> unfollowGroup(String groupId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Vui lòng đăng nhập');

    final batch = _firestore.batch();
    final followRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('following_groups')
        .doc(groupId);

    batch.delete(followRef);

    final groupRef = _firestore.collection('scanlation_groups').doc(groupId);
    batch.update(groupRef, {
      'followerCount': FieldValue.increment(-1),
    });

    await batch.commit();
  }

  Stream<int> streamFollowerCount(String groupId) {
    return _firestore
        .collection('scanlation_groups')
        .doc(groupId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return 0;
      final data = doc.data() ?? {};
      final val = data['followerCount'];
      return val is int ? val : (val is num ? val.toInt() : 0);
    });
  }
}

