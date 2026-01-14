import '../repository/comic_repository.dart';

/// Use case for getting chapter pages
class GetChapterPages {
  final ComicRepository _repository;

  GetChapterPages(this._repository);

  /// Get all page URLs for a specific chapter
  Future<List<String>> call(String chapterId) async {
    try {
      return await _repository.getChapterPages(chapterId);
    } catch (e) {
      // Log error in production
      return [];
    }
  }
}
