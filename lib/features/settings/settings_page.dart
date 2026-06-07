import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../forum/services/image_upload_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../config/admin_config.dart';
import '../library/edit_categories_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _loading = false;

  User? get user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
  }

  InputDecoration _inputDeco(String label, {IconData? icon, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: icon != null ? Icon(icon, color: Colors.white54) : null,
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

  Future<void> _editProfileDialog(BuildContext context) async {
    final currentUser = user;
    if (currentUser == null) return;

    final nameController = TextEditingController(
      text: currentUser.displayName ?? '',
    );
    final bioController = TextEditingController();
    File? newAvatar;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();
    if (doc.exists) {
      bioController.text = doc.data()?['bio'] ?? '';
    }
    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 25,
        ),
        child: StatefulBuilder(
          builder: (context, setStateSheet) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Chỉnh sửa thông tin",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () async {
                      final picked = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                      );
                      if (picked != null) {
                        setStateSheet(() => newAvatar = File(picked.path));
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withValues(alpha: 0.2),
                            blurRadius: 15,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 45,
                        backgroundColor: Colors.grey[800],
                        backgroundImage: newAvatar != null
                            ? FileImage(newAvatar!)
                            : _getUserAvatar(doc),
                        child: (newAvatar == null && _getUserAvatar(doc) == null)
                            ? const Icon(
                                Icons.camera_alt,
                                size: 30,
                                color: Colors.white54,
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Tên hiển thị', icon: Icons.person_outline),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: bioController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Mô tả ngắn', icon: Icons.description_outlined),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _saveProfile(
                          nameController.text,
                          bioController.text,
                          newAvatar,
                        );
                      },
                      icon: const Icon(Icons.save),
                      label: const Text("Lưu thay đổi", style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  ImageProvider? _getUserAvatar(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    // Ưu tiên avatarUrl (Cloudinary) — mới hơn và không bị block
    final avatarUrl = _readString(data, 'avatarUrl');
    if (avatarUrl.isNotEmpty) {
      return NetworkImage(avatarUrl);
    }
    // Fallback: avatarBase64 (legacy) — đọc được nhưng không ghi thêm
    final avatarBase64 = _readString(data, 'avatarBase64');
    if (avatarBase64.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(avatarBase64));
      } catch (_) {}
    }
    // Fallback cuối: Google avatar từ OAuth
    if (user?.photoURL != null) {
      return NetworkImage(user!.photoURL!);
    }
    return null;
  }

  String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return '';
    return value.toString().trim();
  }

  Future<void> _saveProfile(String name, String bio, File? avatar) async {
    final currentUser = user;
    if (currentUser == null) return;
    setState(() => _loading = true);

    try {
      String? avatarUrl;
      if (avatar != null) {
        avatarUrl = await ImageUploadService.uploadAvatarImage(
          avatar,
          currentUser.uid,
        );
        // Cập nhật photoURL trên Firebase Auth để hiện ở các nơi khác
        await currentUser.updatePhotoURL(avatarUrl);
      }

      await currentUser.updateDisplayName(name);

      final dataToUpdate = <String, dynamic>{
        'name': name,
        'displayName': name,
        'bio': bio,
        'email': currentUser.email,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (avatarUrl != null) {
        dataToUpdate['avatarUrl'] = avatarUrl;
        // Xóa field base64 cũ nếu có — giảm dung lượng document
        dataToUpdate['avatarBase64'] = FieldValue.delete();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .set(dataToUpdate, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu thay đổi thành công!')),
      );
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = user;
    if (currentUser == null) return _buildGuestView(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUser.uid)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildSettingsError(
                    context,
                    'Không thể tải dữ liệu tài khoản.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    children: [
                      _buildUserCard(context, snapshot.data!),
                      const SizedBox(height: 24),

                      _buildTile(
                        context,
                        icon: Icons.person_outline,
                        color: Colors.amber,
                        title: 'Tài khoản',
                        subtitle: 'Xem và chỉnh sửa thông tin cá nhân',
                        onTap: () => context.go('/settings/account'),
                      ),

                      // Hiển thị tile "Thêm mật khẩu" nếu user đăng nhập bằng Google và chưa có password.
                      // Lấy dữ liệu trực tiếp từ outer FutureBuilder — không cần query Firestore lần nữa.
                      Builder(
                        builder: (context) {
                          final userData =
                              snapshot.data!.data() as Map<String, dynamic>? ??
                              {};
                          final authProvider = userData['authProvider'] ?? '';
                          final hasPassword = userData['hasPassword'] ?? false;
                          if (authProvider == 'google' && !hasPassword) {
                            return _buildTile(
                              context,
                              icon: Icons.lock_outline,
                              color: Colors.deepOrange,
                              title: 'Thêm mật khẩu',
                              subtitle: 'Đăng nhập bằng email/password',
                              onTap: () => _showAddPasswordDialog(context),
                            );
                          }
                          return const SizedBox();
                        },
                      ),

                      // Kiểm tra quyền Admin qua AdminConfig — tập trung tại config/admin_config.dart
                      if (AdminConfig.isAdmin(currentUser.email))
                        _buildTile(
                          context,
                          icon: Icons.dashboard,
                          color: Colors.orange,
                          title: 'Admin Dashboard',
                          subtitle: 'Thống kê & Quản lý',
                          onTap: () => context.go('/admin/control'),
                        ),

                      _buildTile(
                        context,
                        icon: Icons.category_outlined,
                        color: Colors.purpleAccent,
                        title: 'Hạng mục',
                        subtitle: 'Quản lý danh mục thư viện',
                        // MaterialPageRoute thay vì go_router: EditCategoriesPage không có route named
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const EditCategoriesPage(),
                          ),
                        ),
                      ),

                      _buildTile(
                        context,
                        icon: Icons.download_outlined,
                        color: Colors.teal,
                        title: 'Hàng đợi tải xuống',
                        subtitle: 'Quản lý các chương đang tải',
                        onTap: () => context.push('/downloads'),
                      ),

                      _buildTile(
                        context,
                        icon: Icons.storage_outlined,
                        color: Colors.cyan,
                        title: 'Dung lượng tải xuống',
                        subtitle: 'Xem dung lượng, file lỗi và xóa dữ liệu tải',
                        onTap: () => context.push('/storage'),
                      ),

                      _buildTile(
                        context,
                        icon: Icons.backup_outlined,
                        color: Colors.indigoAccent,
                        title: 'Backup & Restore',
                        subtitle: 'Xuất/nhập thư viện, lịch sử và bookmark',
                        onTap: () => context.push('/backup'),
                      ),

                      const SizedBox(height: 8),
                      _buildTile(
                        context,
                        icon: Icons.bar_chart_rounded,
                        color: Colors.orange,
                        title: 'Thống kê đọc',
                        subtitle: 'Xem hoạt động đọc truyện của bạn',
                        onTap: () => context.push('/analytics'),
                      ),

                      const SizedBox(height: 8),
                      _buildTile(
                        context,
                        icon: Icons.notifications_outlined,
                        color: Colors.blue,
                        title: 'Thông báo',
                        subtitle: 'Xem thông báo của bạn',
                        onTap: () => context.push('/notifications'),
                      ),

                      _buildTile(
                        context,
                        icon: Icons.help_outline,
                        color: Colors.green,
                        title: 'Trợ giúp',
                        subtitle: 'Hỏi đáp và hỗ trợ',
                        onTap: () => context.push('/settings/help'),
                      ),

                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _showLogoutDialog(context),
                          icon: const Icon(
                            Icons.logout,
                            color: Colors.white,
                            size: 22,
                          ),
                          label: const Text(
                            'Đăng xuất',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      elevation: 0,
      centerTitle: true,
      title: Text('Cài đặt', style: Theme.of(context).textTheme.titleLarge),
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new,
          color: Theme.of(context).iconTheme.color,
          size: 20,
        ),
        // canPop() check: tránh pop khi Settings là root route của branch
        onPressed: () =>
            Navigator.of(context).canPop() ? context.pop() : context.go('/'),
      ),
    );
  }

  // User card: avatar + tên + email + edit icon
  Widget _buildUserCard(BuildContext context, DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    ImageProvider? avatarImage;
    final avatarUrl = _readString(data, 'avatarUrl');
    final avatarBase64 = _readString(data, 'avatarBase64');
    if (avatarUrl.isNotEmpty) {
      avatarImage = NetworkImage(avatarUrl);
    } else if (avatarBase64.isNotEmpty) {
      try {
        avatarImage = MemoryImage(base64Decode(avatarBase64));
      } catch (_) {}
    } else if (user?.photoURL != null) {
      avatarImage = NetworkImage(user!.photoURL!);
    }

    return Card(
      color: const Color(0xFF2C2C2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: Colors.blueAccent,
              backgroundImage: avatarImage,
              child: avatarImage == null
                  ? Text(
                      ((user?.displayName?.isNotEmpty ?? false)
                              ? user!.displayName!
                              : 'U')[0]
                          .toUpperCase(),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tên: ưu tiên Firestore displayName hơn Firebase Auth
                  Text(
                    data['displayName'] ?? user?.displayName ?? 'Người dùng',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    user?.email ?? '',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blueAccent),
              onPressed: () => _editProfileDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsError(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 44),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => setState(() {}),
              child: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  // Reusable settings tile: icon có background màu nhạt + title + subtitle + chevron
  Widget _buildTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing, // Cho phép override trailing icon nếu cần
  }) {
    return Card(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          // withValues(alpha: 0.15): icon background mờ, màu tương phản nhẹ với icon đậm
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(
              context,
            ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            fontSize: 13,
          ),
        ),
        trailing:
            trailing ??
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.5),
            ),
        onTap: onTap,
      ),
    );
  }

  // Thêm mật khẩu cho Google user — dùng Firebase Auth credential linking
  Future<void> _showAddPasswordDialog(BuildContext context) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    bool obscurePassword = true;
    bool obscureConfirm = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Thêm mật khẩu',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Thêm mật khẩu để có thể đăng nhập bằng email/password',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDeco(
                  'Mật khẩu mới',
                  icon: Icons.lock_outline,
                  suffix: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white54,
                    ),
                    onPressed: () => setDialogState(
                      () => obscurePassword = !obscurePassword,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                obscureText: obscureConfirm,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDeco(
                  'Xác nhận mật khẩu',
                  icon: Icons.lock_outline,
                  suffix: IconButton(
                    icon: Icon(
                      obscureConfirm ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white54,
                    ),
                    onPressed: () =>
                        setDialogState(() => obscureConfirm = !obscureConfirm),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final password = passwordController.text.trim();
                final confirm = confirmController.text.trim();

                // Validate trước khi gọi API
                if (password.isEmpty || confirm.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Vui lòng nhập đầy đủ')),
                  );
                  return;
                }
                if (password != confirm) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mật khẩu không khớp')),
                  );
                  return;
                }
                if (password.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Mật khẩu phải ít nhất 6 ký tự'),
                    ),
                  );
                  return;
                }

                Navigator.pop(ctx);

                try {
                  // AuthService.linkEmailPassword: link credential email/password vào account Google hiện tại
                  // Sau đó user có thể đăng nhập bằng cả Google lẫn email/password
                  await AuthService().linkEmailPassword(password);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Đã thêm mật khẩu thành công!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    setState(
                      () {},
                    ); // Refresh FutureBuilder → tile "Thêm mật khẩu" biến mất
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          e.toString().replaceAll('Exception: ', ''),
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Text('Thêm', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // Confirm dialog trước khi đăng xuất — showDialog<bool> trả về bool từ Navigator.pop(ctx, value)
  void _showLogoutDialog(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Đăng xuất',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Bạn có chắc muốn đăng xuất?',
          style: TextStyle(color: Colors.white70),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Đăng xuất', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    // confirm == true (không phải chỉ truthy) để phân biệt với null (bấm ra ngoài dialog)
    if (confirm == true && context.mounted) {
      await AuthService().logout();
      if (!context.mounted) return;
      context.go('/login');
    }
  }

  Widget _buildGuestView(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: _buildAppBar(context),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_circle_outlined,
              size: 72,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'Bạn chưa đăng nhập',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Đăng nhập để lưu lịch sử và đồng bộ dữ liệu',
              style: TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => context.go('/login'),
              icon: const Icon(Icons.login),
              label: const Text('Đăng nhập ngay'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
