import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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
        const SnackBar(content: Text('Đã đánh dấu xử lý thành công!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
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
        backgroundColor: Theme.of(context).cardColor,
        title: const Text('Chi tiết báo lỗi'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'Truyện', value: report.mangaTitle),
              if (report.chapterTitle.isNotEmpty)
                _DetailRow(label: 'Chương', value: report.chapterTitle),
              if (report.chapterId.isNotEmpty)
                _DetailRow(label: 'ID chương', value: report.chapterId),
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
              const Text('Mô tả'),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  report.description.isEmpty
                      ? 'Không có mô tả'
                      : report.description,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
          if (report.status == 'pending')
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _resolveReport(report.id);
              },
              icon: const Icon(Icons.check),
              label: const Text('Đã xử lý'),
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
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Lỗi: ${snapshot.error}'));
                }

                final reports = _filterReports(snapshot.data?.docs ?? []);
                if (reports.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 64,
                          color: Colors.green.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Không có báo lỗi phù hợp.',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
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

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? 'Không rõ' : value)),
        ],
      ),
    );
  }
}
