import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'achievement_service.dart';
import 'glossary_service.dart';

/// Gói từ điển sửa từ ngữ chia sẻ từ cộng đồng
class CommunityGlossaryPack {
  final String id;
  final String title;
  final String description;
  final String authorId;
  final String authorName;
  final String authorAvatar;
  final String? mangaTitle;
  final List<GlossaryRule> rules;
  final int downloadsCount;
  final int likesCount;
  final List<String> likedUserIds;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const CommunityGlossaryPack({
    required this.id,
    required this.title,
    required this.description,
    required this.authorId,
    required this.authorName,
    required this.authorAvatar,
    this.mangaTitle,
    required this.rules,
    this.downloadsCount = 0,
    this.likesCount = 0,
    this.likedUserIds = const [],
    required this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toFirestore() {
    final safeAvatar = (authorAvatar.length <= 2000 && !authorAvatar.startsWith('data:'))
        ? authorAvatar
        : '';
    final safeName = title.trim().length > 100 ? title.trim().substring(0, 100) : title.trim();
    return {
      'name': safeName,
      'title': safeName,
      'description': description.trim().length > 1000 ? description.trim().substring(0, 1000) : description.trim(),
      'authorId': authorId,
      'authorName': authorName.trim().length > 100 ? authorName.trim().substring(0, 100) : authorName.trim(),
      'authorAvatar': safeAvatar,
      if (mangaTitle != null && mangaTitle!.trim().isNotEmpty)
        'mangaTitle': mangaTitle!.trim().length > 200 ? mangaTitle!.trim().substring(0, 200) : mangaTitle!.trim(),
      'rules': rules.map((r) => {'from': r.from, 'to': r.to}).toList(),
      'downloadsCount': downloadsCount,
      'likesCount': likesCount,
      'likedUserIds': likedUserIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory CommunityGlossaryPack.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final rawRules = data['rules'] as List<dynamic>? ?? [];
    final parsedRules = <GlossaryRule>[];

    for (int i = 0; i < rawRules.length; i++) {
      final r = rawRules[i];
      if (r is Map) {
        parsedRules.add(
          GlossaryRule(
            id: '${doc.id}_$i',
            from: r['from']?.toString() ?? '',
            to: r['to']?.toString() ?? '',
            isEnabled: true,
            createdAt: DateTime.now(),
          ),
        );
      }
    }

    final createdTimestamp = data['createdAt'];
    final updatedTimestamp = data['updatedAt'];

    return CommunityGlossaryPack(
      id: doc.id,
      title: (data['title'] ?? data['name'])?.toString() ?? 'Gói từ điển',
      description: data['description']?.toString() ?? '',
      authorId: data['authorId']?.toString() ?? '',
      authorName: data['authorName']?.toString() ?? 'Thành viên ẩn danh',
      authorAvatar: data['authorAvatar']?.toString() ?? '',
      mangaTitle: data['mangaTitle']?.toString(),
      rules: parsedRules,
      downloadsCount: (data['downloadsCount'] as num?)?.toInt() ?? 0,
      likesCount: (data['likesCount'] as num?)?.toInt() ?? 0,
      likedUserIds: (data['likedUserIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      createdAt: createdTimestamp is Timestamp
          ? createdTimestamp.toDate()
          : DateTime.now(),
      updatedAt:
          updatedTimestamp is Timestamp ? updatedTimestamp.toDate() : null,
    );
  }
}

/// Dịch vụ quản lý Gói Từ Điển Sửa Từ Cộng Đồng trên Cloud Firestore
class CommunityGlossaryService extends ChangeNotifier {
  static final CommunityGlossaryService instance =
      CommunityGlossaryService._internal();
  CommunityGlossaryService._internal();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection('community_glossaries');

  /// Tải danh sách các gói từ điển cộng đồng
  Stream<List<CommunityGlossaryPack>> streamCommunityPacks({
    String? searchQuery,
    String sortBy = 'downloadsCount', // 'downloadsCount' | 'createdAt' | 'likesCount'
  }) {
    Query<Map<String, dynamic>> query = _collection.orderBy(
      sortBy,
      descending: true,
    );

    return query.snapshots().map((snapshot) {
      final packs = snapshot.docs
          .map((doc) => CommunityGlossaryPack.fromFirestore(doc))
          .toList();

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.toLowerCase().trim();
        return packs.where((p) {
          return p.title.toLowerCase().contains(q) ||
              p.description.toLowerCase().contains(q) ||
              (p.mangaTitle != null &&
                  p.mangaTitle!.toLowerCase().contains(q)) ||
              p.authorName.toLowerCase().contains(q) ||
              p.rules.any((r) =>
                  r.from.toLowerCase().contains(q) ||
                  r.to.toLowerCase().contains(q));
        }).toList();
      }

      return packs;
    });
  }

  /// Đăng tải bộ từ điển của người dùng lên Cloud
  Future<String> publishPack({
    required String title,
    required String description,
    String? mangaTitle,
    required List<GlossaryRule> rules,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Vui lòng đăng nhập để chia sẻ gói từ điển');
    }

    final validRules = rules
        .where((r) => r.from.trim().isNotEmpty && r.to.trim().isNotEmpty)
        .toList();

    if (validRules.isEmpty) {
      throw Exception('Bộ từ điển không có từ nào để chia sẻ');
    }

    final authorName = user.displayName ??
        (user.email != null ? user.email!.split('@')[0] : 'Thành viên');
    final authorAvatar = user.photoURL ?? '';

    final pack = CommunityGlossaryPack(
      id: '',
      title: title.trim(),
      description: description.trim(),
      authorId: user.uid,
      authorName: authorName,
      authorAvatar: authorAvatar,
      mangaTitle: mangaTitle?.trim(),
      rules: validRules,
      createdAt: DateTime.now(),
    );

    final docRef = await _collection.add(pack.toFirestore());
    unawaited(AchievementService.instance.recordCommunityAction());
    notifyListeners();
    return docRef.id;
  }

  /// Tải / Nhập gói từ điển cộng đồng vào máy người dùng
  Future<int> importPackToLocal(
    CommunityGlossaryPack pack, {
    String? targetMangaId,
  }) async {
    final pairs = pack.rules
        .where((r) => r.from.trim().isNotEmpty && r.to.trim().isNotEmpty)
        .map((r) => {'from': r.from.trim(), 'to': r.to.trim()})
        .toList();

    final importedCount = await GlossaryService.instance.addRulesBatch(
      pairs,
      mangaId: targetMangaId,
    );

    // Tăng số lượt tải lên Firestore
    try {
      await _collection.doc(pack.id).update({
        'downloadsCount': FieldValue.increment(1),
      });
    } catch (_) {}

    notifyListeners();
    return importedCount;
  }

  /// Thả tim / Bỏ thích gói từ điển
  Future<void> toggleLike(String packId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final docRef = _collection.doc(packId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final likedUserIds = (doc.data()?['likedUserIds'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final isLiked = likedUserIds.contains(user.uid);
    if (isLiked) {
      await docRef.update({
        'likedUserIds': FieldValue.arrayRemove([user.uid]),
        'likesCount': FieldValue.increment(-1),
      });
    } else {
      await docRef.update({
        'likedUserIds': FieldValue.arrayUnion([user.uid]),
        'likesCount': FieldValue.increment(1),
      });
    }
  }

  /// Xóa gói từ điển (chỉ tác giả hoặc admin)
  Future<void> deletePack(String packId) async {
    await _collection.doc(packId).delete();
    notifyListeners();
  }
}
