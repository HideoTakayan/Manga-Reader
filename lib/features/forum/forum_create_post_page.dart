import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/forum_poll.dart';
import 'services/firebase_forum_repository.dart';
import '../../data/drive_service.dart';
import '../../data/models_cloud.dart';
import 'widgets/shared_manga_card.dart';
import 'widgets/forum_composer.dart';
import 'widgets/simple_emoji_picker.dart';
import 'widgets/manga_picker_sheet.dart';

class ForumCreatePostPage extends StatefulWidget {
  final String type; // 'discussion' or 'manga_share'
  final CloudManga? initialManga;

  const ForumCreatePostPage({
    super.key,
    this.type = 'discussion',
    this.initialManga,
  });

  @override
  State<ForumCreatePostPage> createState() => _ForumCreatePostPageState();
}

class _ForumCreatePostPageState extends State<ForumCreatePostPage> {
  final _repository = FirebaseForumRepository();
  final _bodyController = TextEditingController();
  final _focusNode = FocusNode();

  bool _isSubmitting = false;
  CloudManga? _selectedManga;
  File? _imageFile;
  ForumPoll? _poll;
  bool _showEmojiPicker = false;
  final Set<String> _selectedTags = {};
  static const int _maxBodyLength = 3000;
  List<String> _suggestedTags = [];
  Stream<DocumentSnapshot>? _userSnapshotStream;

  @override
  void initState() {
    super.initState();
    _initUserStream();
    _selectedManga = widget.initialManga;
    _loadExistingTags();
    _bodyController.addListener(_onTextChanged);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
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

  Future<void> _loadExistingTags() async {
    try {
      final tags = await _repository.fetchExistingTags(
        type: widget.type == 'share' ? 'manga_share' : 'discussion',
      );
      if (mounted) {
        setState(() => _suggestedTags = tags);
      }
    } catch (_) {}
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _bodyController.removeListener(_onTextChanged);
    _bodyController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _showMangaPicker() async {
    final selectedManga = await showModalBottomSheet<CloudManga>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const MangaPickerSheet(),
    );

    if (selectedManga != null && mounted) {
      setState(() {
        _selectedManga = selectedManga;
      });
    }
  }

  Future<void> _submitPost() async {
    final body = _bodyController.text.trim();
    final isMangaShare = widget.type == 'manga_share';
    if (!isMangaShare &&
        body.isEmpty &&
        _imageFile == null &&
        _poll == null) {
      return;
    }
    if (isMangaShare &&
        body.isEmpty &&
        _selectedManga == null) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng đăng nhập')));
      return;
    }

    setState(() => _isSubmitting = true);

    final authorName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : 'Người dùng';

    try {
      if (widget.type == 'discussion') {
        await _repository.createDiscussionPost(
          uid: user.uid,
          authorName: authorName,
          authorAvatar: user.photoURL ?? '',
          body: body,
          imageFile: _imageFile,
          poll: _poll,
          tags: _selectedTags.toList(),
        );
      } else if (widget.type == 'manga_share') {
        if (_selectedManga == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Vui lòng chọn truyện để chia sẻ')),
            );
          }
          setState(() => _isSubmitting = false);
          return;
        }
        await _repository.createSharePost(
          uid: user.uid,
          authorName: authorName,
          authorAvatar: user.photoURL ?? '',
          body: body,
          sharedMangaId: _selectedManga!.id,
          sharedMangaTitle: _selectedManga!.title,
          sharedMangaCoverUrl: DriveService.instance.getThumbnailLink(
            _selectedManga!.coverFileId,
          ),
          sharedMangaAuthor: _selectedManga!.author,
          tags: _selectedTags.toList(),
        );
      }

      if (mounted) {
        context.pop(true); // Return success to reload feed
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _showAddCustomTagDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => const _AddCustomTagDialog(),
    );

    if (result != null && result.isNotEmpty && mounted) {
      final clean = result.toLowerCase().replaceAll('#', '').trim();
      if (clean.isNotEmpty) {
        setState(() => _selectedTags.add(clean));
      }
    }
  }

  Future<void> _showPollCreatorDialog() async {
    final createdPoll = await showDialog<ForumPoll>(
      context: context,
      builder: (_) => const _PollCreatorDialog(),
    );

    if (createdPoll != null && mounted) {
      setState(() => _poll = createdPoll);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          title: Text(
            widget.type == 'discussion' ? 'Tạo thảo luận' : 'Chia sẻ truyện',
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 54,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Yêu cầu đăng nhập',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bạn cần đăng nhập tài khoản để có thể đăng bài viết và chia sẻ truyện trên diễn đàn.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => context.push('/login'),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text(
                    'Đăng nhập ngay',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 12,
                    ),
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

    return PopScope(
      canPop: !_isSubmitting,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.type == 'discussion' ? 'Tạo thảo luận' : 'Chia sẻ truyện',
          ),
          actions: [
            TextButton(
              onPressed:
                  _isSubmitting ||
                      (widget.type == 'discussion' &&
                          _bodyController.text.trim().isEmpty &&
                          _imageFile == null) ||
                      (widget.type == 'manga_share' &&
                          _bodyController.text.trim().isEmpty &&
                          _selectedManga == null) ||
                      _bodyController.text.length > _maxBodyLength
                  ? null
                  : _submitPost,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('ĐĂNG', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _userSnapshotStream != null ? StreamBuilder<DocumentSnapshot>(
          stream: _userSnapshotStream,
          builder: (context, snapshot) {
            bool isBanned = false;
            bool isMuted = false;
            DateTime? mutedUntil;

            if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
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

            if (isBanned) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.block, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text(
                      'Tài khoản của bạn đã bị cấm khỏi diễn đàn.',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Bạn không thể tạo bài viết mới.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => context.pop(),
                      child: const Text('Quay lại'),
                    ),
                  ],
                ),
              );
            }

            if (isMuted) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.volume_off, size: 64, color: Colors.orange),
                    const SizedBox(height: 16),
                    const Text(
                      'Tài khoản của bạn đang bị cấm ngôn.',
                      style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Thời hạn: ${mutedUntil != null ? "${mutedUntil.day}/${mutedUntil.month}/${mutedUntil.year} ${mutedUntil.hour}:${mutedUntil.minute.toString().padLeft(2, '0')}" : "Không rõ"}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => context.pop(),
                      child: const Text('Quay lại'),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bodyController,
                    focusNode: _focusNode,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      hintText: 'Bạn đang nghĩ gì?',
                      border: InputBorder.none,
                    ),
                  ),
                ),

                // Character counter
                Align(
                  alignment: Alignment.centerRight,
                  child: Builder(builder: (context) {
                    final count = _bodyController.text.length;
                    final isNearLimit = count > _maxBodyLength * 0.9;
                    final isOverLimit = count > _maxBodyLength;
                    return Text(
                      '$count / $_maxBodyLength',
                      style: TextStyle(
                        fontSize: 12,
                        color: isOverLimit
                            ? Colors.redAccent
                            : isNearLimit
                                ? Colors.orangeAccent
                                : Theme.of(context).disabledColor,
                        fontWeight: isOverLimit ? FontWeight.bold : FontWeight.normal,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 4),

                // Preview
                if (_imageFile != null)
                  Stack(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_imageFile!, fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          icon: const Icon(Icons.cancel),
                          color: Colors.white,
                          onPressed: () => setState(() => _imageFile = null),
                        ),
                      ),
                    ],
                  ),


                if (_poll != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.poll_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _poll!.question,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              icon: const Icon(Icons.cancel, color: Colors.white70, size: 20),
                              onPressed: () => setState(() => _poll = null),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ..._poll!.options.map((opt) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.radio_button_unchecked,
                                    size: 14,
                                    color: Colors.white54,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      opt,
                                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),

                if (widget.type == 'manga_share') ...[
                  const SizedBox(height: 16),
                  if (_selectedManga != null)
                    SharedMangaCard(
                      mangaId: _selectedManga!.id,
                      title: _selectedManga!.title,
                      coverUrl: DriveService.instance.getThumbnailLink(
                        _selectedManga!.coverFileId,
                      ),
                      author: _selectedManga!.author,
                      onTap: () {}, // Do nothing in preview
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _showMangaPicker,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Chọn truyện để chia sẻ', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                  if (_selectedManga != null)
                    TextButton(
                      onPressed: _showMangaPicker,
                      child: const Text('Đổi truyện khác'),
                    ),
                ],
                // Hashtags Selector Bar
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.tag_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 6),
                              const Text(
                                'Hashtag / Nhãn dán',
                                style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _showAddCustomTagDialog,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.add, size: 14, color: Theme.of(context).colorScheme.primary),
                                  const SizedBox(width: 2),
                                  Text(
                                    '+ Tự gõ tag',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // Custom tags added by user
                            ..._selectedTags.map((tag) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: FilterChip(
                                  selected: true,
                                  label: Text('#$tag'),
                                  selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                                  checkmarkColor: Theme.of(context).colorScheme.primary,
                                  labelStyle: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                  ),
                                  side: BorderSide(color: Theme.of(context).colorScheme.primary),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  onSelected: (val) {
                                    HapticFeedback.selectionClick();
                                    setState(() => _selectedTags.remove(tag));
                                  },
                                ),
                              );
                            }),
                            // Suggested tags
                            ..._suggestedTags.where((t) => !_selectedTags.contains(t)).map((tag) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: FilterChip(
                                  selected: false,
                                  label: Text('#$tag'),
                                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                                  labelStyle: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11.5,
                                  ),
                                  side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  onSelected: (val) {
                                    HapticFeedback.selectionClick();
                                    setState(() => _selectedTags.add(tag));
                                  },
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                ForumComposer(
                  showImagePicker:
                      widget.type ==
                      'discussion', // Không cho đính ảnh nếu đang share truyện để đỡ rối
                  onPollPressed: widget.type == 'discussion' ? _showPollCreatorDialog : null,
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

                if (_showEmojiPicker)
                  SizedBox(
                    height: 250,
                    child: SimpleEmojiPicker(controller: _bodyController),
                  ),
              ],
            );
          },
        ) : const SizedBox.shrink(),
      ),
    ),
  );
}
}

class _AddCustomTagDialog extends StatefulWidget {
  const _AddCustomTagDialog();

  @override
  State<_AddCustomTagDialog> createState() => _AddCustomTagDialogState();
}

class _AddCustomTagDialogState extends State<_AddCustomTagDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      Navigator.pop(context, text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return AlertDialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Icon(Icons.tag_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            'Thêm Hashtag Tự Do',
            style: TextStyle(color: onSurface, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: TextStyle(color: onSurface),
        decoration: InputDecoration(
          hintText: 'Ví dụ: review, trinhtham, onepiece...',
          hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.4)),
          prefixText: '#',
          prefixStyle: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
          filled: true,
          fillColor: onSurface.withValues(alpha: 0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Hủy', style: TextStyle(color: onSurface.withValues(alpha: 0.6))),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _submit,
          child: const Text('Thêm'),
        ),
      ],
    );
  }
}

class _PollCreatorDialog extends StatefulWidget {
  const _PollCreatorDialog();

  @override
  State<_PollCreatorDialog> createState() => _PollCreatorDialogState();
}

class _PollCreatorDialogState extends State<_PollCreatorDialog> {
  late final TextEditingController _questionCtrl;
  late final List<TextEditingController> _optionCtrls;

  @override
  void initState() {
    super.initState();
    _questionCtrl = TextEditingController();
    _optionCtrls = [
      TextEditingController(),
      TextEditingController(),
    ];
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    for (final ctrl in _optionCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionCtrls.length < 6) {
      setState(() {
        _optionCtrls.add(TextEditingController());
      });
    }
  }

  void _removeOption(int index) {
    if (_optionCtrls.length > 2) {
      setState(() {
        final removed = _optionCtrls.removeAt(index);
        removed.dispose();
      });
    }
  }

  void _submit() {
    final question = _questionCtrl.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập câu hỏi bình chọn')),
      );
      return;
    }
    final validOptions = _optionCtrls
        .map((c) => c.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
    if (validOptions.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập ít nhất 2 lựa chọn')),
      );
      return;
    }
    Navigator.pop(
      context,
      ForumPoll(
        question: question,
        options: validOptions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return AlertDialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.poll_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            'Tạo bình chọn',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: onSurface),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _questionCtrl,
              style: TextStyle(color: onSurface),
              decoration: InputDecoration(
                hintText: 'Câu hỏi bình chọn...',
                hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.4)),
                filled: true,
                fillColor: onSurface.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Các lựa chọn (Tối thiểu 2, tối đa 6):',
              style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 8),
            ...List.generate(_optionCtrls.length, (idx) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _optionCtrls[idx],
                        style: TextStyle(color: onSurface),
                        decoration: InputDecoration(
                          hintText: 'Lựa chọn ${idx + 1}',
                          hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.4)),
                          filled: true,
                          fillColor: onSurface.withValues(alpha: 0.05),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                    ),
                    if (_optionCtrls.length > 2) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                        onPressed: () => _removeOption(idx),
                      ),
                    ],
                  ],
                ),
              );
            }),
            if (_optionCtrls.length < 6)
              TextButton.icon(
                onPressed: _addOption,
                icon: Icon(Icons.add, size: 18, color: theme.colorScheme.primary),
                label: Text('Thêm lựa chọn', style: TextStyle(color: theme.colorScheme.primary)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Hủy', style: TextStyle(color: onSurface.withValues(alpha: 0.6))),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _submit,
          child: const Text('Tạo', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

