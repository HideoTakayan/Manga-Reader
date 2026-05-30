import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../../forum/services/image_upload_service.dart';

// Trang chỉnh sửa hồ sơ: tên hiển thị, bio, avatar.
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  File? _imageFile; // File ảnh mới chọn từ gallery (chưa encode)
  String? _avatarUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData(); // Pre-fill form với dữ liệu hiện tại từ Firestore
  }

  // Lấy data Firestore 1 lần (get, không phải snapshots) — chỉ cần khi mở trang
  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      _avatarUrl = user.photoURL;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      if (data == null) {
        if (mounted) setState(() {});
        return;
      }
      _nameController.text =
          data['displayName'] ?? data['name'] ?? user.displayName ?? '';
      _bioController.text = data['bio'] ?? '';
      _avatarUrl = data['avatarUrl'] ?? user.photoURL;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi tải hồ sơ: $e')));
      }
    }
  }

  // Chọn ảnh từ gallery. Ảnh chỉ preview local ở đây, khi lưu mới upload lên Cloudinary.
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final file = File(picked.path);
      if (!mounted) return;
      setState(() {
        _imageFile = file;
      });
    }
  }

  Future<void> _saveChanges() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isLoading = true);

    try {
      String? avatarUrl;
      if (_imageFile != null) {
        avatarUrl = await ImageUploadService.uploadAvatarImage(
          _imageFile!,
          user.uid,
        );
        await user.updatePhotoURL(avatarUrl);
      }

      final displayName = _nameController.text.trim();
      await user.updateDisplayName(displayName);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': displayName,
        'displayName': displayName,
        'bio': _bioController.text.trim(),
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
        if (avatarUrl != null) ...{
          'avatarUrl': avatarUrl,
          'avatarBase64': FieldValue.delete(),
        },
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cập nhật thông tin thành công!')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? avatarImage;
    if (_imageFile != null) {
      avatarImage = FileImage(_imageFile!);
    } else if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      avatarImage = NetworkImage(_avatarUrl!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chỉnh sửa thông tin'),
        backgroundColor: Colors.blueAccent,
      ),
      // Spinner toàn màn hình khi đang lưu — tránh double tap
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // GestureDetector bao CircleAvatar → tap để chọn ảnh
                    GestureDetector(
                      onTap: _pickImage,
                      child: CircleAvatar(
                        radius: 50,
                        backgroundImage: avatarImage,
                        backgroundColor: Colors.grey[300],
                        // Camera icon khi chưa có ảnh
                        child: avatarImage == null
                            ? const Icon(Icons.camera_alt, size: 40)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Tên hiển thị',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _bioController,
                      decoration: const InputDecoration(
                        labelText: 'Giới thiệu bản thân',
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _saveChanges,
                      icon: const Icon(Icons.save),
                      label: const Text('Lưu thay đổi'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
