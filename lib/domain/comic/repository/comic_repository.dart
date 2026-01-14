import '../model/models.dart';

/// Comic repository interface
/// Following the Repository pattern from Clean Architecture
/// This abstracts data access, allowing the domain layer to be independent
/// of data sources (Drive, Firestore, SQLite, etc.)

abstract class ComicRepository {
  /// Get all available comics
  Future<List<Comic>> getComics();

  /// Get a specific comic by ID
  Future<Comic?> getComicById(String id);

  /// Watch all comics as a stream
  Stream<List<Comic>> watchComics();

  /// Get chapters for a specific comic
  Future<List<Chapter>> getChapters(String comicId);

  /// Get a specific chapter by ID
  Future<Chapter?> getChapterById(String chapterId);

  /// Get page URLs for a chapter
  Future<List<String>> getChapterPages(String chapterId);

  /// Update comic information
  Future<void> updateComic(Comic comic);

  /// Search comics by title
  Future<List<Comic>> searchComics(String query);
}
