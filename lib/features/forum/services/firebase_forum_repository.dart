import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'forum_repository.dart';
import 'image_upload_service.dart';
import '../models/forum_post.dart';
import '../models/forum_comment.dart';
import '../models/forum_message.dart';
import '../models/forum_report.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../config/admin_config.dart';

class FirebaseForumRepository implements ForumRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<(List<ForumPost>, DocumentSnapshot?)> fetchDiscussionPosts({
    DocumentSnapshot? startAfter,
  }) async {
    Query query = _firestore
        .collection('forumPosts')
        .where('type', isEqualTo: 'discussion')
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(20);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();

    final posts = snapshot.docs
        .map((doc) => ForumPost.fromFirestore(doc))
        .toList();
    final lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;

    return (posts, lastDoc);
  }

  @override
  Future<(List<ForumPost>, DocumentSnapshot?)> fetchSharePosts({
    DocumentSnapshot? startAfter,
  }) async {
    Query query = _firestore
        .collection('forumPosts')
        .where('type', isEqualTo: 'manga_share')
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(20);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();

    final posts = snapshot.docs
        .map((doc) => ForumPost.fromFirestore(doc))
        .toList();
    final lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;

    return (posts, lastDoc);
  }

  @override
  Future<void> createDiscussionPost({
    required String uid,
    required String authorName,
    required String authorAvatar,
    required String body,
    String? gifUrl,
    File? imageFile,
  }) async {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty && gifUrl == null && imageFile == null) {
      throw Exception('Nội dung không được để trống.');
    }
    if (trimmedBody.length > 2000) {
      throw Exception('Nội dung quá dài (tối đa 2000 ký tự).');
    }

    final postRef = _firestore.collection('forumPosts').doc();
    String? uploadedImageUrl;

    if (imageFile != null) {
      uploadedImageUrl = await ImageUploadService.uploadForumImage(
        imageFile,
        uid,
        postRef.id,
      );
    }

    final post = ForumPost(
      id: postRef.id,
      type: 'discussion',
      authorId: uid,
      authorName: authorName,
      authorAvatar: authorAvatar,
      body: trimmedBody,
      gifUrl: gifUrl,
      imageUrl: uploadedImageUrl,
      createdAt: DateTime.now(), // Will be overwritten by server timestamp
      updatedAt: DateTime.now(), // Will be overwritten by server timestamp
    );

    await postRef.set(post.toFirestore());
  }

  @override
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
  }) async {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty && gifUrl == null) {
      throw Exception('Nội dung không được để trống.');
    }
    if (trimmedBody.length > 2000) {
      throw Exception('Nội dung quá dài (tối đa 2000 ký tự).');
    }

    final postRef = _firestore.collection('forumPosts').doc();

    final post = ForumPost(
      id: postRef.id,
      type: 'manga_share',
      authorId: uid,
      authorName: authorName,
      authorAvatar: authorAvatar,
      body: trimmedBody,
      gifUrl: gifUrl,
      sharedMangaId: sharedMangaId,
      sharedMangaTitle: sharedMangaTitle,
      sharedMangaCoverUrl: sharedMangaCoverUrl,
      sharedMangaAuthor: sharedMangaAuthor,
      createdAt: DateTime.now(), // Will be overwritten by server timestamp
      updatedAt: DateTime.now(), // Will be overwritten by server timestamp
    );

    await postRef.set(post.toFirestore());
  }

  @override
  Future<ForumPost?> fetchPost(String postId) async {
    final doc = await _firestore.collection('forumPosts').doc(postId).get();
    if (doc.exists) {
      final post = ForumPost.fromFirestore(doc);
      if (post.isDeleted) return null;
      return post;
    }
    return null;
  }

  @override
  Future<void> softDeletePost(String postId) async {
    await _firestore.collection('forumPosts').doc(postId).update({
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<List<ForumComment>> fetchComments(String postId) async {
    final snapshot = await _firestore
        .collection('forumPosts')
        .doc(postId)
        .collection('comments')
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: false)
        .limit(30)
        .get();

    return snapshot.docs.map((doc) => ForumComment.fromFirestore(doc)).toList();
  }

  @override
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
  }) async {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      throw Exception('Nội dung bình luận không được để trống.');
    }
    if (trimmedBody.length > 1000) {
      throw Exception('Bình luận quá dài (tối đa 1000 ký tự).');
    }

    final postRef = _firestore.collection('forumPosts').doc(postId);
    final commentRef = postRef.collection('comments').doc();

    final comment = ForumComment(
      id: commentRef.id,
      authorId: uid,
      authorName: authorName,
      authorAvatar: authorAvatar,
      body: trimmedBody,
      gifUrl: gifUrl,
      createdAt: DateTime.now(), // Overwritten by server timestamp
      updatedAt: DateTime.now(), // Overwritten by server timestamp
      replyToCommentId: replyToCommentId,
      replyToAuthorName: replyToAuthorName,
      replyToUserId: replyToUserId,
    );

    final postSnapshot = await postRef.get();
    if (!postSnapshot.exists) return;
    final postData = postSnapshot.data() as Map<String, dynamic>;
    if (postData['isDeleted'] == true) {
      throw Exception('Không thể bình luận. Bài viết này đã bị xóa.');
    }

    final postAuthorId = postData['authorId'] as String;
    final postBody = postData['body'] as String? ?? '';
    final sharedMangaTitle = postData['sharedMangaTitle'] as String?;

    String preview = postBody.isNotEmpty
        ? postBody
        : (sharedMangaTitle ?? 'Bài viết');
    if (preview.length > 50) preview = '${preview.substring(0, 50)}...';

    await _firestore.runTransaction((transaction) async {
      transaction.set(commentRef, comment.toFirestore());
      transaction.update(postRef, {'commentCount': FieldValue.increment(1)});
    });

    if (replyToUserId != null && replyToCommentId != null) {
      await _createForumNotification(
        type: 'forum_reply',
        recipientId: replyToUserId,
        actorId: uid,
        actorName: authorName,
        actorAvatar: authorAvatar,
        postId: postId,
        commentId: commentRef.id,
        replyToCommentId: replyToCommentId,
        postPreview: preview,
      );
    } else {
      await _createForumNotification(
        type: 'forum_comment',
        recipientId: postAuthorId,
        actorId: uid,
        actorName: authorName,
        actorAvatar: authorAvatar,
        postId: postId,
        commentId: commentRef.id,
        postPreview: preview,
      );
    }
  }

  @override
  Future<void> softDeleteComment(String postId, String commentId) async {
    final postRef = _firestore.collection('forumPosts').doc(postId);
    final commentRef = postRef.collection('comments').doc(commentId);

    await _firestore.runTransaction((transaction) async {
      final commentSnapshot = await transaction.get(commentRef);
      if (!commentSnapshot.exists) return;
      final data = commentSnapshot.data();
      if (data != null && data['isDeleted'] == true) return;

      transaction.update(commentRef, {
        'isDeleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(postRef, {'commentCount': FieldValue.increment(-1)});
    });
  }

  @override
  Future<void> toggleLikePost(String postId, String uid) async {
    final postRef = _firestore.collection('forumPosts').doc(postId);
    final reactionRef = postRef.collection('reactions').doc(uid);

    final postSnapshot = await postRef.get();
    if (!postSnapshot.exists) return;
    final postData = postSnapshot.data() as Map<String, dynamic>;
    if (postData['isDeleted'] == true) {
      throw Exception('Không thể thích. Bài viết này đã bị xóa.');
    }
    final postAuthorId = postData['authorId'] as String;
    final postBody = postData['body'] as String? ?? '';
    final sharedMangaTitle = postData['sharedMangaTitle'] as String?;

    String preview = postBody.isNotEmpty
        ? postBody
        : (sharedMangaTitle ?? 'Bài viết');
    if (preview.length > 50) preview = '${preview.substring(0, 50)}...';

    bool isNewLike = false;

    await _firestore.runTransaction((transaction) async {
      final reactionSnapshot = await transaction.get(reactionRef);
      if (reactionSnapshot.exists) {
        transaction.delete(reactionRef);
        transaction.update(postRef, {'likeCount': FieldValue.increment(-1)});
      } else {
        transaction.set(reactionRef, {
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(postRef, {'likeCount': FieldValue.increment(1)});
        isNewLike = true;
      }
    });

    if (isNewLike && postAuthorId != uid) {
      final userSnapshot = await _firestore.collection('users').doc(uid).get();
      if (userSnapshot.exists) {
        final userData = userSnapshot.data()!;
        final actorName = userData['name'] as String? ?? 'Người dùng';
        final actorAvatar = userData['avatarUrl'] as String? ?? '';

        await _createForumNotification(
          type: 'forum_like',
          recipientId: postAuthorId,
          actorId: uid,
          actorName: actorName,
          actorAvatar: actorAvatar,
          postId: postId,
          postPreview: preview,
        );
      }
    }
  }

  @override
  Future<void> toggleLikeComment(
    String postId,
    String commentId,
    String uid,
  ) async {
    final postRef = _firestore.collection('forumPosts').doc(postId);
    final commentRef = postRef.collection('comments').doc(commentId);
    final reactionRef = commentRef.collection('reactions').doc(uid);

    await _firestore.runTransaction((transaction) async {
      final postSnapshot = await transaction.get(postRef);
      if (!postSnapshot.exists || (postSnapshot.data()?['isDeleted'] == true)) {
        return;
      }
      final commentSnapshot = await transaction.get(commentRef);
      if (!commentSnapshot.exists ||
          (commentSnapshot.data()?['isDeleted'] == true)) {
        return;
      }

      final reactionSnapshot = await transaction.get(reactionRef);
      if (reactionSnapshot.exists) {
        transaction.delete(reactionRef);
        transaction.update(commentRef, {'likeCount': FieldValue.increment(-1)});
      } else {
        transaction.set(reactionRef, {
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(commentRef, {'likeCount': FieldValue.increment(1)});
      }
    });
  }

  @override
  Stream<bool> hasLikedPost(String postId, String uid) {
    return _firestore
        .collection('forumPosts')
        .doc(postId)
        .collection('reactions')
        .doc(uid)
        .snapshots()
        .map((snap) => snap.exists);
  }

  @override
  Stream<bool> hasLikedComment(String postId, String commentId, String uid) {
    return _firestore
        .collection('forumPosts')
        .doc(postId)
        .collection('comments')
        .doc(commentId)
        .collection('reactions')
        .doc(uid)
        .snapshots()
        .map((snap) => snap.exists);
  }

  @override
  Future<void> incrementViewCount(String postId) async {
    final postRef = _firestore.collection('forumPosts').doc(postId);
    await postRef.update({'viewCount': FieldValue.increment(1)});
  }

  @override
  Future<void> reportContent({
    required String reporterId,
    required String targetType,
    required String targetId,
    required String postId,
    required String reason,
  }) async {
    final reportId = '${reporterId}_${targetType}_$targetId';
    final reportRef = _firestore.collection('forumReports').doc(reportId);
    await reportRef.set({
      'id': reportRef.id,
      'reporterId': reporterId,
      'targetType': targetType,
      'targetId': targetId,
      'postId': postId,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }

  @override
  Future<(List<ForumReport>, DocumentSnapshot?)> fetchPendingReports({
    DocumentSnapshot? startAfter,
    int limit = 20,
  }) async {
    var query = _firestore
        .collection('forumReports')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();
    final reports = snapshot.docs.map((doc) => ForumReport.fromFirestore(doc)).toList();

    return (
      reports,
      snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
    );
  }

  @override
  Future<void> resolveReport({
    required String reportId,
    required String action,
    required String resolvedBy,
  }) async {
    final reportRef = _firestore.collection('forumReports').doc(reportId);
    await reportRef.update({
      'status': action == 'dismissed' ? 'dismissed' : 'resolved',
      'action': action,
      'resolvedBy': resolvedBy,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Stream<List<ForumMessage>> streamLatestMessages() {
    return _firestore
        .collection('forumMessages')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ForumMessage.fromFirestore(doc))
              .toList(),
        );
  }

  @override
  Future<List<ForumMessage>> loadOlderMessages({
    required DocumentSnapshot startAfter,
  }) async {
    final snapshot = await _firestore
        .collection('forumMessages')
        .orderBy('createdAt', descending: true)
        .startAfterDocument(startAfter)
        .limit(50)
        .get();

    return snapshot.docs.map((doc) => ForumMessage.fromFirestore(doc)).toList();
  }

  @override
  Future<void> sendMessage({
    required String uid,
    required String authorName,
    required String authorAvatar,
    required String body,
    String? gifUrl,
  }) async {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty && gifUrl == null) {
      throw Exception('Nội dung tin nhắn không được để trống.');
    }
    if (trimmedBody.length > 1000) {
      throw Exception('Tin nhắn quá dài (tối đa 1000 ký tự).');
    }

    final messageRef = _firestore.collection('forumMessages').doc();
    final message = ForumMessage(
      id: messageRef.id,
      authorId: uid,
      authorName: authorName,
      authorAvatar: authorAvatar,
      body: trimmedBody,
      gifUrl: gifUrl,
      authorIsAdmin: AdminConfig.isAdmin(FirebaseAuth.instance.currentUser?.email),
      createdAt: DateTime.now(), // Overwritten by server timestamp
    );

    await messageRef.set(message.toFirestore());
  }

  Future<void> _createForumNotification({
    required String type,
    required String recipientId,
    required String actorId,
    required String actorName,
    required String actorAvatar,
    required String postId,
    String? commentId,
    String? replyToCommentId,
    required String postPreview,
  }) async {
    if (recipientId == actorId) return;

    final docId = type == 'forum_like'
        ? 'post_like_${postId}_${actorId}_${DateTime.now().millisecondsSinceEpoch}'
        : type == 'forum_reply'
        ? 'post_reply_${postId}_$commentId'
        : 'post_comment_${postId}_$commentId';

    String title = '';
    String body = postPreview;

    if (type == 'forum_like') {
      title = '$actorName đã thích bài viết của bạn';
    } else if (type == 'forum_reply') {
      title = '$actorName đã phản hồi bình luận của bạn';
    } else {
      title = '$actorName đã bình luận bài viết của bạn';
    }

    final data = {
      'type': type,
      'recipientId': recipientId,
      'actorId': actorId,
      'actorName': actorName,
      'actorAvatar': actorAvatar,
      'postId': postId,
      if (commentId != null) 'commentId': commentId,
      if (replyToCommentId != null) 'replyToCommentId': replyToCommentId,
      'postPreview': postPreview,
      'title': title,
      'body': body,
      'route': '/forum/detail/$postId',
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
    };

    try {
      await _firestore
          .collection('users')
          .doc(recipientId)
          .collection('forum_notifications')
          .doc(docId)
          .set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Lỗi tạo thông báo diễn đàn: $e');
    }
  }

  @override
  Future<void> softDeleteMessage(String messageId) async {
    await _firestore.collection('forumMessages').doc(messageId).update({
      'isDeleted': true,
    });
  }

  @override
  Future<void> muteForumUser({
    required String userId,
    required Duration duration,
    required String reason,
  }) async {
    final mutedUntil = DateTime.now().add(duration);
    await _firestore.collection('users').doc(userId).update({
      'mutedUntil': Timestamp.fromDate(mutedUntil),
      'mutedReason': reason,
      'mutedBy': FirebaseAuth.instance.currentUser?.uid,
      'moderationUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> unmuteForumUser(String userId) async {
    await _firestore.collection('users').doc(userId).update({
      'mutedUntil': FieldValue.delete(),
      'mutedReason': FieldValue.delete(),
      'mutedBy': FieldValue.delete(),
      'moderationUpdatedAt': FieldValue.serverTimestamp(),
    });
  }
}
