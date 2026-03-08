import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// BackgroundService: giữ process Android sống trong khi DownloadService tải file.
class BackgroundService {
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

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
        onStart:
            onStart, // Hàm này chạy trong Isolate riêng biệt với main Isolate
        autoStart:
            false, // Không tự chạy khi app mở — chỉ khi DownloadService gọi start()
        isForegroundMode:
            true, // Foreground Service: Android không kill khi app ở nền
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

  // @pragma('vm:entry-point'): ngăn tree-shaker xóa hàm này khi build release
  // Bắt buộc cho hàm được gọi từ native code hoặc Isolate khác
  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    // Isolate này chỉ giữ Foreground Service sống — không tải file ở đây.
    // DownloadService chạy trong main Isolate, BackgroundService ngăn Android kill nó.
    DartPluginRegistrant.ensureInitialized();

    // Lắng nghe signal 'stopService' từ BackgroundService.stop()
    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    // Cập nhật notification mỗi 30s để hệ thống biết service còn sống
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
    return true; // Trả về true = iOS cho phép tiếp tục chạy ngắn ngủi
  }

  /// Khởi động service — chỉ start nếu chưa chạy (tránh double start)
  static Future<void> start() async {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      debugPrint('🚀 Starting Background Service to keep app alive');
      await service.startService();
    }
  }

  /// Dừng service — gửi event 'stopService' để Isolate tự dọn dẹp
  static Future<void> stop() async {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      debugPrint('KV Stopping Background Service');
      service.invoke(
        'stopService',
      ); // invoke thay vì trực tiếp stop để Isolate xử lý cleanup
    }
  }
}
