import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

class ForumComposer extends StatelessWidget {
  final VoidCallback onEmojiPressed;
  final ValueChanged<File> onImageSelected;
  final VoidCallback? onPollPressed;
  final bool showImagePicker;
  final bool enabled;

  const ForumComposer({
    super.key,
    required this.onEmojiPressed,
    required this.onImageSelected,
    this.onPollPressed,
    this.showImagePicker = true,
    this.enabled = true,
  });

  Future<void> _pickMedia() async {
    final pickerPlatform = ImagePickerPlatform.instance;
    if (pickerPlatform is ImagePickerAndroid) {
      pickerPlatform.useAndroidPhotoPicker = true;
    }
    final picker = ImagePicker();
    // pickImage kích hoạt Android Photo Picker (Tất cả ảnh / Albums) giống Messenger
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      onImageSelected(File(pickedFile.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.emoji_emotions_outlined),
          onPressed: enabled ? onEmojiPressed : null,
          tooltip: 'Chọn Emoji',
        ),
        if (showImagePicker)
          IconButton(
            icon: const Icon(Icons.image_outlined),
            onPressed: enabled ? _pickMedia : null,
            tooltip: 'Chọn Ảnh / GIF',
          ),
        if (onPollPressed != null)
          IconButton(
            icon: const Icon(Icons.poll_outlined),
            onPressed: enabled ? onPollPressed : null,
            tooltip: 'Thêm bình chọn',
          ),
      ],
    );
  }
}
