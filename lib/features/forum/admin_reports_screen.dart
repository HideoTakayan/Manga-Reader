import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'models/forum_report.dart';
import 'services/firebase_forum_repository.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  final _repository = FirebaseForumRepository();
  final List<ForumReport> _reports = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final (reports, lastDoc) = await _repository.fetchPendingReports(startAfter: _lastDoc);
      if (!mounted) return;

      setState(() {
        _reports.addAll(reports);
        _lastDoc = lastDoc;
        if (reports.length < 20) {
          _hasMore = false;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải report: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showReportDetails(ForumReport report) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return ReportDetailSheet(
          report: report,
          onDismiss: () => _resolveReport(report, 'dismissed'),
          onAction: () => _showModerationOptions(report),
        );
      },
    );
  }

  void _showModerationOptions(ForumReport report) {
    Navigator.pop(context); // close previous bottom sheet
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Xóa nội dung vi phạm & Đóng report'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  if (_processingReports.contains(report.id)) return;
                  
                  _setProcessing(report.id, true);
                  try {
                    if (report.targetType == 'post') {
                      await _repository.softDeletePost(report.targetId);
                    } else if (report.targetType == 'comment') {
                      await _repository.softDeleteComment(report.postId, report.targetId);
                    } else if (report.targetType == 'message') {
                      await _repository.softDeleteMessage(report.targetId);
                    }
                    if (!mounted) return;
                    await _resolveReport(report, 'resolved_deleted');
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                    }
                  } finally {
                    _setProcessing(report.id, false);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.volume_off, color: Colors.orange),
                title: const Text('Cấm ngôn User 1 giờ & Đóng report'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  if (_processingReports.contains(report.id)) return;

                  _setProcessing(report.id, true);
                  try {
                    String? authorId;
                    final firestore = FirebaseFirestore.instance;
                    if (report.targetType == 'post') {
                      final doc = await firestore.collection('forumPosts').doc(report.targetId).get();
                      authorId = doc.data()?['authorId'];
                    } else if (report.targetType == 'comment') {
                      final doc = await firestore.collection('forumPosts').doc(report.postId).collection('comments').doc(report.targetId).get();
                      authorId = doc.data()?['authorId'];
                    } else if (report.targetType == 'message') {
                      final doc = await firestore.collection('forumMessages').doc(report.targetId).get();
                      authorId = doc.data()?['authorId'];
                    }

                    if (authorId != null) {
                      await _repository.muteForumUser(
                        userId: authorId,
                        duration: const Duration(hours: 1),
                        reason: 'Vi phạm diễn đàn',
                      );
                      if (!mounted) return;
                      await _resolveReport(report, 'resolved_muted');
                    } else {
                      if (mounted) {
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không tìm thấy tác giả')));
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                    }
                  } finally {
                    _setProcessing(report.id, false);
                  }
                },
              ),
            ],
          ),
        );
      }
    );
  }

  final Set<String> _processingReports = {};

  void _setProcessing(String reportId, bool isProcessing) {
    if (!mounted) return;
    setState(() {
      if (isProcessing) {
        _processingReports.add(reportId);
      } else {
        _processingReports.remove(reportId);
      }
    });
  }

  Future<bool> _resolveReport(ForumReport report, String action) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    _setProcessing(report.id, true);
    try {
      await _repository.resolveReport(
        reportId: report.id,
        action: action,
        resolvedBy: user.uid,
      );
      if (!mounted) return false;

      setState(() {
        _reports.removeWhere((r) => r.id == report.id);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xử lý report thành công')),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xử lý report: $e')),
        );
      }
      return false;
    } finally {
      if (mounted) {
        _setProcessing(report.id, false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý Báo cáo (Admin)')),
      body: _reports.isEmpty && !_isLoading
          ? const Center(child: Text('Không có báo cáo nào đang chờ.'))
          : ListView.builder(
              itemCount: _reports.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _reports.length) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _loadMore();
                  });
                  return const Center(child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ));
                }
                final report = _reports[index];
                return ListTile(
                  title: Text('[${report.targetType.toUpperCase()}] Báo cáo vi phạm'),
                  subtitle: Text(
                    report.reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _processingReports.contains(report.id)
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right),
                  onTap: _processingReports.contains(report.id) ? null : () => _showReportDetails(report),
                );
              },
            ),
    );
  }
}

class ReportDetailSheet extends StatefulWidget {
  final ForumReport report;
  final Future<bool> Function() onDismiss;
  final VoidCallback onAction;

  const ReportDetailSheet({
    super.key,
    required this.report,
    required this.onDismiss,
    required this.onAction,
  });

  @override
  State<ReportDetailSheet> createState() => _ReportDetailSheetState();
}

class _ReportDetailSheetState extends State<ReportDetailSheet> {
  Map<String, dynamic>? _targetData;
  Map<String, dynamic>? _reporterData;
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchTargetData();
  }

  Future<void> _fetchTargetData() async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      // Fetch target data and reporter data in parallel
      DocumentSnapshot? doc;
      DocumentSnapshot? reporterDoc;
      
      final reporterFuture = firestore.collection('users').doc(widget.report.reporterId).get();
      Future<DocumentSnapshot> docFuture;

      if (widget.report.targetType == 'post') {
        docFuture = firestore.collection('forumPosts').doc(widget.report.targetId).get();
      } else if (widget.report.targetType == 'comment') {
        docFuture = firestore.collection('forumPosts').doc(widget.report.postId).collection('comments').doc(widget.report.targetId).get();
      } else {
        docFuture = firestore.collection('forumMessages').doc(widget.report.targetId).get();
      }

      final results = await Future.wait([docFuture, reporterFuture]);
      doc = results[0];
      reporterDoc = results[1];

      if (!mounted) return;
      
      Map<String, dynamic>? reporterDataMap;
      if (reporterDoc.exists) {
        reporterDataMap = reporterDoc.data() as Map<String, dynamic>?;
      }

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        setState(() {
          _targetData = data;
          _reporterData = reporterDataMap;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Nội dung này không tồn tại hoặc đã bị xóa.';
          _reporterData = reporterDataMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Lỗi tải nội dung: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isProcessing,
      child: Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Chi tiết báo cáo', style: Theme.of(context).textTheme.titleLarge),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _isProcessing ? null : () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Loại: ${widget.report.targetType.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  
                  // Reporter Info
                  const Text('Người báo cáo:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  const SizedBox(height: 4),
                  if (_reporterData != null)
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundImage: (_reporterData!['avatarUrl'] ?? _reporterData!['avatar']) != null && 
                                           (_reporterData!['avatarUrl'] ?? _reporterData!['avatar']).toString().isNotEmpty
                              ? NetworkImage(_reporterData!['avatarUrl'] ?? _reporterData!['avatar'])
                              : null,
                          child: (_reporterData!['avatarUrl'] ?? _reporterData!['avatar']) == null || 
                                 (_reporterData!['avatarUrl'] ?? _reporterData!['avatar']).toString().isEmpty
                              ? const Icon(Icons.person, size: 16)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text('${_reporterData!['name'] ?? 'Unknown'} (${widget.report.reporterId})'),
                      ],
                    )
                  else
                    Text('UID: ${widget.report.reporterId}'),
                  const SizedBox(height: 4),
                  Text(
                    'Thời gian: ${widget.report.createdAt.toLocal().toString().split('.')[0]}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  
                  const Text('Lý do báo cáo:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  Text(widget.report.reason),
                  const SizedBox(height: 16),
                  const Text('Nội dung bị báo cáo:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  const SizedBox(height: 8),
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red))
                  else if (_targetData != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundImage: _targetData!['authorAvatar'] != null && _targetData!['authorAvatar'].toString().isNotEmpty
                                    ? NetworkImage(_targetData!['authorAvatar'])
                                    : null,
                                child: _targetData!['authorAvatar'] == null || _targetData!['authorAvatar'].toString().isEmpty
                                    ? const Icon(Icons.person, size: 16)
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Text(_targetData!['authorName'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_targetData!['body'] != null && _targetData!['body'].toString().isNotEmpty)
                            Text(_targetData!['body']),
                          if (_targetData!['gifUrl'] != null && _targetData!['gifUrl'].toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Image.network(_targetData!['gifUrl'], height: 100),
                            ),
                          if (_targetData!['imageUrl'] != null && _targetData!['imageUrl'].toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Image.network(
                                _targetData!['imageUrl'], 
                                height: 150,
                                errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                              ),
                            ),
                          const SizedBox(height: 8),
                          if (_targetData!['isDeleted'] == true)
                            const Text('(Đã bị xóa)', style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(
                  onPressed: _isProcessing ? null : () async {
                    setState(() => _isProcessing = true);
                    final success = await widget.onDismiss();
                    if (context.mounted) {
                      setState(() => _isProcessing = false);
                      if (success) {
                        Navigator.pop(context);
                      }
                    }
                  },
                  child: _isProcessing 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                      : const Text('Bỏ qua'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: _isProcessing ? null : widget.onAction,
                  child: const Text('Xử lý vi phạm', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    ));
  }
}
