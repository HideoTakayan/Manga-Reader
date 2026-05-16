import '../../data/models_cloud.dart';

class MetadataValidationIssue {
  final String title;
  final String message;
  final MetadataIssueSeverity severity;

  const MetadataValidationIssue({
    required this.title,
    required this.message,
    required this.severity,
  });
}

enum MetadataIssueSeverity { warning, error }

class MetadataValidator {
  MetadataValidator._();

  static List<MetadataValidationIssue> validateChapters(
    List<CloudChapter> chapters,
  ) {
    final issues = <MetadataValidationIssue>[];
    final idCounts = <String, int>{};
    final titleCounts = <String, int>{};

    for (final chapter in chapters) {
      idCounts.update(chapter.id, (value) => value + 1, ifAbsent: () => 1);
      titleCounts.update(
        _normalize(chapter.title),
        (value) => value + 1,
        ifAbsent: () => 1,
      );

      if (chapter.id.trim().isEmpty) {
        issues.add(
          const MetadataValidationIssue(
            title: 'Chapter thiếu ID',
            message: 'Có chapter không có ID.',
            severity: MetadataIssueSeverity.error,
          ),
        );
      }
      if (chapter.title.trim().isEmpty) {
        issues.add(
          MetadataValidationIssue(
            title: 'Chapter thiếu title',
            message: 'Chapter ${chapter.id} chưa có title.',
            severity: MetadataIssueSeverity.error,
          ),
        );
      }
      if (chapter.fileType.trim().isEmpty) {
        issues.add(
          MetadataValidationIssue(
            title: 'Chapter thiếu fileType',
            message: '"${chapter.title}" chưa có fileType.',
            severity: MetadataIssueSeverity.warning,
          ),
        );
      }
    }

    idCounts.forEach((id, count) {
      if (id.isNotEmpty && count > 1) {
        issues.add(
          MetadataValidationIssue(
            title: 'Trùng chapter ID',
            message: 'Có $count chapter cùng ID "$id".',
            severity: MetadataIssueSeverity.error,
          ),
        );
      }
    });

    titleCounts.forEach((title, count) {
      if (title.isNotEmpty && count > 1) {
        issues.add(
          MetadataValidationIssue(
            title: 'Trùng chapter title',
            message: 'Có $count chapter cùng title "$title".',
            severity: MetadataIssueSeverity.warning,
          ),
        );
      }
    });

    return issues;
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
