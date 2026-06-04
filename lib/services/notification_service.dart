import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database_helper.dart';
import '../data/drive_service.dart';

class AppNotification {
  final String id;
  final String source;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final String? route;
  final String? targetId;
  final String? actorName;
  final String? actorAvatar;
  final String? imageUrl;
  final Map<String, dynamic> metadata;

  const AppNotification({
    required this.id,
    required this.source,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    this.route,
    this.targetId,
    this.actorName,
    this.actorAvatar,
    this.imageUrl,
    this.metadata = const {},
  });

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      source: source,
      type: type,
      title: title,
      body: body,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      route: route,
      targetId: targetId,
      actorName: actorName,
      actorAvatar: actorAvatar,
      imageUrl: imageUrl,
      metadata: metadata,
    );
  }
}

// NotificationService: 2 hệ thống notification độc lập:
// 1. LOCAL NOTIFICATIONS: thanh tiến trình tải xuống (system notification bar)
// 2. FIRESTORE NOTIFICATIONS: thông báo chapter mới, lọc theo following list

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  Stream<List<AppNotification>>? _userNotificationsStream;
  String? _userNotificationsStreamUserId;
  List<AppNotification> _latestUserNotifications = const [];

  static const Map<int, int> _windows1252Bytes = {
    0x20AC: 0x80,
    0x201A: 0x82,
    0x0192: 0x83,
    0x201E: 0x84,
    0x2026: 0x85,
    0x2020: 0x86,
    0x2021: 0x87,
    0x02C6: 0x88,
    0x2030: 0x89,
    0x0160: 0x8A,
    0x2039: 0x8B,
    0x0152: 0x8C,
    0x017D: 0x8E,
    0x2018: 0x91,
    0x2019: 0x92,
    0x201C: 0x93,
    0x201D: 0x94,
    0x2022: 0x95,
    0x2013: 0x96,
    0x2014: 0x97,
    0x02DC: 0x98,
    0x2122: 0x99,
    0x0161: 0x9A,
    0x203A: 0x9B,
    0x0153: 0x9C,
    0x017E: 0x9E,
    0x0178: 0x9F,
  };

  Map<String, dynamic> _normalizeNotificationData(Map<String, dynamic> data) {
    return data.map((key, value) {
      if (value is String) {
        return MapEntry(key, _repairMojibake(value));
      }
      return MapEntry(key, value);
    });
  }

  String _repairMojibake(String value) {
    if (!_looksMojibake(value)) return value;

    final bytes = <int>[];
    for (final rune in value.runes) {
      if (rune <= 0xFF) {
        bytes.add(rune);
        continue;
      }

      final windows1252Byte = _windows1252Bytes[rune];
      if (windows1252Byte == null) return value;
      bytes.add(windows1252Byte);
    }

    try {
      final repaired = utf8.decode(bytes, allowMalformed: false);
      return _mojibakeScore(repaired) < _mojibakeScore(value)
          ? repaired
          : value;
    } catch (_) {
      return value;
    }
  }

  bool _looksMojibake(String value) {
    return value.contains('Ã') ||
        value.contains('Â') ||
        value.contains('â') ||
        value.contains('áº') ||
        value.contains('á»') ||
        value.contains('Ä') ||
        value.contains('Æ');
  }

  int _mojibakeScore(String value) {
    const markers = ['Ã', 'Â', 'â', 'áº', 'á»', 'Ä', 'Æ', '�'];
    var score = 0;
    for (final marker in markers) {
      score += marker.allMatches(value).length;
    }
    return score;
  }

  // ─── LOCAL NOTIFICATIONS (Download Progress Bar) ───────────────────────────

  Future<void> initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) {},
    );
    final androidImpl = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();
  }

  Future<void> showDownloadProgress(
    int id,
    int progress,
    String title,
    String body,
  ) async {
    final androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Download Manager',
      channelDescription: 'Notifications for background downloads',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      ongoing: true,
      autoCancel: false,
    );
    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  Future<void> showDownloadComplete(
    int id,
    String title,
    String body, {
    bool isError = false,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Download Manager',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: false,
      autoCancel: true,
    );
    final displayTitle = isError ? '❌ $title' : '✅ $title';
    await _localNotifications.show(
      id: id,
      title: displayTitle,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  @Deprecated('Use cancelNotification instead.')
  Future<void> cancelNtification(int id) async {
    await cancelNotification(id);
  }

  Future<void> cancelNotification(int id) async {
    await _localNotifications.cancel(id: id);
  }

  // ─── FIRESTORE NOTIFICATIONS (New Chapter Alerts) ──────────────────────────

  // Lọc: chỉ hiện thông báo của manga user đang following
  Stream<List<AppNotification>> streamUserNotifications() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return Stream.value([]);
    }

    if (_userNotificationsStream == null ||
        _userNotificationsStreamUserId != userId) {
      _latestUserNotifications = const [];
      _userNotificationsStreamUserId = userId;
      _userNotificationsStream = _buildUserNotificationsStream(userId);
    }

    final sharedStream = _userNotificationsStream!;
    return Stream<List<AppNotification>>.multi((controller) {
      controller.add(_latestUserNotifications);
      final subscription = sharedStream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  Stream<List<AppNotification>> _buildUserNotificationsStream(String userId) {
    final controller = StreamController<List<AppNotification>>.broadcast();

    List<AppNotification> globalNotifs = [];
    List<AppNotification> forumNotifs = [];
    final globalBySource = <String, Map<String, AppNotification>>{};
    final globalSubscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    var followingIds = <String>{};
    var readIds = <String>{};

    void emitMerged() {
      final merged = [...globalNotifs, ...forumNotifs];
      merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _latestUserNotifications = merged;
      controller.add(merged);
    }

    void rebuildGlobalNotifs() {
      final mergedById = <String, AppNotification>{};
      for (final sourceMap in globalBySource.values) {
        for (final entry in sourceMap.entries) {
          mergedById[entry.key] = entry.value.copyWith(
            isRead: readIds.contains(entry.key),
          );
        }
      }
      globalNotifs = mergedById.values.toList();
      emitMerged();
    }

    void cancelGlobalSubscriptions() {
      for (final sub in globalSubscriptions) {
        unawaited(sub.cancel());
      }
      globalSubscriptions.clear();
    }

    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
    listenGlobalNotificationsByMangaField(String field, List<String> ids) {
      final sourceKey = '$field:${ids.join('|')}';
      final sourceMap = globalBySource[sourceKey] = <String, AppNotification>{};
      return _db
          .collection('notifications')
          .where(field, whereIn: ids)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots()
          .listen(
            (snapshot) {
              for (final change in snapshot.docChanges) {
                if (change.type == DocumentChangeType.removed) {
                  sourceMap.remove(change.doc.id);
                } else {
                  final data = change.doc.data();
                  if (data != null) {
                    sourceMap[change.doc.id] = _globalNotificationFromData(
                      id: change.doc.id,
                      data: data,
                      isRead: readIds.contains(change.doc.id),
                    );
                  }
                }
              }
              rebuildGlobalNotifs();
            },
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('Global notification stream error ($field): $error');
              emitMerged();
            },
          );
    }

    void restartGlobalSubscriptions() {
      cancelGlobalSubscriptions();
      globalBySource.clear();

      if (followingIds.isEmpty) {
        // Fetch only system notifications if following list is empty
      } else {
        final ids = followingIds.toList();
        for (var index = 0; index < ids.length; index += 10) {
          final chunk = ids.skip(index).take(10).toList();
          globalSubscriptions.add(
            listenGlobalNotificationsByMangaField('mangaId', chunk),
          );
          globalSubscriptions.add(
            listenGlobalNotificationsByMangaField('comicId', chunk),
          );
        }
      }

      // Always fetch system-wide notifications
      const systemSourceKey = 'type:system';
      final systemSourceMap = globalBySource[systemSourceKey] =
          <String, AppNotification>{};
      final systemSub = _db
          .collection('notifications')
          .where('type', isEqualTo: 'system')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots()
          .listen(
            (snapshot) {
              for (final change in snapshot.docChanges) {
                if (change.type == DocumentChangeType.removed) {
                  systemSourceMap.remove(change.doc.id);
                } else {
                  final data = change.doc.data();
                  if (data != null) {
                    systemSourceMap[change.doc.id] =
                        _globalNotificationFromData(
                          id: change.doc.id,
                          data: data,
                          isRead: readIds.contains(change.doc.id),
                        );
                  }
                }
              }
              rebuildGlobalNotifs();
            },
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('System notification stream error: $error');
              emitMerged();
            },
          );
      globalSubscriptions.add(systemSub);
    }

    final userFollowingSub = _db
        .collection('users')
        .doc(userId)
        .collection('following')
        .snapshots()
        .listen(
          (snapshot) {
            followingIds = snapshot.docs.map((doc) => doc.id).toSet();
            restartGlobalSubscriptions();
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Following stream error: $error');
            followingIds = <String>{};
            restartGlobalSubscriptions();
            emitMerged();
          },
        );

    final userSub = _db
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen(
          (snapshot) {
            final data = snapshot.data();
            readIds = Set<String>.from(data?['readNotificationIds'] ?? []);
            rebuildGlobalNotifs();
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('User notification state stream error: $error');
            readIds = <String>{};
            rebuildGlobalNotifs();
          },
        );

    final forumSub = _db
        .collection('users')
        .doc(userId)
        .collection('forum_notifications')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen(
          (snapshot) {
            try {
              forumNotifs = snapshot.docs.map((doc) {
                return _forumNotificationFromData(id: doc.id, data: doc.data());
              }).toList();
              emitMerged();
            } catch (e) {
              debugPrint('Error filtering forum notifications: $e');
              forumNotifs = [];
              emitMerged();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Forum notification stream error: $error');
            forumNotifs = [];
            emitMerged();
          },
        );

    emitMerged();

    controller.onCancel = () {
      userFollowingSub.cancel();
      userSub.cancel();
      cancelGlobalSubscriptions();
      forumSub.cancel();
      _userNotificationsStream = null;
      _userNotificationsStreamUserId = null;
      _latestUserNotifications = const [];
    };

    return controller.stream;
  }

  AppNotification _globalNotificationFromData({
    required String id,
    required Map<String, dynamic> data,
    required bool isRead,
  }) {
    final normalized = _normalizeNotificationData(data);
    final rawType = normalized['type']?.toString() ?? 'new_chapter';
    final mangaId =
        _readOptionalString(normalized['mangaId']) ??
        _readOptionalString(normalized['comicId']);
    final route =
        _readOptionalString(normalized['route']) ??
        (mangaId == null ? null : '/detail/$mangaId');

    return AppNotification(
      id: id,
      source: rawType == 'system' ? 'system' : 'manga',
      type: _mapGlobalType(rawType),
      title: _readString(normalized['title'], fallback: 'Thông báo mới'),
      body: _readString(normalized['body']),
      createdAt: _readDateTime(
        normalized['createdAt'] ?? normalized['timestamp'],
      ),
      isRead: isRead,
      route: route,
      targetId: mangaId,
      metadata: normalized,
    );
  }

  AppNotification _forumNotificationFromData({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final normalized = _normalizeNotificationData(data);
    final postId = _readOptionalString(normalized['postId']);

    return AppNotification(
      id: id,
      source: 'forum',
      type: _mapForumType(_readString(normalized['type'])),
      title: _readString(normalized['title'], fallback: 'Thông báo diễn đàn'),
      body: _readString(normalized['body'] ?? normalized['postPreview']),
      createdAt: _readDateTime(normalized['createdAt']),
      isRead: normalized['isRead'] == true,
      route:
          _readOptionalString(normalized['route']) ??
          (postId == null ? null : '/forum/detail/$postId'),
      targetId: postId,
      actorName: _readOptionalString(normalized['actorName']),
      actorAvatar: _readOptionalString(normalized['actorAvatar']),
      metadata: normalized,
    );
  }

  String _mapGlobalType(String type) {
    return switch (type) {
      'new_chapter' => 'manga.new_chapter',
      'info_update' => 'manga.info_updated',
      'status_update' => 'manga.status_changed',
      'system' => 'system.announcement',
      _ => type.contains('.') ? type : 'manga.$type',
    };
  }

  String _mapForumType(String type) {
    return switch (type) {
      'forum_like' => 'forum.post_liked',
      'forum_comment' => 'forum.post_commented',
      'forum_reply' => 'forum.comment_replied',
      'forum_comment_like' => 'forum.comment_liked',
      _ => type.contains('.') ? type : 'forum.$type',
    };
  }

  DateTime _readDateTime(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _readString(Object? value, {String fallback = ''}) {
    if (value is String && value.isNotEmpty) return value;
    return fallback;
  }

  String? _readOptionalString(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  Map<String, dynamic> _userNotificationStatePayload(List<String> ids) {
    final user = _auth.currentUser;
    final payload = <String, dynamic>{
      'readNotificationIds': FieldValue.arrayUnion(ids),
    };
    if (user?.uid != null) {
      payload['uid'] = user!.uid;
    }
    if (user?.email != null && user!.email!.isNotEmpty) {
      payload['email'] = user.email;
    }
    return payload;
  }

  Future<void> markAsRead(String notificationId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    await _db
        .collection('users')
        .doc(userId)
        .set(
          _userNotificationStatePayload([notificationId]),
          SetOptions(merge: true),
        );
  }

  Future<void> markNotificationAsRead(AppNotification note) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    if (note.source == 'forum') {
      try {
        await _db
            .collection('users')
            .doc(userId)
            .collection('forum_notifications')
            .doc(note.id)
            .update({'isRead': true});
      } catch (e) {
        debugPrint('Error marking forum notification as read: $e');
      }
    } else {
      await markAsRead(note.id);
    }
  }

  Future<void> markAllNotificationsAsRead(
    List<AppNotification> notifications,
  ) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null || notifications.isEmpty) return;

    final globalIds = <String>[];
    var batch = _db.batch();
    var batchWrites = 0;

    Future<void> commitBatchIfNeeded({bool force = false}) async {
      if (batchWrites == 0 || (!force && batchWrites < 450)) return;
      await batch.commit();
      batch = _db.batch();
      batchWrites = 0;
    }

    for (final note in notifications) {
      if (note.isRead) continue;

      if (note.source == 'forum') {
        final ref = _db
            .collection('users')
            .doc(userId)
            .collection('forum_notifications')
            .doc(note.id);
        batch.update(ref, {'isRead': true});
        batchWrites++;
        await commitBatchIfNeeded();
      } else {
        globalIds.add(note.id);
      }
    }

    if (globalIds.isNotEmpty) {
      await _db
          .collection('users')
          .doc(userId)
          .set(
            _userNotificationStatePayload(globalIds),
            SetOptions(merge: true),
          );
    }

    await commitBatchIfNeeded(force: true);
  }

  final Set<String> _processedIds = {};
  DateTime _startTime = DateTime.now();
  StreamSubscription? _subscription;

  Future<void> initialize() async {
    await initLocalNotifications();
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        _startListening();
      } else {
        _stopListening(clearStreamCache: true);
      }
    });
  }

  void _startListening() {
    _stopListening();
    _subscription = streamUserNotifications().listen((notifs) {
      for (var n in notifs) {
        final id = n.id;
        if (_processedIds.contains(id)) continue;

        if (n.createdAt.isAfter(_startTime)) {
          _processedIds.add(id);
          showGeneralNotification(title: n.title, body: n.body);
        } else {
          _processedIds.add(id);
        }
      }
    });
  }

  void _stopListening({bool clearStreamCache = false}) {
    _subscription?.cancel();
    _subscription = null;
    if (clearStreamCache) {
      _userNotificationsStream = null;
      _userNotificationsStreamUserId = null;
      _latestUserNotifications = const [];
    }
    _processedIds.clear();
    _startTime = DateTime.now();
  }

  Future<void> showGeneralNotification({
    required String title,
    required String body,
  }) async {
    final androidDetails = const AndroidNotificationDetails(
      'general_channel',
      'General Updates',
      channelDescription: 'New chapters and updates',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  Future<void> checkLocalChapterUpdates() async {
    try {
      await initLocalNotifications();
      final db = await DatabaseHelper.instance.database;
      final libraryRows = await db.query('lib_mapping', columns: ['mangaId']);
      final libraryIds = libraryRows
          .map((row) => row['mangaId']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      if (libraryIds.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final mangas = await DriveService.instance.getMangas();
      for (final manga in mangas.where(
        (manga) => libraryIds.contains(manga.id),
      )) {
        final chapterCount = manga.chapterOrder.length;
        if (chapterCount <= 0) continue;

        final key = 'last_notified_chapter_count_${manga.id}';
        final lastCount = prefs.getInt(key);
        await prefs.setInt(key, chapterCount);

        if (lastCount == null || chapterCount <= lastCount) continue;

        await showGeneralNotification(
          title: 'Có chapter mới',
          body:
              '${manga.title} vừa cập nhật ${chapterCount - lastCount} chapter',
        );
      }
    } catch (e) {
      debugPrint('Local chapter update check failed: $e');
    }
  }

  // ─── FIRESTORE CLOUD NOTIFICATIONS ─────────────────────────────────────────
  Future<void> notifySubscribers({
    required String mangaId,
    required String title,
    required String body,
    String type = 'new_chapter',
  }) async {
    try {
      await _db.collection('notifications').add({
        'mangaId': mangaId,
        'title': _repairMojibake(title),
        'body': _repairMojibake(body),
        'timestamp': FieldValue.serverTimestamp(),
        'type': type,
      });
      debugPrint(
        'Đã gửi thông báo chapter mới lên Firestore cho truyện $mangaId',
      );
    } catch (e) {
      debugPrint('Lỗi gửi thông báo: $e');
    }
  }

  Stream<bool> streamSubscriptionStatus(String mangaId) => Stream.value(false);
  Future<void> toggleSubscription(String mangaId) async {}
  Stream<int> streamMangaNotificationCount(String mangaId) => Stream.value(0);
}
