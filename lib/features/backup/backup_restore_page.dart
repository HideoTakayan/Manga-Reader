import 'package:flutter/material.dart';

import '../../services/backup_service.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  bool _isBusy = false;

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _exportBackup() async {
    await _runBusy(() async {
      final path = await BackupService.instance.exportToJsonFile();
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã lưu backup: $path')),
      );
    });
  }

  Future<void> _importBackup() async {
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import backup'),
        content: const Text(
          'Bạn muốn gộp dữ liệu backup vào dữ liệu hiện tại, hay thay thế toàn bộ dữ liệu local?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Gộp'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Thay thế', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (replace == null) return;

    await _runBusy(() async {
      final result = await BackupService.instance.importFromJsonFile(
        replaceExisting: replace,
      );
      if (!mounted || result == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã import ${result.totalRows} dòng dữ liệu')),
      );
    });
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
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dữ liệu được backup',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const _BackupInfoRow('Thư viện và danh mục local'),
                  const _BackupInfoRow('Lịch sử đọc và vị trí đọc'),
                  const _BackupInfoRow('Bookmark reader'),
                  const _BackupInfoRow('Metadata manga đã cache'),
                  const SizedBox(height: 8),
                  Text(
                    'File truyện đã tải không nằm trong backup JSON để tránh file quá nặng.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isBusy ? null : _exportBackup,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('Export backup JSON'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isBusy ? null : _importBackup,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Import backup JSON'),
          ),
          if (_isBusy) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
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
