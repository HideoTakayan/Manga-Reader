import '../model/models.dart';
import '../repository/comic_repository.dart';

/// Use case for getting all comics
/// Supports both one-shot fetch and reactive stream
class GetComics {
  final ComicRepository _repository;

  GetComics(this._repository);

  /// Get all comics as a list
  Future<List<Comic>> call() async {
    try {
      return await _repository.getComics();
    } catch (e) {
      // Log error in production
      return [];
    }
  }

  /// Watch comics as a stream for reactive updates
  Stream<List<Comic>> watch() {
    return _repository.watchComics();
  }
}
