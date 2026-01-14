import '../model/models.dart';
import '../repository/comic_repository.dart';

/// Use case for getting a single comic by ID
/// Single-responsibility class following the Interactor pattern from Mihon
class GetComic {
  final ComicRepository _repository;

  GetComic(this._repository);

  /// Get comic by ID, returns null if not found or on error
  Future<Comic?> call(String id) async {
    try {
      return await _repository.getComicById(id);
    } catch (e) {
      // Log error in production
      return null;
    }
  }
}
