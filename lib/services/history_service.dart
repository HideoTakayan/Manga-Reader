import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models.dart';

class HistoryService {
  static final HistoryService instance = HistoryService._();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  HistoryService._();

  // Save history to Cloud
  Future<void> saveHistory(ReadingHistory history) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return; // Not logged in

    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('history')
          .doc(history.comicId)
          .set({
            ...history.toMap(),
            'updatedAt': FieldValue.serverTimestamp(), // Use server time
          });
    } catch (e) {
      print('Error saving cloud history: $e');
    }
  }

  // Get single comic history
  Future<ReadingHistory?> getHistoryForComic(String comicId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    try {
      final doc = await _db
          .collection('users')
          .doc(uid)
          .collection('history')
          .doc(comicId)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        // Convert Timestamp to int (milliseconds) for compatibility
        if (data['updatedAt'] is Timestamp) {
          data['updatedAt'] =
              (data['updatedAt'] as Timestamp).millisecondsSinceEpoch;
        }
        return ReadingHistory.fromMap(data);
      }
    } catch (e) {
      print('Error fetching cloud history: $e');
    }
    return null;
  }

  // Get all history
  Future<List<ReadingHistory>> getAllHistory() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return [];

    try {
      final snapshot = await _db
          .collection('users')
          .doc(uid)
          .collection('history')
          .orderBy('updatedAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        if (data['updatedAt'] is Timestamp) {
          data['updatedAt'] =
              (data['updatedAt'] as Timestamp).millisecondsSinceEpoch;
        }
        return ReadingHistory.fromMap(data);
      }).toList();
    } catch (e) {
      print('Error fetching all cloud history: $e');
      return [];
    }
  }

  // Delete history
  Future<void> deleteHistory(String comicId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('history')
          .doc(comicId)
          .delete();
    } catch (e) {
      print('Error deleting cloud history: $e');
    }
  }
}
