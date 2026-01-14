import '../model/reading_history.dart';
import '../repository/history_repository.dart';

/// Use case for getting reading history
class GetHistory {
  final HistoryRepository _repository;

  GetHistory(this._repository);

  /// Get all history entries
  Future<List<ReadingHistory>> call() async {
    try {
      return await _repository.getHistory();
    } catch (e) {
      return [];
    }
  }

  /// Watch history changes
  Stream<List<ReadingHistory>> watch() {
    return _repository.watchHistory();
  }

  /// Get history for a specific comic
  Future<ReadingHistory?> forComic(String comicId) async {
    try {
      return await _repository.getHistoryForComic(comicId);
    } catch (e) {
      return null;
    }
  }
}
