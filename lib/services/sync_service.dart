import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/database_helper.dart';
import 'history_service.dart';

// SyncService: đẩy lịch sử đọc từ SQLite local lên Firestore.
// Thiết kế offline-first: ReaderProvider ghi vào SQLite ngay (nhanh)
// SyncService đẩy lên cloud sau (chạy nền, không block UI)
class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();

  bool _isSyncing = false;

  /// Đẩy tất cả history chưa sync lên Firestore
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
      print(
        '🔄 SyncService: Found ${unsynced.length} pending items. Syncing...',
      );

      // 2. Chạy song song tất cả items — Future.wait đợi tất cả hoàn thành
      final List<Future> syncTasks = unsynced.map((history) async {
        try {
          await HistoryService.instance.saveHistory(
            history,
          ); // Đẩy lên Firestore
          // 3. Đánh dấu synced trong SQLite sau khi thành công
          await DatabaseHelper.instance.markHistoryAsSynced(
            user.uid,
            history.mangaId,
          );
        } catch (e) {
          print('❌ Sync failed for ${history.mangaId}: $e');
          // Không markAsSynced nếu lỗi → sẽ retry lần sau
        }
      }).toList();

      await Future.wait(syncTasks);
      print('✅ SyncService: Sync cycle completed.');
    } catch (e) {
      print('❌ SyncService Error: $e');
    } finally {
      _isSyncing = false; // Luôn unlock, kể cả khi có exception
    }
  }
}
