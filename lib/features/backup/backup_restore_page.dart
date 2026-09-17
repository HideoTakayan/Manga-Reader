import 'dart:io';
import 'package:flutter/material.dart';

import '../../services/backup_service.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  bool _isBusy = false;
  List<File> _backupFiles = [];

  @override
  void initState() {
    super.initState();
    _loadBackupFiles();
  }

  Future<void> _loadBackupFiles() async {
    final files = await BackupService.instance.getBackupFiles();
    if (mounted) {
      setState(() => _backupFiles = files);
    }
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã xảy ra lỗi: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _exportBackup() async {
    await _runBusy(() async {
      final path = await BackupService.instance.exportToJsonFile();
      if (!mounted) return;
      if (path != null) {
        await _loadBackupFiles();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã lưu backup: ${path.split(RegExp(r'[\\/]')).last}'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không thể tạo file sao lưu (vui lòng kiểm tra quyền bộ nhớ)',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  Future<void> _importBackup({String? filePath}) async {
    final replace = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Khôi phục dữ liệu',
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Bạn muốn gộp dữ liệu backup vào dữ liệu hiện tại, hay thay thế toàn bộ dữ liệu local?',
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.primary,
              foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Gộp', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Thay thế', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (replace == null) return;

    await _runBusy(() async {
      final result = await BackupService.instance.importFromJsonFile(
        filePath: filePath,
        replaceExisting: replace,
      );
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã hủy chọn file sao lưu hoặc file không đúng định dạng'),
          ),
        );
        return;
      }
      final novelMsg = result.importedNovelsCount > 0
          ? ' (bao gồm ${result.importedNovelsCount} truyện chữ)'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Đã khôi phục thành công ${result.totalRows} mục dữ liệu$novelMsg',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  Future<void> _deleteBackup(File file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Xóa bản sao lưu?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(ctx).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Bạn có chắc muốn xóa file "${file.path.split(RegExp(r'[\\/]')).last}" khỏi máy?',
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Xóa', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _runBusy(() async {
        await BackupService.instance.deleteBackupFile(file.path);
        await _loadBackupFiles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã xóa bản sao lưu'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatFileDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dữ liệu được backup',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const _BackupInfoRow('Thư viện và danh mục local'),
                  const _BackupInfoRow('Lịch sử đọc và vị trí đọc'),
                  const _BackupInfoRow('Bookmark reader'),
                  const _BackupInfoRow('Metadata manga đã cache'),
                  const _BackupInfoRow('Cấu hình giọng đọc AI (TTS) & Tuỳ chọn'),
                  const SizedBox(height: 8),
                  Text(
                    'File truyện đã tải không nằm trong backup JSON để tránh file quá nặng.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: _isBusy ? null : _exportBackup,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('Tạo bản sao lưu mới (Export)', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: _isBusy ? null : () => _importBackup(),
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Chọn file JSON từ máy (Import)', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (_isBusy) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          const SizedBox(height: 24),

          // Danh sách các bản sao lưu đã có trên máy
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Bản sao lưu trên máy (${_backupFiles.length})',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Làm mới danh sách',
                onPressed: _loadBackupFiles,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_backupFiles.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.indigoAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.cloud_off_outlined,
                      size: 36,
                      color: Colors.indigoAccent,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Chưa có bản sao lưu nào trên máy',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tạo bản sao lưu để bảo vệ dữ liệu đọc và cài đặt cá nhân của bạn',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ..._backupFiles.map((file) {
              final fileName = file.path.split(RegExp(r'[\\/]')).last;
              int size = 0;
              DateTime modified = DateTime.now();
              try {
                size = file.lengthSync();
                modified = file.lastModifiedSync();
              } catch (_) {}

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                    child: Icon(Icons.description_outlined, color: Theme.of(context).colorScheme.primary, size: 22),
                  ),
                  title: Text(
                    fileName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_formatFileDate(modified)} • ${_formatFileSize(size)}',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Khôi phục bản sao lưu này',
                        icon: Icon(Icons.restore, color: Theme.of(context).colorScheme.primary, size: 22),
                        onPressed: _isBusy ? null : () => _importBackup(filePath: file.path),
                      ),
                      IconButton(
                        tooltip: 'Xóa bản sao lưu',
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        onPressed: _isBusy ? null : () => _deleteBackup(file),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _BackupInfoRow extends StatelessWidget {
  final String text;

  const _BackupInfoRow(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            color: Theme.of(context).colorScheme.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
