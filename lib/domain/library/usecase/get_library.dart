import '../model/library_item.dart';
import '../repository/library_repository.dart';

/// Use case for getting library items
class GetLibrary {
  final LibraryRepository _repository;

  GetLibrary(this._repository);

  /// Get all library items
  Future<List<LibraryItem>> call() async {
    try {
      return await _repository.getLibrary();
    } catch (e) {
      return [];
    }
  }

  /// Watch library changes
  Stream<List<LibraryItem>> watch() {
    return _repository.watchLibrary();
  }

  /// Check if comic is in library
  Future<bool> contains(String comicId) async {
    try {
      return await _repository.isInLibrary(comicId);
    } catch (e) {
      return false;
    }
  }
}
