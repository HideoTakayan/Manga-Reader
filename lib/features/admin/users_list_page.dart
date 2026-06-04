import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UsersListPage extends StatelessWidget {
  const UsersListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Danh sách người dùng')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Lỗi tải danh sách: ${snapshot.error}\n\n(Lưu ý: Nếu bị permission-denied, hãy chắc chắn bạn đã đăng nhập đúng tài khoản Admin và ĐÃ PUBLISH bản cập nhật firestore.rules lên Firebase Console)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Không có người dùng nào'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>? ?? {};
              final name = data['displayName'] ?? data['name'] ?? 'Người dùng';
              final email = data['email'] ?? 'Không có email';
              final photoUrl =
                  data['avatarUrl'] ?? data['avatar'] ?? data['photoURL'] ?? '';
              final isBanned = data['isBanned'] == true;

              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                      ? NetworkImage(photoUrl)
                      : null,
                  child: photoUrl == null || photoUrl.isEmpty
                      ? const Icon(Icons.person)
                      : null,
                ),
                title: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isBanned ? Colors.red : null,
                  ),
                ),
                subtitle: Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isBanned
                    ? const Icon(Icons.block, color: Colors.red)
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
