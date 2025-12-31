class CloudComic {
  final String id; // Folder ID
  final String title;
  final String author;
  final String description;
  final String coverFileId; // ID file ảnh bìa trên Drive
  final DateTime updatedAt;

  CloudComic({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.coverFileId,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'description': description,
      'coverFileId': coverFileId,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory CloudComic.fromMap(Map<String, dynamic> map) {
    return CloudComic(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      author: map['author'] ?? '',
      description: map['description'] ?? '',
      coverFileId: map['coverFileId'] ?? '',
      updatedAt: DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
    );
  }
}

class CloudChapter {
  final String id; // File ID
  final String title;
  final String fileId;
  final String fileType; // 'zip', 'cbz', 'epub'
  final int sizeBytes;
  final DateTime uploadedAt;

  CloudChapter({
    required this.id,
    required this.title,
    required this.fileId,
    required this.fileType,
    this.sizeBytes = 0,
    required this.uploadedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'fileId': fileId,
      'fileType': fileType,
      'sizeBytes': sizeBytes,
      'uploadedAt': uploadedAt.toIso8601String(),
    };
  }

  factory CloudChapter.fromMap(Map<String, dynamic> map) {
    return CloudChapter(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      fileId: map['fileId'] ?? '',
      fileType: map['fileType'] ?? 'zip',
      sizeBytes: map['sizeBytes'] ?? 0,
      uploadedAt: DateTime.tryParse(map['uploadedAt'] ?? '') ?? DateTime.now(),
    );
  }
}
