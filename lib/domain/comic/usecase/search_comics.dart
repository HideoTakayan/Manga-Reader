import '../model/models.dart';
import '../repository/comic_repository.dart';

/// Use case for searching comics
class SearchComics {
  final ComicRepository _repository;

  SearchComics(this._repository);

  /// Search comics by query string
  Future<List<Comic>> call(String query) async {
    if (query.trim().isEmpty) return [];
    
    try {
      return await _repository.searchComics(query);
    } catch (e) {
      // Log error in production
      return [];
    }
  }
}
