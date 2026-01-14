/// Chapter domain model
/// Represents a single chapter within a comic

class Chapter {
  final String id;
  final String comicId;
  final String name;
  final int order;
  final List<String> pageUrls;
  final DateTime? uploadedAt;

  const Chapter({
    required this.id,
    required this.comicId,
    required this.name,
    required this.order,
    this.pageUrls = const [],
    this.uploadedAt,
  });

  Chapter copyWith({
    String? id,
    String? comicId,
    String? name,
    int? order,
    List<String>? pageUrls,
    DateTime? uploadedAt,
  }) {
    return Chapter(
      id: id ?? this.id,
      comicId: comicId ?? this.comicId,
      name: name ?? this.name,
      order: order ?? this.order,
      pageUrls: pageUrls ?? this.pageUrls,
      uploadedAt: uploadedAt ?? this.uploadedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'comicId': comicId,
      'name': name,
      'order': order,
      'pageUrls': pageUrls,
      'uploadedAt': uploadedAt?.toIso8601String(),
    };
  }

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      id: json['id'] as String,
      comicId: json['comicId'] as String,
      name: json['name'] as String,
      order: json['order'] as int? ?? 0,
      pageUrls: (json['pageUrls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      uploadedAt: json['uploadedAt'] != null
          ? DateTime.tryParse(json['uploadedAt'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Chapter && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Chapter(id: $id, name: $name, order: $order)';
}
