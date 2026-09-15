import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
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
import '../../../services/achievement_service.dart';
import '../../../services/level_service.dart';

import '../models/forum_poll.dart';

class FirebaseForumRepository implements ForumRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<(String, String, int)> _getCustomProfile(String uid, String defaultName, String defaultAvatar) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        final displayName = (data['displayName']?.toString() ?? '').trim();
        final name = (data['name']?.toString() ?? '').trim();
        final finalName = displayName.isNotEmpty ? displayName : name;
        final rawAvatar = (data['avatarUrl']?.toString() ?? data['avatar']?.toString() ?? '').trim();
        final safeAvatar = (rawAvatar.isNotEmpty && rawAvatar.length <= 2000 && !rawAvatar.startsWith('data:'))
            ? rawAvatar
            : (defaultAvatar.length <= 2000 && !defaultAvatar.startsWith('data:') ? defaultAvatar : '');
        final exp = (data['exp'] as num?)?.toInt() ?? 0;
        final level = (data['level'] as num?)?.toInt() ?? LevelService.getLevelInfo(exp).level;
        return (
          finalName.isNotEmpty ? finalName : defaultName,
          safeAvatar,
          level > 0 ? level : 1,
        );
      }
    } catch (e) {
      debugPrint('Error getting custom profile: $e');
    }
    final safeDefault = (defaultAvatar.length <= 2000 && !defaultAvatar.startsWith('data:')) ? defaultAvatar : '';
    return (defaultName, safeDefault, 1);
  }

  @override
  Future<(List<ForumPost>, DocumentSnapshot?)> fetchDiscussionPosts({
    DocumentSnapshot? startAfter,
    String? tag,
    String sortBy = 'latest',
  }) async {
    final cleanTag = (tag != null && tag.trim().isNotEmpty)
        ? tag.trim().toLowerCase().replaceAll('#', '')
        : null;

    QuerySnapshot snapshot;
    bool isFallback = false;

    try {
      Query query = _firestore
          .collection('forumPosts')
          .where('type', isEqualTo: 'discussion')
          .where('isDeleted', isEqualTo: false);

      if (cleanTag != null) {
        query = query.where('tags', arrayContains: cleanTag);
      }

      String orderField = 'createdAt';
      if (sortBy == 'hot') {
        orderField = 'likeCount';
      } else if (sortBy == 'comments') {
        orderField = 'commentCount';
      }

      query = query.orderBy(orderField, descending: true).limit(cleanTag != null ? 50 : 20);
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      snapshot = await query.get();
    } catch (e) {
      debugPrint('⚠️ Native query failed ($e), falling back to basic indexed query with in-memory filter');
      isFallback = true;
      Query fallbackQuery = _firestore
          .collection('forumPosts')
          .where('type', isEqualTo: 'discussion')
          .where('isDeleted', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(cleanTag != null ? 50 : 20);

      if (startAfter != null) {
        try {
          fallbackQuery = fallbackQuery.startAfterDocument(startAfter);
        } catch (_) {}
      }
      snapshot = await fallbackQuery.get();
    }

    var posts = snapshot.docs
        .map((doc) => ForumPost.fromFirestore(doc))
        .toList();

    // Nếu chạy chế độ fallback, lọc tag trực tiếp trên danh sách
    if (isFallback && cleanTag != null) {
      posts = posts.where((p) => p.tags.map((t) => t.toLowerCase()).contains(cleanTag)).toList();
    }

    // Sắp xếp bài ghim lên đầu tiên, các bài sau theo sortBy
    posts.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      if (sortBy == 'hot') {
        final cmp = b.likeCount.compareTo(a.likeCount);
        if (cmp != 0) return cmp;
      } else if (sortBy == 'comments') {
        final cmp = b.commentCount.compareTo(a.commentCount);
        if (cmp != 0) return cmp;
      }
      return b.createdAt.compareTo(a.createdAt);
    });

    // Khi fallback + có tag filter: lastDoc phải khớp với post cuối TRONG danh sách đã lọc
    // để phân trang tiếp theo không bị sai cursor.
    DocumentSnapshot? lastDoc;
    if (isFallback && cleanTag != null && posts.isNotEmpty) {
      final lastPostId = posts.last.id;
      lastDoc = snapshot.docs.firstWhereOrNull((d) => d.id == lastPostId);
    } else {
      lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
    }

    return (posts, lastDoc);
  }

  @override
  Future<(List<ForumPost>, DocumentSnapshot?)> fetchSharePosts({
    DocumentSnapshot? startAfter,
    String? tag,
    String sortBy = 'latest',
  }) async {
    final cleanTag = (tag != null && tag.trim().isNotEmpty)
        ? tag.trim().toLowerCase().replaceAll('#', '')
        : null;

    QuerySnapshot snapshot;
    bool isFallback = false;

    try {
      Query query = _firestore
          .collection('forumPosts')
          .where('type', isEqualTo: 'manga_share')
          .where('isDeleted', isEqualTo: false);

      if (cleanTag != null) {
        query = query.where('tags', arrayContains: cleanTag);
      }

      String orderField = 'createdAt';
      if (sortBy == 'hot') {
        orderField = 'likeCount';
      } else if (sortBy == 'comments') {
        orderField = 'commentCount';
      }

      query = query.orderBy(orderField, descending: true).limit(cleanTag != null ? 50 : 20);
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      snapshot = await query.get();
    } catch (e) {
      debugPrint('⚠️ Native query failed ($e), falling back to basic indexed query with in-memory filter');
      isFallback = true;
      Query fallbackQuery = _firestore
          .collection('forumPosts')
          .where('type', isEqualTo: 'manga_share')
          .where('isDeleted', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(cleanTag != null ? 50 : 20);

      if (startAfter != null) {
        try {
          fallbackQuery = fallbackQuery.startAfterDocument(startAfter);
        } catch (_) {}
      }
      snapshot = await fallbackQuery.get();
    }

    var posts = snapshot.docs
        .map((doc) => ForumPost.fromFirestore(doc))
        .toList();

    // Nếu chạy chế độ fallback, lọc tag trực tiếp trên danh sách
    if (isFallback && cleanTag != null) {
      posts = posts.where((p) => p.tags.map((t) => t.toLowerCase()).contains(cleanTag)).toList();
    }

    // Sắp xếp bài ghim lên đầu tiên, các bài sau theo sortBy
    posts.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      if (sortBy == 'hot') {
        final cmp = b.likeCount.compareTo(a.likeCount);
        if (cmp != 0) return cmp;
      } else if (sortBy == 'comments') {
        final cmp = b.commentCount.compareTo(a.commentCount);
        if (cmp != 0) return cmp;
      }
      return b.createdAt.compareTo(a.createdAt);
    });

    // Khi fallback + có tag filter: lastDoc phải khớp với post cuối TRONG danh sách đã lọc
    // để phân trang tiếp theo không bị sai cursor.
    DocumentSnapshot? lastDoc;
    if (isFallback && cleanTag != null && posts.isNotEmpty) {
      final lastPostId = posts.last.id;
      lastDoc = snapshot.docs.firstWhereOrNull((d) => d.id == lastPostId);
    } else {
      lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
    }

    return (posts, lastDoc);
  }

  @override
  Future<List<String>> fetchExistingTags({required String type}) async {
    try {
      final snapshot = await _firestore
          .collection('forumPosts')
          .where('type', isEqualTo: type)
          .where('isDeleted', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();

      final tagsSet = <String>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final rawTags = data['tags'];
        if (rawTags is List) {
          for (final t in rawTags) {
            final clean = t.toString().trim().toLowerCase().replaceAll('#', '');
            if (clean.isNotEmpty) {
              tagsSet.add(clean);
            }
          }
        }
      }
      return tagsSet.toList()..sort();
    } catch (e) {
      debugPrint('Error fetching existing forum tags: $e');
      return [];
    }
  }

  @override
  Future<void> createDiscussionPost({
    required String uid,
    required String authorName,
    required String authorAvatar,
    required String body,
    String? gifUrl,
    File? imageFile,
    ForumPoll? poll,
    List<String>? tags,
  }) async {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty && gifUrl == null && imageFile == null && poll == null) {
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

    final (finalName, finalAvatar, finalLevel) = await _getCustomProfile(uid, authorName, authorAvatar);

    final combinedTags = <String>{
      ...ForumPost.extractHashtags(trimmedBody),
      if (tags != null)
        ...tags.map((e) => e.toLowerCase().trim().replaceAll('#', '')),
    }.where((e) => e.isNotEmpty).toList();

    final post = ForumPost(
      id: postRef.id,
      type: 'discussion',
      authorId: uid,
      authorName: finalName,
      authorAvatar: finalAvatar,
      authorLevel: finalLevel,
      body: trimmedBody,
      gifUrl: gifUrl,
      imageUrl: uploadedImageUrl,
      poll: poll,
      tags: combinedTags,
      createdAt: DateTime.now(), // Will be overwritten by server timestamp
      updatedAt: DateTime.now(), // Will be overwritten by server timestamp
    );

    await postRef.set(post.toFirestore());
    unawaited(AchievementService.instance.recordCommunityAction());
  }

  @override
  Future<void> votePoll({
    required String postId,
    required int optionIndex,
    required String uid,
  }) async {
    final postRef = _firestore.collection('forumPosts').doc(postId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(postRef);
      if (!snapshot.exists) throw Exception('Bài viết không tồn tại');

      final data = snapshot.data() ?? {};
      final pollData = data['poll'] as Map<String, dynamic>?;
      if (pollData == null) throw Exception('Bài viết không có bình chọn');

      final voterUids = List<String>.from(pollData['voterUids'] ?? []);
      if (voterUids.contains(uid)) {
        throw Exception('Bạn đã tham gia bình chọn bài viết này rồi');
      }

      final votes = Map<String, int>.from(
        (pollData['votes'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, (v as num).toInt()),
            ) ??
            {},
      );

      final userVotes = Map<String, int>.from(
        (pollData['userVotes'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, (v as num).toInt()),
            ) ??
            {},
      );

      final optKey = optionIndex.toString();
      votes[optKey] = (votes[optKey] ?? 0) + 1;
      voterUids.add(uid);
      userVotes[uid] = optionIndex;

      transaction.update(postRef, {
        'poll.votes': votes,
        'poll.voterUids': voterUids,
        'poll.userVotes': userVotes,
      });
    });
    unawaited(AchievementService.instance.recordCommunityAction());
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
    List<String>? tags,
  }) async {
    final trimmedBody = body.trim();
    if (sharedMangaId.trim().isEmpty ||
        sharedMangaTitle.trim().isEmpty ||
        sharedMangaCoverUrl.trim().isEmpty) {
      throw Exception('Thiếu thông tin truyện để chia sẻ.');
    }
    if (trimmedBody.length > 2000) {
      throw Exception('Nội dung quá dài (tối đa 2000 ký tự).');
    }

    final postRef = _firestore.collection('forumPosts').doc();

    final (finalName, finalAvatar, finalLevel) = await _getCustomProfile(uid, authorName, authorAvatar);

    final combinedTags = <String>{
      ...ForumPost.extractHashtags(trimmedBody),
      if (tags != null)
        ...tags.map((e) => e.toLowerCase().trim().replaceAll('#', '')),
    }.where((e) => e.isNotEmpty).toList();

    final post = ForumPost(
      id: postRef.id,
      type: 'manga_share',
      authorId: uid,
      authorName: finalName,
      authorAvatar: finalAvatar,
      authorLevel: finalLevel,
      body: trimmedBody,
      gifUrl: gifUrl,
      sharedMangaId: sharedMangaId,
      sharedMangaTitle: sharedMangaTitle,
      sharedMangaCoverUrl: sharedMangaCoverUrl,
      sharedMangaAuthor: sharedMangaAuthor,
      tags: combinedTags,
      createdAt: DateTime.now(), // Will be overwritten by server timestamp
      updatedAt: DateTime.now(), // Will be overwritten by server timestamp
    );

    await postRef.set(post.toFirestore());
    unawaited(AchievementService.instance.recordCommunityAction());
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
        .limit(150)
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

    final (finalName, finalAvatar, finalLevel) = await _getCustomProfile(uid, authorName, authorAvatar);

    final comment = ForumComment(
      id: commentRef.id,
      authorId: uid,
      authorName: finalName,
      authorAvatar: finalAvatar,
      authorLevel: finalLevel,
      body: trimmedBody,
      gifUrl: gifUrl,
      createdAt: DateTime.now(), // Overwritten by server timestamp
      updatedAt: DateTime.now(), // Overwritten by server timestamp
      replyToCommentId: replyToCommentId,
      replyToAuthorName: replyToAuthorName,
      replyToUserId: replyToUserId,
    );

    String postAuthorId = '';
    String preview = '';

    await _firestore.runTransaction((transaction) async {
      final postSnapshot = await transaction.get(postRef);
      if (!postSnapshot.exists) {
        throw Exception('Bài viết không tồn tại.');
      }
      final postData = postSnapshot.data() as Map<String, dynamic>;
      if (postData['isDeleted'] == true) {
        throw Exception('Không thể bình luận. Bài viết này đã bị xóa.');
      }

      postAuthorId = postData['authorId']?.toString() ?? '';
      final postBody = postData['body'] as String? ?? '';
      final sharedMangaTitle = postData['sharedMangaTitle'] as String?;

      preview = postBody.isNotEmpty
          ? postBody
          : (sharedMangaTitle ?? 'Bài viết');
      if (preview.length > 50) preview = '${preview.substring(0, 50)}...';

      transaction.set(commentRef, comment.toFirestore());
      transaction.update(postRef, {'commentCount': FieldValue.increment(1)});
    });

    if (replyToUserId != null && replyToCommentId != null) {
      await _createForumNotification(
        type: 'forum_reply',
        recipientId: replyToUserId,
        actorId: uid,
        actorName: finalName,
        actorAvatar: finalAvatar,
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
        actorName: finalName,
        actorAvatar: finalAvatar,
        postId: postId,
        commentId: commentRef.id,
        postPreview: preview,
      );
    }
    unawaited(AchievementService.instance.recordCommunityAction());
  }

  @override
  Future<void> softDeleteComment(String postId, String commentId) async {
    final postRef = _firestore.collection('forumPosts').doc(postId);
    final commentRef = postRef.collection('comments').doc(commentId);

    await _firestore.runTransaction((transaction) async {
      final commentSnapshot = await transaction.get(commentRef);
      if (!commentSnapshot.exists ||
          commentSnapshot.data()?['isDeleted'] == true) {
        return;
      }

      final postSnapshot = await transaction.get(postRef);
      transaction.update(commentRef, {
        'isDeleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (postSnapshot.exists && postSnapshot.data()?['isDeleted'] != true) {
        final count =
            (postSnapshot.data()?['commentCount'] as num?)?.toInt() ?? 0;
        if (count > 0) {
          transaction.update(postRef, {'commentCount': count - 1});
        }
      }
    });
  }

  @override
  Future<void> toggleLikePost(String postId, String uid) async {
    final postRef = _firestore.collection('forumPosts').doc(postId);
    final reactionRef = postRef.collection('reactions').doc(uid);

    bool isNewLike = false;
    String postAuthorId = '';
    String preview = '';

    await _firestore.runTransaction((transaction) async {
      final postSnapshot = await transaction.get(postRef);
      if (!postSnapshot.exists) return;
      final postData = postSnapshot.data() as Map<String, dynamic>;
      if (postData['isDeleted'] == true) {
        throw Exception('Không thể thích. Bài viết này đã bị xóa.');
      }
      postAuthorId = postData['authorId']?.toString() ?? '';
      final postBody = postData['body'] as String? ?? '';
      final sharedMangaTitle = postData['sharedMangaTitle'] as String?;

      preview = postBody.isNotEmpty
          ? postBody
          : (sharedMangaTitle ?? 'Bài viết');
      if (preview.length > 50) preview = '${preview.substring(0, 50)}...';

      final reactionSnapshot = await transaction.get(reactionRef);
      if (reactionSnapshot.exists) {
        transaction.delete(reactionRef);
        final currentLikes = (postData['likeCount'] as num?)?.toInt() ?? 0;
        if (currentLikes > 0) {
          transaction.update(postRef, {'likeCount': currentLikes - 1});
        }
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

    bool isNewLike = false;
    String commentAuthorId = '';
    String preview = '';

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

      final commentData = commentSnapshot.data() as Map<String, dynamic>;
      commentAuthorId = commentData['authorId'] as String? ?? '';
      final commentBody = commentData['body'] as String? ?? '';
      preview = commentBody.isNotEmpty ? commentBody : 'Bình luận';
      if (preview.length > 50) preview = '${preview.substring(0, 50)}...';

      final reactionSnapshot = await transaction.get(reactionRef);
      if (reactionSnapshot.exists) {
        transaction.delete(reactionRef);
        final currentLikes = (commentData['likeCount'] as num?)?.toInt() ?? 0;
        if (currentLikes > 0) {
          transaction.update(commentRef, {'likeCount': currentLikes - 1});
        }
      } else {
        transaction.set(reactionRef, {
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(commentRef, {'likeCount': FieldValue.increment(1)});
        isNewLike = true;
      }
    });

    if (isNewLike && commentAuthorId.isNotEmpty && commentAuthorId != uid) {
      final userSnapshot = await _firestore.collection('users').doc(uid).get();
      if (userSnapshot.exists) {
        final userData = userSnapshot.data()!;
        final actorName = (userData['displayName']?.toString() ??
                userData['name']?.toString() ??
                'Người dùng')
            .trim();
        final actorAvatar = (userData['avatarUrl']?.toString() ??
                userData['avatar']?.toString() ??
                '')
            .trim();

        await _createForumNotification(
          type: 'forum_comment_like',
          recipientId: commentAuthorId,
          actorId: uid,
          actorName: actorName.isNotEmpty ? actorName : 'Người dùng',
          actorAvatar: actorAvatar,
          postId: postId,
          commentId: commentId,
          postPreview: preview,
        );
      }
    }
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
    final reports = snapshot.docs
        .map((doc) => ForumReport.fromFirestore(doc))
        .toList();

    return (reports, snapshot.docs.isNotEmpty ? snapshot.docs.last : null);
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
    File? imageFile,
    String? replyToMessageId,
    String? replyToUserId,
    String? replyToAuthorName,
    String? replyToBody,
  }) async {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty && gifUrl == null && imageFile == null) {
      throw Exception('Nội dung tin nhắn không được để trống.');
    }
    if (trimmedBody.length > 1000) {
      throw Exception('Tin nhắn quá dài (tối đa 1000 ký tự).');
    }

    String? imageUrl;
    if (imageFile != null) {
      imageUrl = await ImageUploadService.uploadChatImage(imageFile, uid);
    }

    final messageRef = _firestore.collection('forumMessages').doc();
    
    final (finalName, finalAvatar, _) = await _getCustomProfile(uid, authorName, authorAvatar);

    final message = ForumMessage(
      id: messageRef.id,
      authorId: uid,
      authorName: finalName,
      authorAvatar: finalAvatar,
      body: trimmedBody,
      gifUrl: gifUrl,
      imageUrl: imageUrl,
      createdAt: DateTime.now(), // Overwritten by server timestamp
      authorIsAdmin: AdminConfig.isAdmin(
        FirebaseAuth.instance.currentUser?.email,
      ),
      replyToMessageId: replyToMessageId,
      replyToAuthorName: replyToAuthorName,
      replyToBody: replyToBody,
    );

    await messageRef.set(message.toFirestore());

    // 1. Thông báo cho người được trả lời (Reply)
    if (replyToUserId != null && replyToUserId != uid) {
      await _createForumNotification(
        type: 'forum_chat_reply',
        recipientId: replyToUserId,
        actorId: uid,
        actorName: finalName,
        actorAvatar: finalAvatar,
        postId: '',
        postPreview: trimmedBody.isNotEmpty ? trimmedBody : 'Hình ảnh/GIF',
      );
    }

    // 2. Thông báo cho người được tag (@Mention)
    if (trimmedBody.contains('@')) {
      final mentionedCandidates = <String>{};

      // Ưu tiên khớp dạng @[Tên đầy đủ có dấu cách]
      final bracketMatches = RegExp(r'@\[([^\]]+)\]').allMatches(trimmedBody);
      for (final m in bracketMatches) {
        final val = m.group(1)?.trim();
        if (val != null && val.isNotEmpty) mentionedCandidates.add(val);
      }

      // Khớp dạng @Tên (chỉ lấy 1 từ đơn hoặc 2 từ liền kề tối đa)
      final rawAtMatches = RegExp(r'@([a-zA-Z0-9_\u00C0-\u024F\u1E00-\u1EFF]+(?:\s+[a-zA-Z0-9_\u00C0-\u024F\u1E00-\u1EFF]+)?)').allMatches(trimmedBody);
      for (final m in rawAtMatches) {
        final phrase = m.group(1)?.trim();
        if (phrase != null && phrase.isNotEmpty) {
          mentionedCandidates.add(phrase);
        }
      }

      final notifiedUids = <String>{};
      for (final name in mentionedCandidates.take(3)) {
        try {
          String? targetUid = _userMentionCache[name];
          if (targetUid == null && !_userMentionCache.containsKey(name)) {
            var userQuery = await _firestore
                .collection('users')
                .where('name', isEqualTo: name)
                .limit(1)
                .get();
            if (userQuery.docs.isEmpty) {
              userQuery = await _firestore
                  .collection('users')
                  .where('displayName', isEqualTo: name)
                  .limit(1)
                  .get();
            }
            if (userQuery.docs.isNotEmpty) {
              targetUid = userQuery.docs.first.id;
              _addToMentionCache(name, targetUid);
            } else {
              _addToMentionCache(name, null); // Cache không tồn tại để tránh query lại
            }
          }

          if (targetUid != null &&
              targetUid != uid &&
              targetUid != replyToUserId &&
              !notifiedUids.contains(targetUid)) {
            notifiedUids.add(targetUid);
            await _createForumNotification(
              type: 'forum_chat_mention',
              recipientId: targetUid,
              actorId: uid,
              actorName: finalName,
              actorAvatar: finalAvatar,
              postId: '',
              postPreview: trimmedBody,
            );
          }
        } catch (e) {
          debugPrint('Error sending mention notification: $e');
        }
      }
    }
  }

  static final Map<String, String?> _userMentionCache = {};
  static const int _mentionCacheMaxSize = 500;

  static void _addToMentionCache(String name, String? uid) {
    if (_userMentionCache.length >= _mentionCacheMaxSize) {
      // Evict oldest half to keep memory bounded
      final keysToRemove = _userMentionCache.keys.take(_mentionCacheMaxSize ~/ 2).toList();
      for (final k in keysToRemove) {
        _userMentionCache.remove(k);
      }
    }
    _userMentionCache[name] = uid;
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
        ? 'post_like_${postId}_$actorId'
        : type == 'forum_comment_like'
        ? 'comment_like_${postId}_${commentId}_$actorId'
        : type == 'forum_reply'
        ? 'post_reply_${postId}_$commentId'
        : (type == 'forum_chat_reply' || type == 'forum_chat_mention')
        ? 'chat_${type}_${DateTime.now().millisecondsSinceEpoch}_$actorId'
        : 'post_comment_${postId}_$commentId';

    String title = '';
    String body = postPreview;

    if (type == 'forum_like') {
      title = '$actorName đã thích bài viết của bạn';
    } else if (type == 'forum_comment_like') {
      title = '$actorName đã thích bình luận của bạn';
    } else if (type == 'forum_reply') {
      title = '$actorName đã phản hồi bình luận của bạn';
    } else if (type == 'forum_chat_reply') {
      title = '$actorName đã trả lời tin nhắn của bạn trong Chat Tổng';
    } else if (type == 'forum_chat_mention') {
      title = '$actorName đã nhắc đến bạn trong Chat Tổng';
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
      'route': (type == 'forum_chat_reply' || type == 'forum_chat_mention')
          ? '/forum'
          : '/forum/detail/$postId',
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
  Future<void> toggleMessageReaction({
    required String messageId,
    required String uid,
    required String emoji,
  }) async {
    final ref = _firestore.collection('forumMessages').doc(messageId);
    try {
      await _firestore.runTransaction((transaction) async {
        final snap = await transaction.get(ref);
        if (!snap.exists) return;
        final data = snap.data() ?? {};
        final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
        if (reactions[uid] == emoji) {
          reactions.remove(uid); // Gỡ bỏ reaction nếu bấm lại cùng 1 emoji
        } else {
          reactions[uid] = emoji; // Đặt hoặc đổi emoji
        }
        transaction.update(ref, {'reactions': reactions});
      });
    } catch (e) {
      debugPrint('Lỗi thả reaction tin nhắn: $e');
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
