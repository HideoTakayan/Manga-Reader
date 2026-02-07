import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BackgroundService {
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    // Channel cho Service "giữ sống" app
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'background_keep_alive',
      'Background Service',
      description: 'Giữ ứng dụng chạy ngầm',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        // Hàm này chạy ở Isolate riêng
        onStart: onStart,

        // Không tự chạy khi mở app, chỉ chạy khi DownloadService gọi
        autoStart: false,
        isForegroundMode: true,

        notificationChannelId: 'background_keep_alive',
        initialNotificationTitle: 'Manga Reader',
        initialNotificationContent: 'Đang duy trì kết nối...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    // Isolate này chỉ có nhiệm vụ giữ Process ở trạng thái Foreground Service
    // để Android không kill Main Isolate (nơi đang tải file).

    DartPluginRegistrant.ensureInitialized();

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    // Timer giữ alive (nếu cần)
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          service.setForegroundNotificationInfo(
            title: 'Manga Reader',
            content: 'Đang xử lý tác vụ ngầm...',
          );
        }
      }
    });
  }

  @pragma('vm:entry-point')
  static bool onIosBackground(ServiceInstance service) {
    return true;
  }

  static Future<void> start() async {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      debugPrint('🚀 Starting Background Service to keep app alive');
      await service.startService();
    }
  }

  static Future<void> stop() async {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      debugPrint('KV Stopping Background Service');
      service.invoke('stopService');
    }
  }
}
