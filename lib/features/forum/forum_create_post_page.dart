import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/firebase_forum_repository.dart';
import '../../data/drive_service.dart';
import '../../data/models_cloud.dart';
import 'widgets/shared_manga_card.dart';
import 'widgets/forum_composer.dart';
import 'widgets/simple_emoji_picker.dart';
import 'widgets/manga_picker_sheet.dart';

class ForumCreatePostPage extends StatefulWidget {
  final String type; // 'discussion' or 'manga_share'

  const ForumCreatePostPage({super.key, this.type = 'discussion'});

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
  String? _gifUrl;
  bool _showEmojiPicker = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() {
          _showEmojiPicker = false;
        });
      }
    });
  }

  @override
  void dispose() {
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
    if (body.isEmpty && _gifUrl == null && _imageFile == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng đăng nhập')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (widget.type == 'discussion') {
        await _repository.createDiscussionPost(
          uid: user.uid,
          authorName: user.displayName ?? 'Người dùng',
          authorAvatar: user.photoURL ?? '',
          body: body,
          gifUrl: _gifUrl,
          imageFile: _imageFile,
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
          authorName: user.displayName ?? 'Người dùng',
          authorAvatar: user.photoURL ?? '',
          body: body,
          sharedMangaId: _selectedManga!.id,
          sharedMangaTitle: _selectedManga!.title,
          sharedMangaCoverUrl: DriveService.instance.getThumbnailLink(
            _selectedManga!.coverFileId,
          ),
          sharedMangaAuthor: _selectedManga!.author,
          gifUrl: _gifUrl,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.type == 'discussion' ? 'Tạo thảo luận' : 'Chia sẻ truyện',
        ),
        actions: [
          TextButton(
            onPressed:
                _isSubmitting ||
                    (_bodyController.text.trim().isEmpty &&
                        _gifUrl == null &&
                        _imageFile == null)
                ? null
                : _submitPost,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('ĐĂNG'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _bodyController,
                focusNode: _focusNode,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  hintText: 'Bạn đang nghĩ gì?',
                  border: InputBorder.none,
                ),
                onChanged: (text) {
                  setState(() {}); // Cập nhật trạng thái nút ĐĂNG
                },
              ),
            ),

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

            if (_gifUrl != null)
              Stack(
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(_gifUrl!, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(Icons.cancel),
                      color: Colors.white,
                      onPressed: () => setState(() => _gifUrl = null),
                    ),
                  ),
                ],
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
                  label: const Text('Chọn truyện để chia sẻ'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
              if (_selectedManga != null)
                TextButton(
                  onPressed: _showMangaPicker,
                  child: const Text('Đổi truyện khác'),
                ),
            ],
            ForumComposer(
              showImagePicker:
                  widget.type ==
                  'discussion', // Không cho đính ảnh nếu đang share truyện để đỡ rối
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
                  _imageFile = null; // Chỉ chọn 1 trong 2
                });
              },
              onImageSelected: (file) {
                setState(() {
                  _imageFile = file;
                  _gifUrl = null;
                });
              },
            ),

            if (_showEmojiPicker)
              SizedBox(
                height: 250,
                child: SimpleEmojiPicker(controller: _bodyController),
              ),
          ],
        ),
      ),
    );
  }
}
