import '../model/reading_history.dart';

/// History repository interface
/// Abstracts access to reading history data

abstract class HistoryRepository {
  /// Get all reading history entries
  Future<List<ReadingHistory>> getHistory();

  /// Watch history changes as a stream
  Stream<List<ReadingHistory>> watchHistory();

  /// Get history for a specific comic
  Future<ReadingHistory?> getHistoryForComic(String comicId);

  /// Add or update reading history
  Future<void> upsertHistory(ReadingHistory history);

  /// Delete specific history entry
  Future<void> deleteHistory(String id);

  /// Clear all history
  Future<void> clearHistory();
}
