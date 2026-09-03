import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../forum/services/image_upload_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../services/group_service.dart';
import '../../config/admin_config.dart';
import '../../core/theme.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _loading = false;
  Future<DocumentSnapshot>? _userDocFuture;

  User? get user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _refreshUserDoc();
  }

  void _refreshUserDoc() {
    final uid = user?.uid ?? AuthService.persistedUid;
    if (uid.isNotEmpty) {
      _userDocFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
    }
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
          top: 12,
        ),
        child: StatefulBuilder(
          builder: (context, setStateSheet) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Chỉnh sửa thông tin",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: Colors.white,
                    ),
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
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 45,
                        backgroundColor: Theme.of(context).cardColor,
                        backgroundImage: newAvatar != null
                            ? FileImage(newAvatar!)
                            : _getUserAvatar(doc),
                        child:
                            (newAvatar == null && _getUserAvatar(doc) == null)
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
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    decoration: _inputDeco(
                      'Tên hiển thị',
                      icon: Icons.person_outline,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: bioController,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.done,
                    decoration: _inputDeco(
                      'Mô tả ngắn',
                      icon: Icons.description_outlined,
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final trimmedName = nameController.text.trim();
                        if (trimmedName.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Tên hiển thị không được để trống'),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(ctx);
                        await _saveProfile(
                          trimmedName,
                          bioController.text.trim(),
                          newAvatar,
                        );
                      },
                      icon: const Icon(Icons.save),
                      label: const Text(
                        "Lưu thay đổi",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
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
    ).whenComplete(() {
      nameController.dispose();
      bioController.dispose();
    });
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
      _refreshUserDoc(); // Refresh cached future sau khi lưu profile
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
    final isPersisted = AuthService.isPersistedLoggedIn;
    if (currentUser == null && !isPersisted) return _buildGuestView(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : FutureBuilder<DocumentSnapshot>(
              future: _userDocFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    children: [
                      _buildUserCard(context, snapshot.data),
                      const SizedBox(height: 24),

                      _buildTile(
                        context,
                        icon: Icons.person_outline,
                        color: Colors.amber,
                        title: 'Tài khoản',
                        subtitle: 'Xem và chỉnh sửa thông tin cá nhân',
                        onTap: () => context.go('/settings/account'),
                      ),

                      _buildTile(
                        context,
                        icon: Icons.palette_outlined,
                        color: Colors.deepOrangeAccent,
                        title: 'Giao diện & Bảo vệ mắt',
                        subtitle: 'Chế độ: ${ref.watch(themeProvider).title}',
                        onTap: () => _showThemeSelectorSheet(context),
                      ),

                      // Hiển thị tile "Thêm mật khẩu" nếu user đăng nhập bằng Google và chưa có password.
                      // Lấy dữ liệu trực tiếp từ outer FutureBuilder — không cần query Firestore lần nữa.
                      Builder(
                        builder: (context) {
                          final userData =
                              snapshot.data?.data() as Map<String, dynamic>? ??
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
                          return const SizedBox.shrink();
                        },
                      ),

                      // Kiểm tra quyền Admin qua AdminConfig — tập trung tại config/admin_config.dart
                      if (AdminConfig.isAdmin(
                        currentUser?.email ?? AuthService.persistedEmail,
                      ))
                        _buildTile(
                          context,
                          icon: Icons.dashboard,
                          color: Colors.orange,
                          title: 'Admin Dashboard',
                          subtitle: 'Thống kê & Quản lý',
                          onTap: () => context.go('/admin/control'),
                        ),

                      // Tính năng Nhóm Dịch (Chỉ dành cho User thường, loại Admin khỏi nhóm dịch)
                      Builder(
                        builder: (context) {
                          final isAdmin = AdminConfig.isAdmin(
                            currentUser?.email ?? AuthService.persistedEmail,
                          );
                          if (isAdmin) return const SizedBox.shrink();

                          final userData =
                              snapshot.data?.data() as Map<String, dynamic>? ??
                              {};
                          final groupId = userData['groupId']
                              ?.toString()
                              .trim();
                          if (groupId == null || groupId.isEmpty) {
                            return Column(
                              children: [
                                _buildTile(
                                  context,
                                  icon: Icons.groups,
                                  color: Colors.greenAccent,
                                  title: 'Tham gia Nhóm dịch',
                                  subtitle: 'Nhập mã để tham gia nhóm',
                                  onTap: () => _showJoinGroupDialog(context),
                                ),
                                _buildTile(
                                  context,
                                  icon: Icons.group_add,
                                  color: Colors.lightGreen,
                                  title: 'Tạo Nhóm dịch',
                                  subtitle: 'Đăng ký thành lập nhóm dịch mới',
                                  onTap: () => _showCreateGroupDialog(context),
                                ),
                              ],
                            );
                          }
                          return _buildTile(
                            context,
                            icon: Icons.groups,
                            color: Colors.greenAccent,
                            title: 'Nhóm dịch của bạn',
                            subtitle: 'Quản lý truyện, thành viên và mã mời',
                            onTap: () => context.go('/group'),
                          );
                        },
                      ),

                      _buildTile(
                        context,
                        icon: Icons.category_outlined,
                        color: Colors.purpleAccent,
                        title: 'Hạng mục',
                        subtitle: 'Quản lý danh mục thư viện',
                        onTap: () => context.push('/settings/categories'),
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
                        icon: Icons.cloud_download_outlined,
                        color: Colors.lightBlueAccent,
                        title: 'Tự động tải chương mới',
                        subtitle:
                            'Tự tải ngầm khi có chap mới từ truyện Theo dõi',
                        onTap: () => _showAutoDownloadSettingsDialog(context),
                      ),

                      _buildTile(
                        context,
                        icon: Icons.schedule_rounded,
                        color: Colors.deepOrangeAccent,
                        title: 'Tần suất kiểm tra chương mới',
                        subtitle:
                            'Tùy chỉnh chu kỳ quét ngầm (tiết kiệm pin & 4G)',
                        onTap: () => _showCheckFrequencyDialog(context),
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
  Widget _buildUserCard(BuildContext context, DocumentSnapshot? doc) {
    final data = (doc?.data() as Map<String, dynamic>?) ?? {};
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

    final displayName =
        data['displayName'] ??
        user?.displayName ??
        (AuthService.persistedName.isNotEmpty
            ? AuthService.persistedName
            : 'Người dùng');
    final email =
        user?.email ??
        (AuthService.persistedEmail.isNotEmpty
            ? AuthService.persistedEmail
            : '');

    return Card(
      color: Theme.of(context).cardColor,
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
                      (displayName.isNotEmpty ? displayName[0] : 'U')
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
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    email,
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

  Future<void> _showAutoDownloadSettingsDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    bool enabled = prefs.getBool('auto_download_new_chapters') ?? false;
    int maxChapters = prefs.getInt('auto_download_max_chapters') ?? 1;

    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).padding.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.lightBlueAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.cloud_download_rounded,
                        color: Colors.lightBlueAccent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tự động tải chương mới',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Tự tải về máy khi có chap mới',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: enabled,
                      activeTrackColor: Colors.lightBlueAccent.withValues(
                        alpha: 0.5,
                      ),
                      activeThumbColor: Colors.lightBlueAccent,
                      onChanged: (val) async {
                        setSheetState(() => enabled = val);
                        await prefs.setBool('auto_download_new_chapters', val);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(color: Colors.white10),
                const SizedBox(height: 12),
                const Text(
                  'Số chương mới tải mỗi truyện:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildOptionChip(
                      label: '1 chương',
                      selected: maxChapters == 1,
                      onTap: enabled
                          ? () async {
                              setSheetState(() => maxChapters = 1);
                              await prefs.setInt(
                                'auto_download_max_chapters',
                                1,
                              );
                            }
                          : null,
                    ),
                    const SizedBox(width: 8),
                    _buildOptionChip(
                      label: '3 chương',
                      selected: maxChapters == 3,
                      onTap: enabled
                          ? () async {
                              setSheetState(() => maxChapters = 3);
                              await prefs.setInt(
                                'auto_download_max_chapters',
                                3,
                              );
                            }
                          : null,
                    ),
                    const SizedBox(width: 8),
                    _buildOptionChip(
                      label: 'Tất cả',
                      selected: maxChapters >= 999,
                      onTap: enabled
                          ? () async {
                              setSheetState(() => maxChapters = 999);
                              await prefs.setInt(
                                'auto_download_max_chapters',
                                999,
                              );
                            }
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Colors.lightBlueAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Áp dụng cho tất cả các truyện trong Thư viện và danh sách Theo dõi của bạn. Tiến trình tải sẽ chạy ngầm không làm phiền.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
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

  Widget _buildOptionChip({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Colors.lightBlueAccent.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? Colors.lightBlueAccent : Colors.white12,
              width: selected ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.lightBlueAccent : Colors.white60,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCheckFrequencyDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    int currentInterval = prefs.getInt('chapter_check_interval_hours') ?? 6;

    if (!context.mounted) return;

    final options = [
      (0, 'Chỉ khi mở ứng dụng', 'Không quét ngầm, tiết kiệm tối đa pin & 4G'),
      (2, 'Mỗi 2 giờ', 'Nhận thông báo nhanh nhất khi có chương mới'),
      (6, 'Mỗi 6 giờ (Khuyên dùng)', 'Cân bằng tối ưu giữa pin và cập nhật'),
      (12, 'Mỗi 12 giờ', 'Kiểm tra 2 lần mỗi ngày'),
      (24, 'Mỗi 24 giờ', 'Kiểm tra 1 lần mỗi ngày'),
    ];

    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Tần suất kiểm tra chương mới',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Tần suất kiểm tra chương mới cho truyện trong Thư viện & Theo dõi',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white10),
                  ...options.map((opt) {
                    final isSelected = currentInterval == opt.$1;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 2,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.deepOrangeAccent.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.schedule_rounded,
                          color: isSelected
                              ? Colors.deepOrangeAccent
                              : Colors.white60,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        opt.$2,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.deepOrangeAccent
                              : Colors.white,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        opt.$3,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle_rounded,
                              color: Colors.deepOrangeAccent,
                            )
                          : null,
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        setSheetState(() => currentInterval = opt.$1);
                        await prefs.setInt(
                          'chapter_check_interval_hours',
                          opt.$1,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '⏱️ Đã đặt tần suất kiểm tra: ${opt.$2}',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    );
                  }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showJoinGroupDialog(BuildContext context) async {
    final codeController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),

                // Icon hero
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFF7043),
                        Color(0xFFFF9800),
                        Color(0xFFFF5252),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.5),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.groups_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  'Tham gia Nhóm Dịch',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Nhập mã mời 6 ký tự từ Trưởng nhóm',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 28),

                // Code input
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFFF7043).withValues(alpha: 0.15),
                          const Color(0xFFFF9800).withValues(alpha: 0.1),
                        ],
                      ),
                      border: Border.all(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.4),
                      ),
                    ),
                    child: TextField(
                      controller: codeController,
                      textCapitalization: TextCapitalization.characters,
                      textAlign: TextAlign.center,
                      textInputAction: TextInputAction.done,
                      onChanged: (val) {
                        setSheet(() {});
                        // Auto-submit when 6 chars are entered
                        if (val.length == 6) {
                          FocusScope.of(ctx).unfocus();
                        }
                      },
                      style: const TextStyle(
                        color: Color(0xFFFBBF24),
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                      ),
                      decoration: InputDecoration(
                        hintText: '• • • • • •',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.2),
                          fontSize: 22,
                          letterSpacing: 6,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 18,
                          horizontal: 16,
                        ),
                        counterText: '',
                      ),
                      maxLength: 6,
                    ),
                  ),
                ),

                // Character count indicator
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) {
                    final filled = i < codeController.text.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled
                            ? const Color(0xFFFF9800)
                            : Colors.white12,
                        boxShadow: filled
                            ? [
                                BoxShadow(
                                  color: const Color(
                                    0xFFFF9800,
                                  ).withValues(alpha: 0.6),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 28),

                // Action buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white60,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            'Hủy',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: codeController.text.length == 6
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFFFF7043),
                                      Color(0xFFFF9800),
                                      Color(0xFFFF5252),
                                    ],
                                  )
                                : null,
                            color: codeController.text.length == 6
                                ? null
                                : Colors.white10,
                            boxShadow: codeController.text.length == 6
                                ? [
                                    BoxShadow(
                                      color: const Color(
                                        0xFFFF7043,
                                      ).withValues(alpha: 0.4),
                                      blurRadius: 14,
                                      offset: const Offset(0, 5),
                                    ),
                                  ]
                                : null,
                          ),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: codeController.text.length == 6
                                ? () async {
                                    final code = codeController.text
                                        .trim()
                                        .toUpperCase();
                                    Navigator.pop(ctx);
                                    try {
                                      setState(() => _loading = true);
                                      await GroupService.instance
                                          .joinGroupByCode(code);
                                      if (mounted) {
                                        _refreshUserDoc();
                                        setState(() {});
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Row(
                                              children: [
                                                Icon(
                                                  Icons.check_circle,
                                                  color: Colors.green,
                                                ),
                                                SizedBox(width: 10),
                                                Text(
                                                  'Đã tham gia nhóm thành công!',
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        messenger.showSnackBar(
                                          SnackBar(content: Text('Lỗi: $e')),
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() => _loading = false);
                                      }
                                    }
                                  }
                                : null,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.login_rounded, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Gia nhập ngay',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(codeController.dispose);
  }

  Future<void> _showCreateGroupDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Icon hero
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFF59E0B),
                          Color(0xFFD97706),
                          Color(0xFFEA580C),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_moderator_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Đăng ký Tạo Nhóm Dịch',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Yêu cầu sẽ gửi cho Admin duyệt',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Info banner
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: Color(0xFFFBBF24),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Sau khi Admin phê duyệt, bạn sẽ trở thành Trưởng nhóm và có toàn quyền quản lý nhóm dịch.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Form fields
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        // Group name
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: Colors.white.withValues(alpha: 0.05),
                            border: Border.all(
                              color: nameController.text.isNotEmpty
                                  ? const Color(
                                      0xFFFF9800,
                                    ).withValues(alpha: 0.5)
                                  : Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: TextField(
                            controller: nameController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setSheet(() {}),
                            decoration: InputDecoration(
                              labelText: 'Tên nhóm dịch *',
                              labelStyle: TextStyle(
                                color: nameController.text.isNotEmpty
                                    ? const Color(0xFFFFB74D)
                                    : Colors.white38,
                              ),
                              prefixIcon: Container(
                                margin: const EdgeInsets.all(10),
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFFF9800,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.group_rounded,
                                  color: Color(0xFFFFB74D),
                                  size: 18,
                                ),
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Group description
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: Colors.white.withValues(alpha: 0.05),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: TextField(
                            controller: descController,
                            style: const TextStyle(color: Colors.white),
                            maxLines: 3,
                            textInputAction: TextInputAction.done,
                            onChanged: (_) => setSheet(() {}),
                            decoration: InputDecoration(
                              labelText: 'Mô tả nhóm (không bắt buộc)',
                              labelStyle: const TextStyle(
                                color: Colors.white38,
                              ),
                              prefixIcon: Container(
                                margin: const EdgeInsets.only(
                                  left: 10,
                                  right: 10,
                                  top: 10,
                                  bottom: 56,
                                ),
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.description_rounded,
                                  color: Colors.white38,
                                  size: 18,
                                ),
                              ),
                              alignLabelWithHint: true,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white60,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text(
                              'Hủy',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: nameController.text.trim().isNotEmpty
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFFF59E0B),
                                        Color(0xFFD97706),
                                        Color(0xFFEA580C),
                                      ],
                                    )
                                  : null,
                              color: nameController.text.trim().isNotEmpty
                                  ? null
                                  : Colors.white10,
                              boxShadow: nameController.text.trim().isNotEmpty
                                  ? [
                                      BoxShadow(
                                        color: const Color(
                                          0xFFF59E0B,
                                        ).withValues(alpha: 0.4),
                                        blurRadius: 14,
                                        offset: const Offset(0, 5),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: nameController.text.trim().isNotEmpty
                                  ? () async {
                                      Navigator.pop(ctx);
                                      try {
                                        setState(() => _loading = true);
                                        await GroupService.instance
                                            .registerGroup(
                                              name: nameController.text.trim(),
                                              description: descController.text
                                                  .trim(),
                                            );
                                        if (mounted) {
                                          messenger.showSnackBar(
                                            const SnackBar(
                                              content: Row(
                                                children: [
                                                  Icon(
                                                    Icons.hourglass_top_rounded,
                                                    color: Colors.amber,
                                                  ),
                                                  SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      'Đã đăng ký! Chờ Admin duyệt nhé.',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              duration: Duration(seconds: 4),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          messenger.showSnackBar(
                                            SnackBar(content: Text('Lỗi: $e')),
                                          );
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() => _loading = false);
                                        }
                                      }
                                    }
                                  : null,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.send_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Gửi Đăng Ký',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      nameController.dispose();
      descController.dispose();
    });
  }

  Future<void> _showThemeSelectorSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final themeState = ref.watch(themeProvider);
            final themeNotifier = ref.read(themeProvider.notifier);
            final theme = Theme.of(context);
            final primary = themeState.primaryColor;

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.88,
              ),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: primary.withValues(alpha: 0.15),
                            ),
                            child: Icon(
                              Icons.palette_rounded,
                              color: primary,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Studio Giao Diện & Màu Sắc',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Tùy biến phong cách nền, màu điểm nhấn và phông chữ',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Live Interactive Preview Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: themeState.cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: primary.withValues(alpha: 0.35),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: primary.withValues(alpha: 0.12),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Xem trước giao diện',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: primary.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    themeState.title,
                                    style: TextStyle(
                                      color: primary,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                ElevatedButton(
                                  onPressed: () {},
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    minimumSize: Size.zero,
                                  ),
                                  child: const Text(
                                    'Nút bấm chính',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: () {},
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: primary,
                                    side: BorderSide(
                                      color: primary.withValues(alpha: 0.6),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    minimumSize: Size.zero,
                                  ),
                                  child: const Text(
                                    'Đường viền',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                const Spacer(),
                                Switch.adaptive(
                                  value: true,
                                  activeTrackColor: primary,
                                  activeThumbColor: primary,
                                  onChanged: (_) {},
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Section 1: Màu Điểm Nhấn (Accent Color Palettes)
                      const Text(
                        'Màu Điểm Nhấn (Accent Color)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Chọn tông màu nổi bật cho các nút bấm, biểu tượng và thanh công cụ',
                        style: TextStyle(color: Colors.white54, fontSize: 11.5),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          // Default from Theme
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              themeNotifier.setAccentColor(null);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: themeState.customAccentColor == null
                                    ? primary.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: themeState.customAccentColor == null
                                      ? primary
                                      : Colors.white12,
                                  width: themeState.customAccentColor == null
                                      ? 1.8
                                      : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 14,
                                    color: primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Theo Theme',
                                    style: TextStyle(
                                      color:
                                          themeState.customAccentColor == null
                                          ? Colors.white
                                          : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          ...AppAccentColor.presets.map((accent) {
                            final isSelected =
                                themeState.customAccentColor?.toARGB32() ==
                                accent.color.toARGB32();
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                themeNotifier.setAccentColor(accent.color);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? accent.color.withValues(alpha: 0.22)
                                      : Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? accent.color
                                        : Colors.white12,
                                    width: isSelected ? 1.8 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: accent.color,
                                        shape: BoxShape.circle,
                                        boxShadow: isSelected
                                            ? [
                                                BoxShadow(
                                                  color: accent.color
                                                      .withValues(alpha: 0.6),
                                                  blurRadius: 6,
                                                ),
                                              ]
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      accent.label,
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.white70,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Section 2: Chế độ OLED Đen Thuần Khiết
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: themeState.usePureBlack
                              ? Colors.black
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: themeState.usePureBlack
                                ? primary
                                : Colors.white12,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Icon(
                                Icons.contrast_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Nền Đen Tuyệt Đối (Pure Black OLED)',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Tắt điểm ảnh hoàn toàn (0x000000) trên màn hình OLED để tiết kiệm pin tối đa',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: themeState.usePureBlack,
                              activeTrackColor: primary,
                              activeThumbColor: primary,
                              onChanged: (val) {
                                HapticFeedback.selectionClick();
                                themeNotifier.setPureBlack(val);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Section 3: Phong Cách Nền & Bảo Vệ Mắt (Theme Mode Presets)
                      const Text(
                        'Phong Cách Nền & Bảo Vệ Mắt',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Lựa chọn tông nền dịu mắt khi đọc trong bóng tối',
                        style: TextStyle(color: Colors.white54, fontSize: 11.5),
                      ),
                      const SizedBox(height: 12),

                      ...AppThemeMode.values.map((mode) {
                        final isSelected = themeState.mode == mode;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? mode.surfaceHighlight
                                : mode.cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? primary
                                  : Colors.white.withValues(alpha: 0.08),
                              width: isSelected ? 1.8 : 1.0,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: primary.withValues(alpha: 0.15),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                themeNotifier.setTheme(mode);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    // Theme Icon
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: mode.backgroundColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: mode.primaryColor.withValues(
                                            alpha: 0.5,
                                          ),
                                        ),
                                      ),
                                      child: Icon(
                                        mode.icon,
                                        color: mode.primaryColor,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 14),

                                    // Title & Description
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                mode.title,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: isSelected
                                                      ? FontWeight.w900
                                                      : FontWeight.w700,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              if (mode ==
                                                  AppThemeMode.warmAmber) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1.5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFFF9800,
                                                    ).withValues(alpha: 0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  child: const Text(
                                                    'BẢO VỆ MẮT',
                                                    style: TextStyle(
                                                      color: Color(0xFFFFB74D),
                                                      fontSize: 8.5,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            mode.description,
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.6,
                                              ),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Color Swatches
                                    const SizedBox(width: 8),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildColorDot(
                                          mode.backgroundColor,
                                          'Nền',
                                        ),
                                        const SizedBox(width: 4),
                                        _buildColorDot(mode.cardColor, 'Thẻ'),
                                        const SizedBox(width: 4),
                                        _buildColorDot(
                                          mode.primaryColor,
                                          'Điểm nhấn',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 10),

                                    // Checkmark Indicator
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected
                                            ? primary
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: isSelected
                                              ? primary
                                              : Colors.white30,
                                          width: 2,
                                        ),
                                      ),
                                      child: isSelected
                                          ? const Icon(
                                              Icons.check,
                                              size: 14,
                                              color: Colors.white,
                                            )
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Widget _buildColorDot(Color color, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 0.8),
        ),
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
          backgroundColor:
              Theme.of(ctx).dialogTheme.backgroundColor ??
              Theme.of(ctx).cardColor,
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
                textInputAction: TextInputAction.next,
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
                textInputAction: TextInputAction.done,
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
                    _refreshUserDoc();
                    setState(() {}); // Refresh FutureBuilder → tile "Thêm mật khẩu" biến mất
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Thêm',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      passwordController.dispose();
      confirmController.dispose();
    });
  }

  // Confirm dialog trước khi đăng xuất — showDialog<bool> trả về bool từ Navigator.pop(ctx, value)
  void _showLogoutDialog(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            Theme.of(ctx).dialogTheme.backgroundColor ??
            Theme.of(ctx).cardColor,
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Đăng xuất',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(context),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E22),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.account_circle_outlined,
                    size: 64,
                    color: Colors.white54,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Bạn chưa đăng nhập',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Đăng nhập để đồng bộ lịch sử đọc, theo dõi truyện và tham gia diễn đàn',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => context.go('/login'),
                      icon: const Icon(Icons.login, size: 18),
                      label: const Text('Đăng nhập ngay'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _buildTile(
              context,
              icon: Icons.palette_outlined,
              color: Colors.deepOrangeAccent,
              title: 'Giao diện & Bảo vệ mắt',
              subtitle: 'Chế độ: ${ref.watch(themeProvider).title}',
              onTap: () => _showThemeSelectorSheet(context),
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

            _buildTile(
              context,
              icon: Icons.bar_chart_rounded,
              color: Colors.orange,
              title: 'Thống kê đọc',
              subtitle: 'Xem hoạt động đọc truyện của bạn',
              onTap: () => context.push('/analytics'),
            ),

            _buildTile(
              context,
              icon: Icons.help_outline,
              color: Colors.green,
              title: 'Trợ giúp',
              subtitle: 'Hỏi đáp và hỗ trợ',
              onTap: () => context.push('/settings/help'),
            ),
          ],
        ),
      ),
    );
  }
}
