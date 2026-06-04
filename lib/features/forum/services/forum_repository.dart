import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:manga_reader/features/forum/models/forum_post.dart';
import 'package:manga_reader/features/forum/models/forum_comment.dart';
import '../models/forum_message.dart';
import '../models/forum_report.dart';

abstract class ForumRepository {
  Future<(List<ForumPost>, DocumentSnapshot?)> fetchDiscussionPosts({
    DocumentSnapshot? startAfter,
  });
  Future<(List<ForumPost>, DocumentSnapshot?)> fetchSharePosts({
    DocumentSnapshot? startAfter,
  });

  Future<void> createDiscussionPost({
    required String uid,
    required String authorName,
    required String authorAvatar,
    required String body,
    String? gifUrl,
    File? imageFile,
  });

  Future<void> createSharePost({
    required String uid,
    required String authorName,
    required String authorAvatar,
    required String body,
    required String sharedMangaId,
    required String sharedMangaTitle,
    required String sharedMangaCoverUrl,
    String? sharedMangaAuthor,
    String? gifUrl,
  });

  Future<ForumPost?> fetchPost(String postId);
  Future<void> softDeletePost(String postId);

  Future<List<ForumComment>> fetchComments(String postId);
  Future<void> createComment({
    required String postId,
    required String uid,
    required String authorName,
    required String authorAvatar,
    required String body,
    String? gifUrl,
    String? replyToCommentId,
    String? replyToAuthorName,
    String? replyToUserId,
  });
  Future<void> softDeleteComment(String postId, String commentId);

  // Like
  Future<void> toggleLikePost(String postId, String uid);
  Future<void> toggleLikeComment(String postId, String commentId, String uid);
  Stream<bool> hasLikedPost(String postId, String uid);
  Stream<bool> hasLikedComment(String postId, String commentId, String uid);

  // View
  Future<void> incrementViewCount(String postId);

  // Report
  Future<void> reportContent({
    required String reporterId,
    required String targetType, // 'post', 'comment', 'message'
    required String targetId,
    required String postId,
    required String reason,
  });

  Future<(List<ForumReport>, DocumentSnapshot?)> fetchPendingReports({
    DocumentSnapshot? startAfter,
    int limit = 20,
  });

  Future<void> resolveReport({
    required String reportId,
    required String action, // 'dismissed', 'resolved'
    required String resolvedBy,
  });

  // Chat
  Stream<List<ForumMessage>> streamLatestMessages();
  Future<List<ForumMessage>> loadOlderMessages({
    required DocumentSnapshot startAfter,
  });
  Future<void> sendMessage({
    required String uid,
    required String authorName,
    required String authorAvatar,
    required String body,
    String? gifUrl,
    File? imageFile,
    String? replyToMessageId,
    String? replyToAuthorName,
    String? replyToBody,
  });

  // Moderation
  Future<void> softDeleteMessage(String messageId);
  Future<void> muteForumUser({
    required String userId,
    required Duration duration,
    required String reason,
  });
  Future<void> unmuteForumUser(String userId);
}
