import 'package:flutter/material.dart';

class SimpleEmojiPicker extends StatelessWidget {
  final TextEditingController controller;

  const SimpleEmojiPicker({super.key, required this.controller});

  static const List<String> _emojis = [
    '😀',
    '😄',
    '😂',
    '😊',
    '😍',
    '😘',
    '😎',
    '😭',
    '😡',
    '👍',
    '👎',
    '👏',
    '🙏',
    '💪',
    '🔥',
    '✨',
    '❤️',
    '💔',
    '💕',
    '🎉',
    '💯',
    '🤔',
    '😅',
    '😆',
    '😋',
    '😴',
    '😱',
    '🥰',
    '😤',
    '👌',
    '🙌',
    '👀',
    '⭐',
    '🌟',
    '☀️',
    '🌙',
  ];

  void _insertEmoji(String emoji) {
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final newText = text.replaceRange(start, end, emoji);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _emojis.length,
      itemBuilder: (context, index) {
        final emoji = _emojis[index];
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _insertEmoji(emoji),
          child: Center(
            child: Text(emoji, style: const TextStyle(fontSize: 24)),
          ),
        );
      },
    );
  }
}
