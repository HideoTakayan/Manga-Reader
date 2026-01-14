/// Comic domain model
/// Immutable representation of a comic/manga

class Comic {
  final String id;
  final String title;
  final String coverUrl;
  final String? author;
  final String? description;
  final List<String> genres;

  const Comic({
    required this.id,
    required this.title,
    required this.coverUrl,
    this.author,
    this.description,
    this.genres = const [],
  });

  Comic copyWith({
    String? id,
    String? title,
    String? coverUrl,
    String? author,
    String? description,
    List<String>? genres,
  }) {
    return Comic(
      id: id ?? this.id,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      author: author ?? this.author,
      description: description ?? this.description,
      genres: genres ?? this.genres,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'coverUrl': coverUrl,
      'author': author,
      'description': description,
      'genres': genres,
    };
  }

  factory Comic.fromJson(Map<String, dynamic> json) {
    return Comic(
      id: json['id'] as String,
      title: json['title'] as String,
      coverUrl: json['coverUrl'] as String,
      author: json['author'] as String?,
      description: json['description'] as String?,
      genres: _parseGenres(json['genres']),
    );
  }

  static List<String> _parseGenres(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String) return raw.split(',').map((e) => e.trim()).toList();
    return [];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Comic && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Comic(id: $id, title: $title)';
}
