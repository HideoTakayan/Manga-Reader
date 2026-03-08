/// Model đại diện cho một bộ truyện lấy từ Google Drive (qua catalog.json).
/// Đây là model "online", khác với [Manga] là model cục bộ SQLite.
class CloudManga {
  final String id; // ID thư mục
  final String title;
  final String author;
  final String description;
  final String coverFileId; // ID file ảnh bìa trên Google Drive
  final DateTime updatedAt;
  final List<String> genres;
  final String status;
  final int viewCount;
  final int likeCount;
  final List<String> chapterOrder; // Danh sách ID chương/file theo thứ tự

  CloudManga({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.coverFileId,
    required this.updatedAt,
    this.genres = const [],
    this.status = 'Đang Cập Nhật',
    this.viewCount = 0,
    this.likeCount = 0,
    this.chapterOrder = const [],
  });

  /// Chuyển đối tượng sang Map để ghi vào Firestore hoặc truyền qua API.
  Map<String, dynamic> toMap() {
    // Giữ nguyên các key để tương thích với Firestore nếu cần,
    // nhưng đối tượng logic hiện tại là Manga.
    return {
      'id': id,
      'title': title,
      'author': author,
      'description': description,
      'coverFileId': coverFileId,
      'updatedAt': updatedAt.toIso8601String(),
      'genres': genres,
      'status': status,
      'viewCount': viewCount,
      'likeCount': likeCount,
      'chapterOrder': chapterOrder,
    };
  }

  /// Tạo đối tượng CloudManga từ Map đọc ra từ catalog.json hoặc Firestore.
  factory CloudManga.fromMap(Map<String, dynamic> map) {
    return CloudManga(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      author: map['author'] ?? '',
      description: map['description'] ?? '',
      coverFileId: map['coverFileId'] ?? '',
      updatedAt: DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
      genres: List<String>.from(map['genres'] ?? []),
      status: map['status'] ?? 'Đang Cập Nhật',
      viewCount: map['viewCount'] ?? 0,
      likeCount: map['likeCount'] ?? 0,
      chapterOrder: List<String>.from(map['chapterOrder'] ?? []),
    );
  }
}

/// Model đại diện cho một chương truyện lấy từ Google Drive.
/// Mỗi chương là một file nén (.zip/.cbz) hoặc PDF nằm trong thư mục trên Drive.
class CloudChapter {
  final String id; // ID file
  final String title;
  final String fileId;
  final String fileType; // Loại file: 'zip', 'cbz', 'epub'
  final int sizeBytes;
  final DateTime uploadedAt;
  final int viewCount;

  CloudChapter({
    required this.id,
    required this.title,
    required this.fileId,
    required this.fileType,
    this.sizeBytes = 0,
    required this.uploadedAt,
    this.viewCount = 0,
  });

  /// Chuyển đối tượng sang Map để lưu hoặc truyền đi.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'fileId': fileId,
      'fileType': fileType,
      'sizeBytes': sizeBytes,
      'uploadedAt': uploadedAt.toIso8601String(),
      'viewCount': viewCount,
    };
  }

  /// Tạo đối tượng CloudChapter từ Map (đọc từ catalog.json hoặc Drive API).
  factory CloudChapter.fromMap(Map<String, dynamic> map) {
    return CloudChapter(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      fileId: map['fileId'] ?? '',
      fileType: map['fileType'] ?? 'zip',
      sizeBytes: map['sizeBytes'] ?? 0,
      uploadedAt: DateTime.tryParse(map['uploadedAt'] ?? '') ?? DateTime.now(),
      viewCount: map['viewCount'] ?? 0,
    );
  }

  /// Hai CloudChapter được coi là giống nhau nếu cùng ID file.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CloudChapter && other.id == id;
  }

  @override
  int get hashCode => id.hashCode; // Dùng id file làm khóa hash
}
