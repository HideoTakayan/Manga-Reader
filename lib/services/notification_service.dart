import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database_helper.dart';
import '../data/drive_service.dart';

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
  Stream<List<Map<String, dynamic>>> streamUserNotifications() async* {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      yield [];
      return;
    }

    final notifStream = _db
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();

    await for (final snapshot in notifStream) {
      try {
        // Lấy song song: following list + user doc (readNotificationIds)
        final results = await Future.wait([
          _db.collection('users').doc(userId).collection('following').get(),
          _db.collection('users').doc(userId).get(),
        ]);

        final followingSnap = results[0] as QuerySnapshot;
        final userDoc = results[1] as DocumentSnapshot;

        final followingIds = followingSnap.docs.map((d) => d.id).toSet();
        final userdata = userDoc.data() as Map<String, dynamic>?;
        final readIds = Set<String>.from(
          userdata?['readNotificationIds'] ?? [],
        );

        final filteredNotifications = snapshot.docs
            .where((doc) {
              final data = doc.data();
              final mangaId = data['mangaId'] ?? data['comicId'];
              if (mangaId == null || mangaId == '') return true;
              return followingIds.contains(mangaId);
            })
            .map(
              (doc) => {
                ...doc.data(),
                'id': doc.id,
                'isRead': readIds.contains(doc.id),
              },
            )
            .toList();

        yield filteredNotifications;
      } catch (e) {
        debugPrint('Error filtering notifications: $e');
        yield [];
      }
    }
  }

  Future<void> markAsRead(String notificationId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    await _db.collection('users').doc(userId).set({
      'readNotificationIds': FieldValue.arrayUnion([notificationId]),
    }, SetOptions(merge: true));
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
        _stopListening();
      }
    });
  }

  void _startListening() {
    _stopListening();
    _subscription = streamUserNotifications().listen((notifs) {
      for (var n in notifs) {
        final id = n['notificationId'] ?? n['id'];
        if (id == null || _processedIds.contains(id)) continue;

        final timestamp = (n['timestamp'] as Timestamp?)?.toDate();
        if (timestamp != null && timestamp.isAfter(_startTime)) {
          _processedIds.add(id);
          showGeneralNotification(
            title: n['title'] ?? 'Thông báo',
            body: n['body'] ?? '',
          );
        } else {
          _processedIds.add(id);
        }
      }
    });
  }

  void _stopListening() {
    _subscription?.cancel();
    _subscription = null;
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
      for (final manga in mangas.where((manga) => libraryIds.contains(manga.id))) {
        final chapterCount = manga.chapterOrder.length;
        if (chapterCount <= 0) continue;

        final key = 'last_notified_chapter_count_${manga.id}';
        final lastCount = prefs.getInt(key);
        await prefs.setInt(key, chapterCount);

        if (lastCount == null || chapterCount <= lastCount) continue;

        await showGeneralNotification(
          title: 'Có chapter mới',
          body: '${manga.title} vừa cập nhật ${chapterCount - lastCount} chapter',
        );
      }
    } catch (e) {
      debugPrint('Local chapter update check failed: $e');
    }
  }

  // ─── STUB METHODS (chưa implement phía client) ─────────────────────────────
  Future<void> notifySubscribers({
    required String mangaId,
    required String title,
    required String body,
  }) async {
    await showGeneralNotification(title: title, body: body);
  }

  Stream<bool> streamSubscriptionStatus(String mangaId) => Stream.value(false);
  Future<void> toggleSubscription(String mangaId) async {}
  Stream<int> streamMangaNotificationCount(String mangaId) => Stream.value(0);
}
