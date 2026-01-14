import '../comic/model/models.dart';

/// Library item model representing a followed/saved comic
class LibraryItem {
  final String id;
  final String comicId;
  final String title;
  final String coverUrl;
  final DateTime addedAt;
  final int unreadChapters;

  const LibraryItem({
    required this.id,
    required this.comicId,
    required this.title,
    required this.coverUrl,
    required this.addedAt,
    this.unreadChapters = 0,
  });

  LibraryItem copyWith({
    String? id,
    String? comicId,
    String? title,
    String? coverUrl,
    DateTime? addedAt,
    int? unreadChapters,
  }) {
    return LibraryItem(
      id: id ?? this.id,
      comicId: comicId ?? this.comicId,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      addedAt: addedAt ?? this.addedAt,
      unreadChapters: unreadChapters ?? this.unreadChapters,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'comicId': comicId,
      'title': title,
      'coverUrl': coverUrl,
      'addedAt': addedAt.toIso8601String(),
      'unreadChapters': unreadChapters,
    };
  }

  factory LibraryItem.fromJson(Map<String, dynamic> json) {
    return LibraryItem(
      id: json['id'] as String,
      comicId: json['comicId'] as String,
      title: json['title'] as String,
      coverUrl: json['coverUrl'] as String,
      addedAt: DateTime.parse(json['addedAt'] as String),
      unreadChapters: json['unreadChapters'] as int? ?? 0,
    );
  }

  /// Create from a Comic
  factory LibraryItem.fromComic(Comic comic) {
    return LibraryItem(
      id: comic.id,
      comicId: comic.id,
      title: comic.title,
      coverUrl: comic.coverUrl,
      addedAt: DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryItem &&
          runtimeType == other.runtimeType &&
          comicId == other.comicId;

  @override
  int get hashCode => comicId.hashCode;

  @override
  String toString() => 'LibraryItem(comicId: $comicId, title: $title)';
}
