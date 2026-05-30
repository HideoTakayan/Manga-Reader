import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'gif_picker_sheet.dart';

class ForumComposer extends StatelessWidget {
  final VoidCallback onEmojiPressed;
  final ValueChanged<String> onGifSelected;
  final ValueChanged<File> onImageSelected;
  final bool showImagePicker;

  const ForumComposer({
    super.key,
    required this.onEmojiPressed,
    required this.onGifSelected,
    required this.onImageSelected,
    this.showImagePicker = true,
  });

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70, // Giảm chất lượng ảnh sơ bộ
    );
    if (pickedFile != null) {
      onImageSelected(File(pickedFile.path));
    }
  }

  void _showGifPicker(BuildContext context) async {
    final gifUrl = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const GifPickerSheet(),
    );
    if (gifUrl != null) {
      onGifSelected(gifUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.emoji_emotions_outlined),
            onPressed: onEmojiPressed,
            tooltip: 'Chọn Emoji',
          ),
          IconButton(
            icon: const Icon(Icons.gif_box_outlined),
            onPressed: () => _showGifPicker(context),
            tooltip: 'Chọn GIF',
          ),
          if (showImagePicker)
            IconButton(
              icon: const Icon(Icons.image_outlined),
              onPressed: _pickImage,
              tooltip: 'Chọn Ảnh',
            ),
        ],
      ),
    );
  }
}
