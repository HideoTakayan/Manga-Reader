import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../services/auth_service.dart';
import '../../../services/level_service.dart';
import '../../../widgets/level_badge.dart';

// Trang thông tin tài khoản — StatelessWidget vì toàn bộ data đến từ StreamBuilder Firestore.
// Bao gồm: hiển thị avatar/tên/email, chỉnh sửa hồ sơ, đổi mật khẩu.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final theme = Theme.of(context);
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Tài khoản'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.orangeAccent.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.account_circle_outlined,
                    size: 64,
                    color: Colors.orangeAccent,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Bạn chưa đăng nhập',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Đăng nhập để đồng bộ tiến trình đọc truyện, tham gia cộng đồng diễn đàn và quản lý tài khoản.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white60,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: () => context.push('/login'),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text(
                    'Đăng nhập ngay',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Tài khoản', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.85),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final doc = snapshot.data;
          if (doc == null || !doc.exists || doc.data() == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_off_rounded, size: 48, color: Colors.orangeAccent),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Chưa có dữ liệu hồ sơ',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Không tìm thấy thông tin hồ sơ trên hệ thống máy chủ.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = doc.data()! as Map<String, dynamic>;

          ImageProvider? avatarImage;
          final avatarUrl = data['avatarUrl']?.toString().trim() ?? '';
          final avatarBase64 = data['avatarBase64']?.toString().trim() ?? '';
          if (avatarUrl.isNotEmpty) {
            avatarImage = NetworkImage(avatarUrl);
          } else if (avatarBase64.isNotEmpty) {
            try {
              avatarImage = MemoryImage(base64Decode(avatarBase64));
            } catch (_) {}
          } else if (user.photoURL != null) {
            avatarImage = NetworkImage(user.photoURL!);
          } else if (data['avatar'] != null &&
              data['avatar'].toString().isNotEmpty) {
            try {
              avatarImage = NetworkImage(data['avatar']);
            } catch (_) {}
          }

          return SingleChildScrollView(
            child: Column(
              children: [
                // Hero Header
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Blurred background from avatar
                    if (avatarImage != null)
                      Container(
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          image: DecorationImage(
                            image: avatarImage,
                            fit: BoxFit.cover,
                          ),
                        ),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(color: Colors.black.withValues(alpha: 0.4)),
                        ),
                      )
                    else
                      Container(
                        height: 220,
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.blueAccent, Colors.purpleAccent],
                          ),
                        ),
                      ),
                    
                    // Avatar & Info
                    Builder(
                      builder: (_) {
                        final userExp = (data['exp'] as num?)?.toInt() ?? LevelService.instance.currentExp;
                        final userLevel = LevelService.getLevelInfo(userExp).level;

                        return Column(
                          children: [
                            const SizedBox(height: 25),
                            LevelAvatarFrame(
                              level: userLevel,
                              size: 110,
                              child: CircleAvatar(
                                radius: 55,
                                backgroundColor: Colors.blueAccent,
                                backgroundImage: avatarImage,
                                child: avatarImage == null
                                    ? Text(
                                        ((data['displayName'] ?? user.displayName ?? 'U')[0]).toUpperCase(),
                                        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              data['displayName'] ?? user.displayName ?? data['name'] ?? 'Không tên',
                              style: const TextStyle(
                                fontSize: 22, 
                                fontWeight: FontWeight.bold, 
                                color: Colors.white, 
                                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                              ),
                            ),
                            const SizedBox(height: 6),
                            LevelBadge(level: userLevel, fontSize: 12, showTitle: true),
                            const SizedBox(height: 4),
                            Text(
                              data['email'] ?? user.email ?? '',
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                
                // Reader Level Progression Card
                Builder(
                  builder: (_) {
                    final userExp = (data['exp'] as num?)?.toInt() ?? LevelService.instance.currentExp;
                    return LevelProgressCard(exp: userExp);
                  },
                ),

                // Content section
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cài đặt hồ sơ',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        color: Theme.of(context).cardColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.edit, color: Colors.blueAccent),
                              ),
                              title: const Text('Chỉnh sửa hồ sơ', style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: const Text('Cập nhật tên, giới thiệu và ảnh', style: TextStyle(fontSize: 12)),
                              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                              onTap: () => context.go('/settings/account/edit'),
                            ),
                            Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.lock_reset, color: Colors.orange),
                              ),
                              title: const Text('Đổi mật khẩu', style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: const Text('Bảo vệ tài khoản của bạn', style: TextStyle(fontSize: 12)),
                              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                              onTap: () => _showChangePasswordDialog(context),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Thông tin tài khoản',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        color: Theme.of(context).cardColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                        child: Column(
                          children: [
                            if ((data['bio'] ?? '').toString().trim().isNotEmpty) ...[
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.purpleAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.format_quote_rounded, color: Colors.purpleAccent),
                                ),
                                title: const Text('Tiểu sử', style: TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(data['bio'].toString(), style: const TextStyle(fontSize: 13, color: Colors.white70)),
                              ),
                              Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
                            ],
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.cyanAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.fingerprint_rounded, color: Colors.cyanAccent),
                              ),
                              title: const Text('Mã người dùng (UID)', style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(user.uid, style: const TextStyle(fontSize: 12, color: Colors.white60)),
                              trailing: IconButton(
                                icon: const Icon(Icons.copy_rounded, color: Colors.cyanAccent, size: 20),
                                tooltip: 'Sao chép UID',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: user.uid));
                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã sao chép UID người dùng'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const ChangePasswordDialog(),
    );
  }
}

// Dialog đổi mật khẩu — StatefulWidget riêng để quản lý form state độc lập
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _currentPassController = TextEditingController();
  final _newPassController = TextEditingController();
  final _confirmPassController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _currentPassController.dispose();
    _newPassController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  InputDecoration _inputDeco(String label, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.orange, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLoading,
      child: AlertDialog(
        backgroundColor: Theme.of(context).dialogTheme.backgroundColor ?? Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Đổi mật khẩu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                TextFormField(
                  controller: _currentPassController,
                  obscureText: _obscureCurrent,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDeco(
                    'Mật khẩu hiện tại',
                    suffix: IconButton(
                      icon: Icon(
                        _obscureCurrent ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white54,
                      ),
                      onPressed: () =>
                          setState(() => _obscureCurrent = !_obscureCurrent),
                    ),
                  ),
                  validator: (val) => val == null || val.isEmpty
                      ? 'Vui lòng nhập mật khẩu hiện tại'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _newPassController,
                  obscureText: _obscureNew,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDeco(
                    'Mật khẩu mới',
                    suffix: IconButton(
                      icon: Icon(
                        _obscureNew ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white54,
                      ),
                      onPressed: () => setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) {
                      return 'Vui lòng nhập mật khẩu mới';
                    }
                    if (val.length < 6) return 'Mật khẩu phải từ 6 ký tự trở lên';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPassController,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _isLoading ? null : _changePassword(),
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDeco(
                    'Xác nhận mật khẩu mới',
                    suffix: IconButton(
                      icon: Icon(
                        _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white54,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (val) => val != _newPassController.text
                      ? 'Mật khẩu xác nhận không khớp'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: _isLoading ? null : _changePassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Đổi mật khẩu', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword() async {
    // Validate tất cả  — dừng nếu có lỗi
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      // AuthService.changePassword: re-authenticate rồi updatePassword qua Firebase Auth
      await AuthService().changePassword(
        _currentPassController.text,
        _newPassController.text,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đổi mật khẩu thành công!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${e.toString().replaceAll("Exception:", "")}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
