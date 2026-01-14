import '../model/models.dart';
import '../repository/comic_repository.dart';

/// Use case for getting chapters of a comic
class GetChapters {
  final ComicRepository _repository;

  GetChapters(this._repository);

  /// Get all chapters for a specific comic
  Future<List<Chapter>> call(String comicId) async {
    try {
      return await _repository.getChapters(comicId);
    } catch (e) {
      // Log error in production
      return [];
    }
  }

  /// Get a single chapter by ID
  Future<Chapter?> getById(String chapterId) async {
    try {
      return await _repository.getChapterById(chapterId);
    } catch (e) {
      return null;
    }
  }
}
