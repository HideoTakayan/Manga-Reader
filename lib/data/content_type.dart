enum MangaContentType { manga, novel }

MangaContentType parseContentType(
  dynamic value, {
  List<String> genres = const [],
}) {
  final raw = value?.toString().trim().toLowerCase();
  if (raw == 'novel' ||
      raw == 'text' ||
      raw == 'text_novel' ||
      raw == 'light_novel') {
    return MangaContentType.novel;
  }
  if (raw == 'manga' || raw == 'comic' || raw == 'comics') {
    return MangaContentType.manga;
  }

  final normalizedGenres = genres.map((genre) => genre.toLowerCase().trim());
  final hasNovelGenre = normalizedGenres.any(
    (genre) =>
        genre == 'novel' ||
        genre == 'light novel' ||
        genre == 'web novel' ||
        genre == 'truyen chu' ||
        genre == 'truyện chữ',
  );
  return hasNovelGenre ? MangaContentType.novel : MangaContentType.manga;
}

String contentTypeToJson(MangaContentType type) => type.name;

extension MangaContentTypeX on MangaContentType {
  bool get isNovel => this == MangaContentType.novel;
  bool get isManga => this == MangaContentType.manga;

  String get label => switch (this) {
    MangaContentType.manga => 'Truyện tranh',
    MangaContentType.novel => 'Novel',
  };

  String get unitLabel => switch (this) {
    MangaContentType.manga => 'Chương',
    MangaContentType.novel => 'Tập',
  };
}
