import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  User? get currentUser => FirebaseAuth.instance.currentUser;

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    final user = FirebaseAuth.instance.currentUser;

    if (text.isEmpty || user == null) return;

    // 🔹 Lấy thông tin user từ Firestore
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final userData = userDoc.data();

    final senderName = userData?['name'] ?? user.displayName ?? 'Ẩn danh';
    final senderAvatarBase64 = userData?['avatarBase64'] ?? '';

    // 🔹 Gửi tin nhắn vào Firestore
    await FirebaseFirestore.instance
        .collection('chats')
        .doc('room_global')
        .collection('messages')
        .add({
      'text': text,
      'senderId': user.uid,
      'senderName': senderName,
      'avatarBase64': senderAvatarBase64,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _controller.clear();

    // 🔹 Cuộn xuống cuối
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundImage: NetworkImage(
                'https://cdn-icons-png.flaticon.com/512/149/149071.png',
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Phòng Chat Cộng Đồng',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc('room_global')
                  .collection('messages')
                  .orderBy('timestamp')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  controller: _scrollController,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final data = msg.data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == currentUser?.uid;

                    // 🔹 An toàn khi đọc avatarBase64
                    final avatarBase64 = data.containsKey('avatarBase64')
                        ? data['avatarBase64']
                        : '';
                    final senderName = data.containsKey('senderName')
                        ? data['senderName']
                        : 'Ẩn danh';

                    ImageProvider avatarImage;
                    if (avatarBase64 != null && avatarBase64.isNotEmpty) {
                      avatarImage = MemoryImage(base64Decode(avatarBase64));
                    } else {
                      avatarImage = const NetworkImage(
                          'https://cdn-icons-png.flaticon.com/512/149/149071.png');
                    }

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (!isMe)
                              CircleAvatar(
                                radius: 16,
                                backgroundImage: avatarImage,
                              ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? Colors.blueAccent.withOpacity(0.8)
                                      : const Color(0xFF2C2C2E),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (!isMe)
                                      Text(
                                        senderName,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12),
                                      ),
                                    Text(
                                      data['text'] ?? '',
                                      style:
                                          const TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: const Color(0xFF2C2C2E),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Nhập tin nhắn...',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.blueAccent),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
