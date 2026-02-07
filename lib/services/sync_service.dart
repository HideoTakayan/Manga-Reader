import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/database_helper.dart';
import 'history_service.dart';

class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();

  bool _isSyncing = false;

  /// Trigger sync process for pending history items
  Future<void> syncPendingHistory() async {
    // Basic debounce/lock to prevent multiple concurrent syncs
    if (_isSyncing) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _isSyncing = true;
    try {
      // 1. Get unsynced items from Local DB
      final unsynced = await DatabaseHelper.instance.getUnsyncedHistory(
        user.uid,
      );
      if (unsynced.isEmpty) {
        // print('✅ SyncService: No pending items.');
        return;
      }

      print(
        '🔄 SyncService: Found ${unsynced.length} pending items. Syncing...',
      );

      // 2. Push to Cloud (Firestore)
      // Run in parallel for faster sync
      final List<Future> syncTasks = unsynced.map((history) async {
        try {
          await HistoryService.instance.saveHistory(history);
          // 3. Mark as synced locally upon success
          await DatabaseHelper.instance.markHistoryAsSynced(
            user.uid,
            history.mangaId,
          );
        } catch (e) {
          print('❌ Sync failed for ${history.mangaId}: $e');
          // Keep isSynced = 0 to retry later
        }
      }).toList();

      await Future.wait(syncTasks);
      print('✅ SyncService: Sync cycle completed.');
    } catch (e) {
      print('❌ SyncService Error: $e');
    } finally {
      _isSyncing = false;
    }
  }
}
