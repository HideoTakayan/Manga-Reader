import '../../comic/model/models.dart';

/// Reading history domain model
/// Represents a user's reading progress for a comic

class ReadingHistory {
  final String id;
  final String comicId;
  final String chapterId;
  final String comicTitle;
  final String chapterName;
  final String coverUrl;
  final int pageIndex;
  final DateTime readAt;

  const ReadingHistory({
    required this.id,
    required this.comicId,
    required this.chapterId,
    required this.comicTitle,
    required this.chapterName,
    required this.coverUrl,
    this.pageIndex = 0,
    required this.readAt,
  });

  ReadingHistory copyWith({
    String? id,
    String? comicId,
    String? chapterId,
    String? comicTitle,
    String? chapterName,
    String? coverUrl,
    int? pageIndex,
    DateTime? readAt,
  }) {
    return ReadingHistory(
      id: id ?? this.id,
      comicId: comicId ?? this.comicId,
      chapterId: chapterId ?? this.chapterId,
      comicTitle: comicTitle ?? this.comicTitle,
      chapterName: chapterName ?? this.chapterName,
      coverUrl: coverUrl ?? this.coverUrl,
      pageIndex: pageIndex ?? this.pageIndex,
      readAt: readAt ?? this.readAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'comicId': comicId,
      'chapterId': chapterId,
      'comicTitle': comicTitle,
      'chapterName': chapterName,
      'coverUrl': coverUrl,
      'pageIndex': pageIndex,
      'readAt': readAt.toIso8601String(),
    };
  }

  factory ReadingHistory.fromJson(Map<String, dynamic> json) {
    return ReadingHistory(
      id: json['id'] as String,
      comicId: json['comicId'] as String,
      chapterId: json['chapterId'] as String,
      comicTitle: json['comicTitle'] as String,
      chapterName: json['chapterName'] as String,
      coverUrl: json['coverUrl'] as String,
      pageIndex: json['pageIndex'] as int? ?? 0,
      readAt: DateTime.parse(json['readAt'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadingHistory &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ReadingHistory(id: $id, comic: $comicTitle, chapter: $chapterName)';
}
