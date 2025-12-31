import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../../utils/auth_help.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final user = FirebaseAuth.instance.currentUser;
  bool _loading = false;

  Future<void> _editProfileDialog(BuildContext context) async {
    final nameController = TextEditingController(text: user?.displayName ?? '');
    final bioController = TextEditingController();
    File? newAvatar;

    // Lấy dữ liệu mô tả & avatarBase64 từ Firestore
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .get();
    if (doc.exists) {
      bioController.text = doc.data()?['bio'] ?? '';
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
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
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Chỉnh sửa thông tin",
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () async {
                    final picked = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                    );
                    if (picked != null) {
                      setStateSheet(() => newAvatar = File(picked.path));
                    }
                  },
                  child: CircleAvatar(
                    radius: 45,
                    backgroundColor: Colors.grey[700],
                    backgroundImage: newAvatar != null
                        ? FileImage(newAvatar!)
                        : _getUserAvatar(doc),
                    child: (newAvatar == null && _getUserAvatar(doc) == null)
                        ? const Icon(
                            Icons.camera_alt,
                            size: 30,
                            color: Colors.white70,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Tên hiển thị',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0xFF2C2C2E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bioController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Mô tả',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0xFF2C2C2E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _saveProfile(
                      nameController.text,
                      bioController.text,
                      newAvatar,
                    );
                  },
                  icon: const Icon(Icons.save),
                  label: const Text("Lưu thay đổi"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            );
          },
        ),
      ),
    );
  }

  ImageProvider? _getUserAvatar(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    if (data['avatarBase64'] != null) {
      try {
        return MemoryImage(base64Decode(data['avatarBase64']));
      } catch (_) {
        return null;
      }
    } else if (user?.photoURL != null) {
      return NetworkImage(user!.photoURL!);
    }
    return null;
  }

  Future<void> _saveProfile(String name, String bio, File? avatar) async {
    if (user == null) return;
    setState(() => _loading = true);

    try {
      String? avatarBase64;

      // Nếu có ảnh mới thì encode base64
      if (avatar != null) {
        final bytes = await avatar.readAsBytes();
        avatarBase64 = base64Encode(bytes);
      }

      // Cập nhật tên hiển thị
      await user!.updateDisplayName(name);

      // Cập nhật vào Firestore
      final dataToUpdate = {
        'displayName': name,
        'bio': bio,
        'email': user!.email,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (avatarBase64 != null) {
        dataToUpdate['avatarBase64'] = avatarBase64;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .set(dataToUpdate, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu thay đổi thành công!')),
        );
        setState(() {});
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) return _buildGuestView(context);

    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: _buildAppBar(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user!.uid)
                  .get(),
              builder: (context, snapshot) {
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
                      if (user!.email == 'admin@gmail.com')
                        _buildTile(
                          context,
                          icon: Icons.dashboard,
                          color: Colors.orange,
                          title: 'Admin Dashboard',
                          subtitle: 'Thống kê & Quản lý',
                          onTap: () => context.push('/admin'),
                        ),
                      _buildTile(
                        context,
                        icon: Icons.notifications_outlined,
                        color: Colors.blue,
                        title: 'Thông báo',
                        subtitle: 'Cài đặt thông báo đẩy',
                        onTap: () {},
                      ),
                      _buildTile(
                        context,
                        icon: Icons.privacy_tip_outlined,
                        color: Colors.purple,
                        title: 'Quyền riêng tư',
                        subtitle: 'Quản lý dữ liệu và quyền truy cập',
                        onTap: () {},
                      ),
                      _buildTile(
                        context,
                        icon: Icons.help_outline,
                        color: Colors.green,
                        title: 'Trợ giúp',
                        subtitle: 'Hỏi đáp và hỗ trợ',
                        onTap: () {},
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
                            style: TextStyle(fontWeight: FontWeight.bold),
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
      backgroundColor: const Color(0xFF1C1C1E),
      elevation: 0,
      centerTitle: true,
      title: const Text(
        'Cài đặt',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new,
          color: Colors.white,
          size: 20,
        ),
        onPressed: () =>
            Navigator.of(context).canPop() ? context.pop() : context.go('/'),
      ),
    );
  }

  Widget _buildUserCard(BuildContext context, DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    ImageProvider? avatarImage;

    if (data['avatarBase64'] != null) {
      try {
        avatarImage = MemoryImage(base64Decode(data['avatarBase64']));
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

  Widget _buildTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      color: const Color(0xFF2C2C2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white70),
        onTap: onTap,
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Đăng xuất',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Bạn có chắc muốn đăng xuất?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đăng xuất', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await AuthService().logout();
      context.go('/login');
    }
  }

  Widget _buildGuestView(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: _buildAppBar(context),
      body: const Center(
        child: Text(
          "Bạn chưa đăng nhập",
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
    );
  }
}
