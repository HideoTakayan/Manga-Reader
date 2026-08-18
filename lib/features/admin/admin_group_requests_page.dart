import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/group_service.dart';
import '../../data/models_group.dart';

class AdminGroupRequestsPage extends StatelessWidget {
  const AdminGroupRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Duyệt Nhóm dịch'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.group_add), text: 'Nhóm chờ duyệt'),
              Tab(icon: Icon(Icons.cloud_outlined), text: 'Yêu cầu Drive'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PendingGroupsTab(),
            _DriveRequestsTab(),
          ],
        ),
      ),
    );
  }
}

// ── Tab 1: Nhóm dịch chờ duyệt ────────────────────────────────────────────

class _PendingGroupsTab extends StatelessWidget {
  const _PendingGroupsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('scanlation_groups')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Lỗi tải dữ liệu'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                SizedBox(height: 12),
                Text('Không có nhóm nào đang chờ duyệt'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final group = ScanlationGroup.fromFirestore(docs[index]);
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    if (group.description.isNotEmpty)
                      Text(group.description, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 12),

                    // Email trưởng nhóm để copy thêm vào test users
                    if (group.leaderEmail.isNotEmpty) ...[
                      const Divider(),
                      const SizedBox(height: 8),
                      const Row(
                        children: [
                          Icon(Icons.email_outlined, size: 16, color: Colors.blue),
                          SizedBox(width: 6),
                          Text('Google account (trưởng nhóm):', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _EmailCopyRow(email: group.leaderEmail),
                      const SizedBox(height: 4),
                      const Text(
                        '⚡ Thêm email này vào Google Cloud Console → OAuth → Test Users\nđể trưởng nhóm có thể kết nối Google Drive trong app.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                    ],

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: const Text('Từ chối', style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                          onPressed: () async {
                            try {
                              await GroupService.instance.rejectGroup(group.id);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Đã từ chối nhóm!')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                              }
                            }
                          },
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.check, color: Colors.white),
                          label: const Text('Duyệt', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          onPressed: () async {
                            try {
                              await GroupService.instance.approveGroup(group.id, group.leaderId);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Đã duyệt nhóm thành công!')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Tab 2: Yêu cầu truy cập Google Drive ──────────────────────────────────

class _DriveRequestsTab extends StatelessWidget {
  const _DriveRequestsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('drive_access_requests')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Lỗi tải dữ liệu'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = List<QueryDocumentSnapshot>.from(snapshot.data!.docs);
        docs.sort((a, b) {
          final aDate = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          final bDate = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          if (aDate == null || bDate == null) return 0;
          return bDate.compareTo(aDate);
        });
        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_done, size: 64, color: Colors.green),
                SizedBox(height: 12),
                Text('Không có yêu cầu truy cập Drive nào'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final email = data['email'] ?? '';
            final displayName = data['displayName'] ?? '';
            final groupName = data['groupName'] ?? '';
            final docId = docs[index].id;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_outline, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            displayName.isNotEmpty ? displayName : 'Thành viên',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        // Badge nhóm
                        if (groupName.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                            ),
                            child: Text(groupName, style: const TextStyle(fontSize: 11, color: Colors.purple)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Email cần copy để thêm vào test users
                    const Text('Email Google cần thêm vào Test Users:',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    _EmailCopyRow(email: email),
                    const SizedBox(height: 4),
                    const Text(
                      '📌 Bước 1: Vào Google Cloud Console → OAuth consent screen → Test Users → ADD USERS\n📌 Bước 2: Trên Google Drive, chia sẻ quyền "Người chỉnh sửa" (Editor) cho email này trên thư mục MangaReader_Data (hoặc để thư mục chế độ "Bất kỳ ai có liên kết đều có thể chỉnh sửa")',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),

                    // Nút đánh dấu đã xử lý
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check, color: Colors.white, size: 16),
                        label: const Text('Đã thêm vào Test Users', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('drive_access_requests')
                              .doc(docId)
                              .update({'status': 'done'});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Đã đánh dấu xong cho $email')),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Widget dùng chung: hiển thị email + nút copy ──────────────────────────

class _EmailCopyRow extends StatelessWidget {
  final String email;
  const _EmailCopyRow({required this.email});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(email, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy email',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: email));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Đã copy: $email'), duration: const Duration(seconds: 2)),
              );
            },
          ),
        ],
      ),
    );
  }
}
