import '../model/library_item.dart';

/// Library repository interface
/// Abstracts access to user's followed/saved comics library

abstract class LibraryRepository {
  /// Get all items in library
  Future<List<LibraryItem>> getLibrary();

  /// Watch library changes as a stream
  Stream<List<LibraryItem>> watchLibrary();

  /// Check if a comic is in library
  Future<bool> isInLibrary(String comicId);

  /// Add comic to library
  Future<void> addToLibrary(LibraryItem item);

  /// Remove comic from library
  Future<void> removeFromLibrary(String comicId);

  /// Toggle comic in library (add if not present, remove if present)
  Future<bool> toggleLibrary(LibraryItem item);
}
