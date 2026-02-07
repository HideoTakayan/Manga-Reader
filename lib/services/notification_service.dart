import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ignore_for_file: depend_on_referenced_packages, file_names

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // --- LOCAL NOTIFICATIONS (BACKGROUND DOWNLOAD) ---

  Future<void> initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    // ignore: prefer_const_constructors
    final initSettings = InitializationSettings(android: androidSettings);

    // Fix: Sử dụng named parameters (Syntax mới v18+)
    // ignore: undefined_named_parameter
    await _localNotifications.initialize(
      // ignore: missing_required_argument
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification tap
      },
    );

    // Request permission for Android 13+
    final androidImpl = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();
  }

  /// Hiển thị thanh tiến độ tải xuống
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

    final details = NotificationDetails(android: androidDetails);

    // ignore: undefined_named_parameter
    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  /// Hiển thị thông báo tải xong
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

    final details = NotificationDetails(android: androidDetails);
    final displayTitle = isError ? '❌ $title' : '✅ $title';

    // ignore: undefined_named_parameter
    await _localNotifications.show(
      id: id,
      title: displayTitle,
      body: body,
      notificationDetails: details,
    );
  }

  /// Hủy thông báo
  Future<void> cancelNtification(int id) async {
    // Fix: Cancel cũng dùng named parameter 'id'
    // ignore: undefined_named_parameter
    await _localNotifications.cancel(id: id);
  }

  // --- FIRESTORE NOTIFICATIONS ---

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
        final followingSnap = await _db
            .collection('users')
            .doc(userId)
            .collection('following')
            .get();

        final followingIds = followingSnap.docs.map((d) => d.id).toSet();

        final filteredNotifications = snapshot.docs
            .where((doc) {
              final data = doc.data();
              final mangaId = data['mangaId'] ?? data['comicId'];
              if (mangaId == null || mangaId == '') return true;
              return followingIds.contains(mangaId);
            })
            .map((doc) => {...doc.data(), 'id': doc.id})
            .toList();

        yield filteredNotifications;
      } catch (e) {
        // ignore: avoid_print
        print('Error filtering notifications: $e');
        yield [];
      }
    }
  }

  Future<void> markAsRead(String notificationId) async {
    // Stub
  }

  // --- SYSTEM NOTIFICATIONS LOGIC ---

  final Set<String> _processedIds = {};
  DateTime _startTime = DateTime.now();
  StreamSubscription? _subscription;

  Future<void> initialize() async {
    await initLocalNotifications();

    // Listen to Auth changes to start/stop notification listener
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
        // Only notify for items created/received AFTER app start to avoid spam
        if (timestamp != null && timestamp.isAfter(_startTime)) {
          _processedIds.add(id);
          showGeneralNotification(
            title: n['title'] ?? 'Thông báo',
            body: n['body'] ?? '',
          );
        } else {
          // Mark old items as processed
          _processedIds.add(id);
        }
      }
    });
  }

  void _stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _processedIds.clear();
    _startTime = DateTime.now(); // Reset start time on re-login
  }

  /// Show standard system notification
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

    final details = NotificationDetails(android: androidDetails);

    // Use a unique ID or hash
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  // --- STUB METHODS ---

  Future<void> notifySubscribers({
    required String mangaId,
    required String title,
    required String body,
  }) async {
    // Also trigger local notification directly if called client-side
    await showGeneralNotification(title: title, body: body);
  }

  Stream<bool> streamSubscriptionStatus(String mangaId) {
    return Stream.value(false);
  }

  Future<void> toggleSubscription(String mangaId) async {}

  Stream<int> streamMangaNotificationCount(String mangaId) {
    return Stream.value(0);
  }
}
