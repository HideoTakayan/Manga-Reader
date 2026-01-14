import '../../comic/model/models.dart';
import '../model/library_item.dart';
import '../repository/library_repository.dart';

/// Use case for toggling a comic in the library
class ToggleLibrary {
  final LibraryRepository _repository;

  ToggleLibrary(this._repository);

  /// Toggle comic in library
  /// Returns true if added, false if removed
  Future<bool> call(Comic comic) async {
    try {
      final item = LibraryItem.fromComic(comic);
      return await _repository.toggleLibrary(item);
    } catch (e) {
      return false;
    }
  }

  /// Explicitly add to library
  Future<void> add(Comic comic) async {
    try {
      final item = LibraryItem.fromComic(comic);
      await _repository.addToLibrary(item);
    } catch (e) {
      // Log error in production
    }
  }

  /// Explicitly remove from library
  Future<void> remove(String comicId) async {
    try {
      await _repository.removeFromLibrary(comicId);
    } catch (e) {
      // Log error in production
    }
  }
}
