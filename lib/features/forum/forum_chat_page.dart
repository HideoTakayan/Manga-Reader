import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/firebase_forum_repository.dart';
import 'models/forum_message.dart';
import 'widgets/chat_message_bubble.dart';
import 'widgets/forum_composer.dart';
import 'widgets/simple_emoji_picker.dart';

class ForumChatPage extends StatefulWidget {
  const ForumChatPage({super.key});

  @override
  State<ForumChatPage> createState() => _ForumChatPageState();
}

class _ForumChatPageState extends State<ForumChatPage> {
  final _repository = FirebaseForumRepository();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  TabController? _tabController;

  StreamSubscription<List<ForumMessage>>? _streamSubscription;
  final List<ForumMessage> _messages = [];
  bool _isLoadingOlder = false;
  bool _hasMore = true;
  bool _isSending = false;
  bool _isInitialLoading = true;
  bool _showEmojiPicker = false;
  String? _gifUrl;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() {
          _showEmojiPicker = false;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tabController == null) {
      _tabController = DefaultTabController.maybeOf(context);
      _tabController?.addListener(_onTabChanged);
      _onTabChanged(); // Check initial state
    }
  }

  void _onTabChanged() {
    if (!mounted) return;
    if (_tabController?.index == 0) {
      if (_streamSubscription == null) {
        _subscribeToMessages();
      }
    } else {
      _streamSubscription?.cancel();
      _streamSubscription = null;
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChanged);
    _streamSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _subscribeToMessages() {
    _streamSubscription = _repository.streamLatestMessages().listen(
      (newMessages) {
        if (!mounted) return;
        setState(() {
          // If it's the first load, replace all
          if (_messages.isEmpty) {
            _messages.addAll(newMessages);
          } else {
            // Merge logic: we have reverse list (index 0 is newest)
            // For simplicity in Phase 4 MVP, we just update the top of the list or replace if we haven't loaded older.
            // Since it's a stream of the top 50, if we haven't scrolled past 50, we can just replace the first N elements.
            // A robust way is to use a Map, but for this MVP, if we haven't loaded older messages, replace all.
            // If we have loaded older, we just prepend the very newest ones.

            if (_messages.length <= 50) {
              _messages.clear();
              _messages.addAll(newMessages);
            } else {
              // We have older messages. Find which of newMessages are actually new.
              for (var newMsg in newMessages.reversed) {
                final index = _messages.indexWhere((m) => m.id == newMsg.id);
                if (index != -1) {
                  _messages[index] = newMsg; // Update existing
                } else {
                  _messages.insert(0, newMsg); // Prepend new
                }
              }
            }
          }
          _isInitialLoading = false;
        });
      },
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Lỗi tải chat: $error')));
        }
      },
    );
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingOlder || !_hasMore || _messages.isEmpty) return;

    setState(() => _isLoadingOlder = true);

    try {
      // Find the oldest message document snapshot to pass to startAfter
      // _messages is ordered newest first, so the oldest is at the end.
      final oldestMsg = _messages.last;
      final docSnap = await FirebaseFirestore.instance
          .collection('forumMessages')
          .doc(oldestMsg.id)
          .get();

      final olderMessages = await _repository.loadOlderMessages(
        startAfter: docSnap,
      );

      if (!mounted) return;

      setState(() {
        if (olderMessages.isEmpty || olderMessages.length < 50) {
          _hasMore = false;
        }
        _messages.addAll(olderMessages);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi tải thêm tin: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingOlder = false);
      }
    }
  }

  void _onScroll() {
    // ListView is reversed, so scrolling to bottom of screen means scrolling to maxScrollExtent
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadOlderMessages();
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _gifUrl == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để chat')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      await _repository.sendMessage(
        uid: user.uid,
        authorName: user.displayName ?? 'Người dùng',
        authorAvatar: user.photoURL ?? '',
        body: text,
        gifUrl: _gifUrl,
      );

      if (mounted) {
        _messageController.clear();
        setState(() {
          _gifUrl = null;
        });
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi gửi tin: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Column(
      children: [
        Expanded(
          child: _isInitialLoading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
              ? const Center(child: Text('Chưa có tin nhắn nào'))
              : ListView.builder(
                  controller: _scrollController,
                  reverse: true, // Tin mới nhất ở dưới cùng
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _messages.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    return ChatMessageBubble(message: _messages[index]);
                  },
                ),
        ),

        // Input bar
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
              ),
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                if (_gifUrl != null)
                  Stack(
                    children: [
                      Container(
                        height: 100,
                        width: double.infinity,
                        margin: const EdgeInsets.all(8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(_gifUrl!, fit: BoxFit.contain),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: IconButton(
                          icon: const Icon(Icons.cancel),
                          color: Colors.red,
                          onPressed: () => setState(() => _gifUrl = null),
                        ),
                      ),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          focusNode: _focusNode,
                          decoration: InputDecoration(
                            hintText: user == null
                                ? 'Vui lòng đăng nhập...'
                                : 'Nhập tin nhắn...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Theme.of(context).cardColor,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          enabled: user != null,
                          maxLines: 4,
                          minLines: 1,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: user == null || _isSending
                            ? null
                            : _sendMessage,
                        icon: _isSending
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                        color: const Color(0xFFFF5252),
                      ),
                    ],
                  ),
                ),
                ForumComposer(
                  showImagePicker: false, // Chat chỉ hỗ trợ emoji, GIF
                  onEmojiPressed: () {
                    setState(() {
                      _showEmojiPicker = !_showEmojiPicker;
                      if (_showEmojiPicker) {
                        _focusNode.unfocus();
                      } else {
                        _focusNode.requestFocus();
                      }
                    });
                  },
                  onGifSelected: (url) {
                    setState(() {
                      _gifUrl = url;
                    });
                  },
                  onImageSelected: (file) {}, // Not used
                ),
                if (_showEmojiPicker)
                  SizedBox(
                    height: 250,
                    child: SimpleEmojiPicker(controller: _messageController),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
