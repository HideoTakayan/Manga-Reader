import '../model/reading_history.dart';
import '../repository/history_repository.dart';

/// Use case for updating reading progress
class UpdateReadingProgress {
  final HistoryRepository _repository;

  UpdateReadingProgress(this._repository);

  /// Update or create reading progress for a chapter
  Future<void> call({
    required String comicId,
    required String chapterId,
    required String comicTitle,
    required String chapterName,
    required String coverUrl,
    required int pageIndex,
  }) async {
    try {
      final history = ReadingHistory(
        id: '${comicId}_$chapterId',
        comicId: comicId,
        chapterId: chapterId,
        comicTitle: comicTitle,
        chapterName: chapterName,
        coverUrl: coverUrl,
        pageIndex: pageIndex,
        readAt: DateTime.now(),
      );
      await _repository.upsertHistory(history);
    } catch (e) {
      // Log error in production
    }
  }
}
