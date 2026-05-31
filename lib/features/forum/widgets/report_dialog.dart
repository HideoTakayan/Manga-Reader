import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_forum_repository.dart';

class ReportDialog extends StatefulWidget {
  final String targetType; // 'post', 'comment', or 'message'
  final String targetId;
  final String postId; // the root post id (can be empty for message)

  const ReportDialog({
    super.key,
    required this.targetType,
    required this.targetId,
    required this.postId,
  });

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  final List<String> _reasons = [
    'Nội dung xúc phạm, quấy rối',
    'Spam, quảng cáo',
    'Chứa thông tin cá nhân',
    'Bạo lực hoặc hình ảnh nhạy cảm',
    'Sai chủ đề',
    'Lý do khác',
  ];

  String? _selectedReason;
  final _otherReasonController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _otherReasonController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để báo cáo')),
      );
      Navigator.of(context).pop();
      return;
    }

    String reason = _selectedReason ?? '';
    if (reason == 'Lý do khác') {
      reason = _otherReasonController.text.trim();
    }

    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn hoặc nhập lý do')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await FirebaseForumRepository().reportContent(
        reporterId: uid,
        targetType: widget.targetType,
        targetId: widget.targetId,
        postId: widget.postId,
        reason: reason,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Báo cáo đã được gửi. Cảm ơn bạn!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi gửi báo cáo: $e')));
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _getTypeName() {
    switch (widget.targetType) {
      case 'post': return 'bài viết';
      case 'comment': return 'bình luận';
      case 'message': return 'tin nhắn';
      default: return 'nội dung';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Báo cáo ${_getTypeName()}',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vui lòng chọn lý do báo cáo:'),
            const SizedBox(height: 8),
            ..._reasons.map((reason) {
              return ListTile(
                title: Text(reason),
                leading: Radio<String>(
                  value: reason,
                  // ignore: deprecated_member_use
                  groupValue: _selectedReason,
                  // ignore: deprecated_member_use
                  onChanged: (value) {
                    setState(() {
                      _selectedReason = value;
                    });
                  },
                ),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  setState(() {
                    _selectedReason = reason;
                  });
                },
              );
            }),
            if (_selectedReason == 'Lý do khác')
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: TextField(
                  controller: _otherReasonController,
                  decoration: const InputDecoration(
                    hintText: 'Nhập lý do cụ thể...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitReport,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Gửi'),
        ),
      ],
    );
  }
}
