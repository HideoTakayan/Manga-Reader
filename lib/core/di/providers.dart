/// Dependency Injection providers
/// Riverpod providers for use cases and repositories
/// Following pattern from implementation guidelines

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/comic/comic.dart';
import '../../domain/history/history.dart';
import '../../domain/library/library.dart';

// ============================================
// Repository Providers
// These will be overridden with implementations
// ============================================

/// Comic repository provider - to be overridden with implementation
final comicRepositoryProvider = Provider<ComicRepository>((ref) {
  throw UnimplementedError(
    'ComicRepository must be overridden with an implementation',
  );
});

/// History repository provider - to be overridden with implementation
final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  throw UnimplementedError(
    'HistoryRepository must be overridden with an implementation',
  );
});

/// Library repository provider - to be overridden with implementation
final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  throw UnimplementedError(
    'LibraryRepository must be overridden with an implementation',
  );
});

// ============================================
// Comic Use Cases
// ============================================

final getComicProvider = Provider<GetComic>((ref) {
  return GetComic(ref.watch(comicRepositoryProvider));
});

final getComicsProvider = Provider<GetComics>((ref) {
  return GetComics(ref.watch(comicRepositoryProvider));
});

final getChaptersProvider = Provider<GetChapters>((ref) {
  return GetChapters(ref.watch(comicRepositoryProvider));
});

final getChapterPagesProvider = Provider<GetChapterPages>((ref) {
  return GetChapterPages(ref.watch(comicRepositoryProvider));
});

final searchComicsProvider = Provider<SearchComics>((ref) {
  return SearchComics(ref.watch(comicRepositoryProvider));
});

// ============================================
// History Use Cases
// ============================================

final getHistoryProvider = Provider<GetHistory>((ref) {
  return GetHistory(ref.watch(historyRepositoryProvider));
});

final updateReadingProgressProvider = Provider<UpdateReadingProgress>((ref) {
  return UpdateReadingProgress(ref.watch(historyRepositoryProvider));
});

// ============================================
// Library Use Cases
// ============================================

final getLibraryProvider = Provider<GetLibrary>((ref) {
  return GetLibrary(ref.watch(libraryRepositoryProvider));
});

final toggleLibraryProvider = Provider<ToggleLibrary>((ref) {
  return ToggleLibrary(ref.watch(libraryRepositoryProvider));
});
