import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../data/database_helper.dart';
import 'history_service.dart';

// SyncService: đẩy lịch sử đọc từ SQLite local lên Firestore.
// Thiết kế offline-first: ReaderProvider ghi vào SQLite ngay (nhanh)
// SyncService đẩy lên cloud sau (chạy nền, không block UI)
class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();

  bool _isSyncing = false;

  /// Đẩy tất cả history chưa sync lên Firestore — xử lý theo từng batch 10 items.
  /// Tránh Firestore rate-limit khi có nhiều items tích lũy offline.
  Future<void> syncPendingHistory() async {
    if (_isSyncing) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _isSyncing = true;
    try {
      // 1. Lấy items chưa sync từ SQLite (isSynced = 0)
      final unsynced = await DatabaseHelper.instance.getUnsyncedHistory(
        user.uid,
      );
      if (unsynced.isEmpty) return;
      debugPrint(
        '🔄 SyncService: Found ${unsynced.length} pending items. Syncing...',
      );

      // 2. Xử lý theo batch 10 items — tránh 50+ Firestore writes đồng thời
      const batchSize = 10;
      int synced = 0;
      for (int i = 0; i < unsynced.length; i += batchSize) {
        final chunk = unsynced.skip(i).take(batchSize).toList();
        await Future.wait(
          chunk.map((history) async {
            try {
              await HistoryService.instance.saveHistory(history); // Firestore
              await DatabaseHelper.instance.markHistoryAsSynced(
                user.uid,
                history.mangaId,
              );
              synced++;
            } catch (e) {
              debugPrint('❌ Sync failed for ${history.mangaId}: $e');
              // Không markAsSynced nếu lỗi → retry lần sau
            }
          }),
        );
        // Delay nhỏ giữa các batch — giảm tải Firestore
        if (i + batchSize < unsynced.length) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
      debugPrint('✅ SyncService: Synced $synced/${unsynced.length} items.');
    } catch (e) {
      debugPrint('❌ SyncService Error: $e');
    } finally {
      _isSyncing = false; // Luôn unlock, kể cả khi có exception
    }
  }
}
