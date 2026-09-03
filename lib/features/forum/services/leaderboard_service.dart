import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/level_service.dart';

/// Đại diện cho 1 người dùng trên Bảng Xếp Hạng
class LeaderboardUser {
  final String uid;
  final String name;
  final String avatarUrl;
  final int exp;
  final int level;
  final String title;
  final int claimedChaptersCount;
  final int rank;

  const LeaderboardUser({
    required this.uid,
    required this.name,
    required this.avatarUrl,
    required this.exp,
    required this.level,
    required this.title,
    required this.claimedChaptersCount,
    required this.rank,
  });

  factory LeaderboardUser.fromFirestore(
    DocumentSnapshot doc,
    int rank,
  ) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final displayName = (data['displayName']?.toString() ?? '').trim();
    final name = (data['name']?.toString() ?? '').trim();
    final finalName = displayName.isNotEmpty
        ? displayName
        : (name.isNotEmpty ? name : 'Độc giả vô danh');

    final avatarUrl = (data['avatarUrl']?.toString() ??
            data['avatar']?.toString() ??
            '')
        .trim();

    final exp = (data['exp'] as num?)?.toInt() ?? 0;
    final levelInfo = LevelService.getLevelInfo(exp);
    final level = (data['level'] as num?)?.toInt() ?? levelInfo.level;
    final title = (data['title']?.toString() ?? '').trim().isNotEmpty
        ? data['title'].toString()
        : levelInfo.title;

    final chapters = (data['claimedChaptersCount'] as num?)?.toInt() ??
        (exp / LevelService.expPerChapter).floor();

    return LeaderboardUser(
      uid: doc.id,
      name: finalName,
      avatarUrl: avatarUrl,
      exp: exp,
      level: level,
      title: title,
      claimedChaptersCount: chapters,
      rank: rank,
    );
  }
}

/// Dịch vụ tải dữ liệu Bảng Xếp Hạng toàn server
class LeaderboardService {
  static final LeaderboardService instance = LeaderboardService._internal();
  LeaderboardService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, int> _rankCache = {};
  bool _isWarmupStarted = false;

  /// Khởi động lắng nghe nền Top 20 user để cache thứ hạng VIP toàn app
  void initWarmup() {
    if (_isWarmupStarted) return;
    _isWarmupStarted = true;
    try {
      _firestore
          .collection('users')
          .orderBy('exp', descending: true)
          .limit(20)
          .snapshots()
          .listen((snapshot) {
        _rankCache.clear();
        for (int i = 0; i < snapshot.docs.length; i++) {
          _rankCache[snapshot.docs[i].id] = i + 1;
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  /// Lấy thứ hạng hiện tại của người dùng từ cache (0 nếu không trong Top)
  int getCachedRank(String uid) => _rankCache[uid] ?? 0;

  /// Lấy Top độc giả theo tổng EXP
  Stream<List<LeaderboardUser>> streamTopExpUsers({int limit = 50}) {
    return _firestore
        .collection('users')
        .orderBy('exp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final list = <LeaderboardUser>[];
      for (int i = 0; i < snapshot.docs.length; i++) {
        final rank = i + 1;
        final doc = snapshot.docs[i];
        _rankCache[doc.id] = rank;
        list.add(LeaderboardUser.fromFirestore(doc, rank));
      }
      return list;
    });
  }

  /// Lấy Top độc giả theo số chương đã đọc
  Stream<List<LeaderboardUser>> streamTopChaptersUsers({int limit = 50}) {
    return _firestore
        .collection('users')
        .orderBy('claimedChaptersCount', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final list = <LeaderboardUser>[];
      for (int i = 0; i < snapshot.docs.length; i++) {
        list.add(LeaderboardUser.fromFirestore(snapshot.docs[i], i + 1));
      }
      return list;
    });
  }
}
