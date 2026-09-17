import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/firebase_forum_repository.dart';
import 'models/forum_message.dart';
import 'widgets/chat_message_bubble.dart';
import 'widgets/report_dialog.dart';
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
  bool _hasLoadedOlder = false;
  bool _hasMore = true;
  bool _isSending = false;
  bool _isInitialLoading = true;
  bool _showEmojiPicker = false;
  File? _imageFile;
  ForumMessage? _replyingTo;
  Timer? _muteTimer;
  DateTime? _currentMutedUntil;

  void _scheduleMuteTimer(DateTime mutedUntil) {
    _muteTimer?.cancel();
    final delay = mutedUntil.difference(DateTime.now());
    if (delay.isNegative) return;
    _muteTimer = Timer(delay, () {
      if (mounted) setState(() {});
    });
  }

  Stream<DocumentSnapshot>? _userSnapshotStream;

  @override
  void initState() {
    super.initState();
    _initUserStream();
    _scrollController.addListener(_onScroll);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && mounted) {
        setState(() {
          _showEmojiPicker = false;
        });
      }
    });
  }

  void _initUserStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userSnapshotStream = FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();
    } else {
      _userSnapshotStream = null;
    }
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
    _muteTimer?.cancel();
    _tabController?.removeListener(_onTabChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _streamSubscription?.cancel();
    _messageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _subscribeToMessages() {
    _streamSubscription = _repository.streamLatestMessages().listen(
      (newMessages) {
        if (!mounted) return;
        setState(() {
          if (!_hasLoadedOlder) {
            _messages.clear();
            _messages.addAll(newMessages);
          } else {
            // Đã load tin cũ: cập nhật các tin hiện tại hoặc chèn thêm tin mới nhất
            for (var newMsg in newMessages.reversed) {
              final index = _messages.indexWhere((m) => m.id == newMsg.id);
              if (index != -1) {
                _messages[index] = newMsg; // Cập nhật tin có sẵn
              } else {
                _messages.insert(0, newMsg); // Thêm tin mới nhất vào đầu
              }
            }
            // Đảm bảo thứ tự mới nhất -> cũ nhất
            _messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
        if (olderMessages.isNotEmpty) {
          _hasLoadedOlder = true;
          // Loại bỏ trùng lặp nếu có
          final existingIds = _messages.map((m) => m.id).toSet();
          final uniqueOlder = olderMessages.where((m) => !existingIds.contains(m.id)).toList();
          _messages.addAll(uniqueOlder);
        }
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
    if (!_scrollController.hasClients) return;
    // ListView is reversed, so scrolling to bottom of screen means scrolling to maxScrollExtent
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadOlderMessages();
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _imageFile == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để chat')),
      );
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _isSending = true);

    final authorName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : 'Người dùng';

    try {
      await _repository.sendMessage(
        uid: user.uid,
        authorName: authorName,
        authorAvatar: user.photoURL ?? '',
        body: text,
        imageFile: _imageFile,
        replyToMessageId: _replyingTo?.id,
        replyToUserId: _replyingTo?.authorId,
        replyToAuthorName: _replyingTo?.authorName,
        replyToBody: _replyingTo?.body.isNotEmpty == true
            ? _replyingTo!.body
            : (_replyingTo?.imageUrl != null
                ? 'Hình ảnh/GIF'
                : null),
      );

      if (mounted) {
        _messageController.clear();
        setState(() {
          _imageFile = null;
          _replyingTo = null;
        });
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
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

  void _mentionUser(String authorName) {
    final currentText = _messageController.text;
    final mention = '@$authorName ';
    if (currentText.isEmpty) {
      _messageController.text = mention;
    } else if (currentText.endsWith(' ')) {
      _messageController.text = '$currentText$mention';
    } else {
      _messageController.text = '$currentText $mention';
    }
    _messageController.selection = TextSelection.fromPosition(
      TextPosition(offset: _messageController.text.length),
    );
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return _buildChatLayout(null, false, null, false);
    }

    if (_userSnapshotStream != null) {
      return StreamBuilder<DocumentSnapshot>(
        stream: _userSnapshotStream,
        builder: (context, snapshot) {
        bool isMuted = false;
        bool isBanned = false;
        DateTime? mutedUntil;

        if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          if (data['isBanned'] == true) {
            isBanned = true;
          }
          if (data['mutedUntil'] != null) {
            mutedUntil = (data['mutedUntil'] as Timestamp).toDate();
            if (mutedUntil.isAfter(DateTime.now())) {
              isMuted = true;
            }
          }
        }

        if (mutedUntil != _currentMutedUntil) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _currentMutedUntil = mutedUntil;
            if (isMuted && mutedUntil != null) {
              _scheduleMuteTimer(mutedUntil);
            } else {
              _muteTimer?.cancel();
            }
          });
        }

        if (isMuted || isBanned) {
          if (_showEmojiPicker) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (_showEmojiPicker) setState(() => _showEmojiPicker = false);
            });
          }
        }

        return _buildChatLayout(user, isMuted, mutedUntil, isBanned);
      },
    );
    }
    
    return _buildChatLayout(user, false, null, false);
  }

  Widget _buildChatLayout(User? user, bool isMuted, DateTime? mutedUntil, bool isBanned) {
    return PopScope(
      canPop: !_showEmojiPicker,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showEmojiPicker) {
          setState(() => _showEmojiPicker = false);
        }
      },
      child: Column(
      children: [
        Expanded(
          child: _isInitialLoading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.forum_outlined,
                          size: 44,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Chưa có tin nhắn nào',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Hãy là người đầu tiên gửi tin nhắn trò chuyện!',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
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
                    final message = _messages[index];
                    
                    final nextMsg = index > 0 ? _messages[index - 1] : null; // Newer message (visual bottom)
                    final prevMsg = index < _messages.length - 1 ? _messages[index + 1] : null; // Older message (visual top)

                    bool isSameGroup(ForumMessage a, ForumMessage? b) {
                      if (b == null) return false;
                      if (a.authorId != b.authorId) return false;
                      final diff = a.createdAt.difference(b.createdAt).inMinutes.abs();
                      return diff < 5;
                    }

                    final isFirstInSequence = !isSameGroup(message, prevMsg);
                    final isLastInSequence = !isSameGroup(message, nextMsg);

                    return ChatMessageBubble(
                      message: message,
                      isFirstInSequence: isFirstInSequence,
                      isLastInSequence: isLastInSequence,
                      onDelete: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (dialogCtx) => AlertDialog(
                            backgroundColor: Theme.of(dialogCtx).dialogTheme.backgroundColor ?? Theme.of(dialogCtx).cardColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: Text(
                              'Xóa tin nhắn',
                              style: TextStyle(
                                color: Theme.of(dialogCtx).colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            content: Text(
                              'Bạn có chắc muốn xóa tin nhắn này?',
                              style: TextStyle(
                                color: Theme.of(dialogCtx).colorScheme.onSurface.withValues(alpha: 0.75),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogCtx, false),
                                child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => Navigator.pop(dialogCtx, true),
                                child: const Text('Xóa', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                        if (!context.mounted) return;

                        try {
                          await _repository.softDeleteMessage(message.id);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Đã xóa tin nhắn'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                        }
                      },
                      onMute: (duration) async {
                        try {
                          await _repository.muteForumUser(
                            userId: message.authorId,
                            duration: duration,
                            reason: 'Vi phạm quy định diễn đàn',
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Đã cấm ngôn người dùng'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                        }
                      },
                      onUnmute: () async {
                        try {
                          await _repository.unmuteForumUser(message.authorId);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Đã gỡ cấm ngôn'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                        }
                      },
                      onReport: () {
                        showDialog(
                          context: context,
                          builder: (context) => ReportDialog(
                            targetType: 'message',
                            targetId: message.id,
                            postId: '',
                          ),
                        );
                      },
                      onReply: () {
                        setState(() {
                          _replyingTo = message;
                          _focusNode.requestFocus();
                        });
                      },
                      onMention: () => _mentionUser(message.authorName),
                      onReact: (emoji) {
                        if (user == null) {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Vui lòng đăng nhập để thả cảm xúc'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        _repository.toggleMessageReaction(
                          messageId: message.id,
                          uid: user.uid,
                          emoji: emoji,
                        );
                      },
                    );
                  },
                ),
        ),

        // Input bar
        if (isBanned)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.red.withValues(alpha: 0.1),
            child: const Text(
              'Tài khoản của bạn đã bị cấm khỏi diễn đàn',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          )
        else if (isMuted && mutedUntil != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.orange.withValues(alpha: 0.1),
            child: Text(
              'Bạn đang bị cấm ngôn đến ${mutedUntil.hour}:${mutedUntil.minute.toString().padLeft(2, '0')} ${mutedUntil.day}/${mutedUntil.month}/${mutedUntil.year}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
            ),
          ),
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
                if (_replyingTo != null)
                  Container(
                    width: double.infinity,
                    color: Theme.of(context).cardColor,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.reply, size: 20, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Đang trả lời ${_replyingTo!.authorName}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                _replyingTo!.body.isNotEmpty
                                    ? _replyingTo!.body
                                    : 'Hình ảnh/GIF',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => setState(() => _replyingTo = null),
                        ),
                      ],
                    ),
                  ),
                if (_imageFile != null)
                  Stack(
                    children: [
                      Container(
                        height: 100,
                        width: double.infinity,
                        margin: const EdgeInsets.all(8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_imageFile!, fit: BoxFit.contain),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: IconButton(
                          icon: const Icon(Icons.cancel),
                          color: Colors.red,
                          onPressed: () => setState(() => _imageFile = null),
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
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      ForumComposer(
                        showImagePicker: true,
                        enabled: !isMuted && !isBanned,
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
                        onImageSelected: (file) {
                          setState(() {
                            _imageFile = file;
                          });
                        },
                      ),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          focusNode: _focusNode,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.send,
                          decoration: InputDecoration(
                            hintText: user == null
                                ? 'Đăng nhập...'
                                : isBanned
                                    ? 'Đã bị cấm'
                                    : isMuted
                                        ? 'Đang bị cấm ngôn'
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
                          enabled: user != null && !isMuted && !isBanned,
                          maxLines: 4,
                          minLines: 1,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      IconButton(
                        onPressed: user == null || _isSending || isMuted || isBanned
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
                            : const Icon(Icons.send_rounded),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
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
    ),
    );
  }
}
