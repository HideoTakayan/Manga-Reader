import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/models_cloud.dart';

class ReportsListPage extends StatefulWidget {
  const ReportsListPage({super.key});

  @override
  State<ReportsListPage> createState() => _ReportsListPageState();
}

class _ReportsListPageState extends State<ReportsListPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String _statusFilter = 'pending';

  Future<void> _resolveReport(String reportId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn cần đăng nhập admin để xử lý lỗi.')),
      );
      return;
    }

    try {
      await _db.collection('reports').doc(reportId).update({
        'status': 'resolved',
        'resolvedBy': uid,
        'resolvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã đánh dấu xử lý thành công!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _reopenReport(String reportId) async {
    try {
      await _db.collection('reports').doc(reportId).update({
        'status': 'pending',
        'resolvedBy': FieldValue.delete(),
        'resolvedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã mở lại báo cáo (chờ xử lý)'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _deleteReport(String reportId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Xóa báo cáo này?',
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Báo cáo này sẽ bị xóa vĩnh viễn khỏi hệ thống.',
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
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

    if (confirm != true) return;

    try {
      await _db.collection('reports').doc(reportId).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã xóa báo cáo'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  void _showReportDetails(Report report) {
    final createdAt = DateFormat('dd/MM/yyyy HH:mm').format(report.createdAt);
    final resolvedAt = report.resolvedAt == null
        ? ''
        : DateFormat('dd/MM/yyyy HH:mm').format(report.resolvedAt!);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Chi tiết báo lỗi',
          style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(ctx).colorScheme.onSurface),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(
                label: 'Truyện',
                value: report.mangaTitle,
                canCopy: true,
              ),
              if (report.chapterTitle.isNotEmpty)
                _DetailRow(
                  label: 'Chương',
                  value: report.chapterTitle,
                  canCopy: true,
                ),
              if (report.chapterId.isNotEmpty)
                _DetailRow(
                  label: 'ID chương',
                  value: report.chapterId,
                  canCopy: true,
                ),
              _DetailRow(label: 'Loại reader', value: report.readerType),
              _DetailRow(
                label: 'Trang',
                value: report.totalPages > 0
                    ? '${report.pageIndex + 1}/${report.totalPages}'
                    : 'Không rõ',
              ),
              _DetailRow(label: 'Loại lỗi', value: report.reason),
              _DetailRow(label: 'Ngày gửi', value: createdAt),
              if (resolvedAt.isNotEmpty)
                _DetailRow(label: 'Đã xử lý lúc', value: resolvedAt),
              if (report.resolvedBy.isNotEmpty)
                _DetailRow(label: 'Người xử lý', value: report.resolvedBy),
              const SizedBox(height: 12),
              const Text('Mô tả', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Text(
                  report.description.isEmpty
                      ? 'Không có mô tả'
                      : report.description,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              IconButton(
                tooltip: 'Xóa báo cáo',
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () {
                  Navigator.pop(ctx);
                  _deleteReport(report.id);
                },
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng'),
              ),
              const SizedBox(width: 8),
              if (report.status == 'pending')
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _resolveReport(report.id);
                  },
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Đã xử lý'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _reopenReport(report.id);
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Mở lại'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<Report> _filterReports(List<QueryDocumentSnapshot> docs) {
    final reports = docs
        .map(
          (doc) => Report.fromMap(doc.data() as Map<String, dynamic>, doc.id),
        )
        .toList();
    if (_statusFilter == 'all') return reports;
    return reports.where((report) => report.status == _statusFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trung tâm báo lỗi')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pending', label: Text('Chờ xử lý')),
                ButtonSegment(value: 'resolved', label: Text('Đã xử lý')),
                ButtonSegment(value: 'all', label: Text('Tất cả')),
              ],
              selected: {_statusFilter},
              onSelectionChanged: (value) {
                setState(() => _statusFilter = value.first);
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('reports')
                  .orderBy('createdAt', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.cloud_off_rounded,
                              size: 44,
                              color: Colors.redAccent,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Lỗi tải danh sách báo cáo',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final reports = _filterReports(snapshot.data?.docs ?? []);
                if (reports.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.task_alt_rounded,
                              size: 48,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _statusFilter == 'pending'
                                ? 'Tuyệt vời! Không có báo lỗi chờ xử lý'
                                : 'Không có báo cáo lỗi nào trong mục này',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _statusFilter == 'pending'
                                ? 'Hệ thống đang hoạt động ổn định và không có khiếu nại sự cố'
                                : 'Danh sách sẽ hiển thị khi người dùng gửi phản hồi lỗi chương truyện',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: reports.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) {
                    final report = reports[index];
                    final isResolved = report.status == 'resolved';
                    final dateStr = DateFormat(
                      'dd/MM HH:mm',
                    ).format(report.createdAt);
                    final pageText = report.totalPages > 0
                        ? ' • Trang ${report.pageIndex + 1}/${report.totalPages}'
                        : '';

                    return Card(
                      color: Theme.of(context).cardColor,
                      margin: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Icon(
                          isResolved
                              ? Icons.check_circle
                              : Icons.warning_amber_rounded,
                          color: isResolved ? Colors.green : Colors.redAccent,
                          size: 32,
                        ),
                        title: Text(
                          report.mangaTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${report.reason} • $dateStr$pageText',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: Theme.of(context).iconTheme.color,
                        ),
                        onTap: () => _showReportDetails(report),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool canCopy;

  const _DetailRow({
    required this.label,
    required this.value,
    this.canCopy = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = value.isEmpty ? 'Không rõ' : value;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          if (canCopy && value.isNotEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Đã sao chép $label'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.copy,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
