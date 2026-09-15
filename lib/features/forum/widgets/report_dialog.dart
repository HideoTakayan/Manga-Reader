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
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Báo cáo đã được gửi. Cảm ơn bạn!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return PopScope(
      canPop: !_isSubmitting,
      child: AlertDialog(
        backgroundColor: theme.dialogTheme.backgroundColor ?? theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Báo cáo ${_getTypeName()}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: theme.colorScheme.onSurface,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vui lòng chọn lý do báo cáo:',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              ..._reasons.map((reason) {
                final isSelected = _selectedReason == reason;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primary.withValues(alpha: 0.12)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.08),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    title: Text(
                      reason,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? primary : theme.colorScheme.onSurface,
                      ),
                    ),
                    leading: Radio<String>(
                      value: reason,
                      // ignore: deprecated_member_use
                      groupValue: _selectedReason,
                      activeColor: primary,
                      // ignore: deprecated_member_use
                      onChanged: (value) {
                        setState(() {
                          _selectedReason = value;
                        });
                      },
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    onTap: () {
                      setState(() {
                        _selectedReason = reason;
                      });
                    },
                  ),
                );
              }),
              if (_selectedReason == 'Lý do khác')
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: TextField(
                    controller: _otherReasonController,
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Nhập lý do cụ thể...',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    maxLines: 3,
                  ),
                ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submitReport,
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: theme.colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: _isSubmitting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : const Text('Gửi báo cáo', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
