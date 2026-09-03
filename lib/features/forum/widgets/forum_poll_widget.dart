import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/forum_poll.dart';
import '../services/firebase_forum_repository.dart';

class ForumPollWidget extends StatefulWidget {
  final String postId;
  final ForumPoll poll;

  const ForumPollWidget({
    super.key,
    required this.postId,
    required this.poll,
  });

  @override
  State<ForumPollWidget> createState() => _ForumPollWidgetState();
}

class _ForumPollWidgetState extends State<ForumPollWidget> {
  final _repository = FirebaseForumRepository();
  bool _isSubmitting = false;

  Future<void> _handleVote(int optionIndex) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để bình chọn')),
      );
      return;
    }

    if (widget.poll.voterUids.contains(user.uid)) {
      return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    try {
      await _repository.votePoll(
        postId: widget.postId,
        optionIndex: optionIndex,
        uid: user.uid,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi bình chọn: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final hasVoted = uid != null && widget.poll.voterUids.contains(uid);
    final userChoice = uid != null ? widget.poll.userVotes[uid] : null;
    final totalVotes = widget.poll.totalVotes;

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.purpleAccent.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.poll_rounded,
                  size: 16,
                  color: Colors.purpleAccent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.poll.question,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Options List
          ...List.generate(widget.poll.options.length, (index) {
            final optionText = widget.poll.options[index];
            final optVotes = widget.poll.votes[index.toString()] ?? 0;
            final pct = totalVotes > 0 ? (optVotes / totalVotes) : 0.0;
            final isUserChoice = userChoice == index;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: (hasVoted || _isSubmitting)
                      ? null
                      : () => _handleVote(index),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isUserChoice
                            ? Colors.purpleAccent
                            : Colors.white.withValues(alpha: 0.12),
                        width: isUserChoice ? 1.5 : 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Progress Fill Bar
                        if (hasVoted)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: AnimatedFractionallySizedBox(
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeOutCubic,
                                widthFactor: pct,
                                child: Container(
                                  color: isUserChoice
                                      ? Colors.purpleAccent.withValues(alpha: 0.35)
                                      : Colors.white.withValues(alpha: 0.15),
                                ),
                              ),
                            ),
                          ),

                        // Option Content Text
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              // Selection check / circle
                              Icon(
                                isUserChoice
                                    ? Icons.check_circle_rounded
                                    : (hasVoted
                                        ? Icons.radio_button_unchecked
                                        : Icons.touch_app_outlined),
                                size: 16,
                                color: isUserChoice
                                    ? Colors.purpleAccent
                                    : Colors.white54,
                              ),
                              const SizedBox(width: 8),

                              // Text
                              Expanded(
                                child: Text(
                                  optionText,
                                  style: TextStyle(
                                    color: isUserChoice
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.9),
                                    fontWeight: isUserChoice
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),

                              // Percent and count
                              if (hasVoted)
                                Text(
                                  '${(pct * 100).toStringAsFixed(0)}% ($optVotes)',
                                  style: TextStyle(
                                    color: isUserChoice
                                        ? Colors.purpleAccent
                                        : Colors.white60,
                                    fontSize: 12,
                                    fontWeight: isUserChoice
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 4),
          // Footer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '📊 $totalVotes lượt bình chọn',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),
              Text(
                hasVoted ? '✓ Đã bình chọn' : 'Chạm vào lựa chọn để bình chọn',
                style: TextStyle(
                  color: hasVoted ? Colors.purpleAccent : Colors.white38,
                  fontSize: 11,
                  fontWeight: hasVoted ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
