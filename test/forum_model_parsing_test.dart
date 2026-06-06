import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/features/forum/models/forum_comment.dart';
import 'package:manga_reader/features/forum/models/forum_message.dart';
import 'package:manga_reader/features/forum/models/forum_post.dart';

void main() {
  test('forum post ignores malformed typed fields', () {
    final post = ForumPost.fromMap('post-1', {
      'authorName': 123,
      'authorAvatar': {'bad': true},
      'sharedMangaTitle': false,
      'likeCount': 'many',
      'isDeleted': 'false',
    });

    expect(post.authorName, 'Unknown');
    expect(post.authorAvatar, '');
    expect(post.sharedMangaTitle, isNull);
    expect(post.likeCount, 0);
    expect(post.isDeleted, isFalse);
  });

  test('forum comment ignores malformed reply fields', () {
    final comment = ForumComment.fromMap('comment-1', {
      'authorName': ['bad'],
      'replyToCommentId': 42,
      'replyToAuthorName': true,
      'replyToUserId': {'bad': true},
    });

    expect(comment.authorName, 'Unknown');
    expect(comment.replyToCommentId, isNull);
    expect(comment.replyToAuthorName, isNull);
    expect(comment.replyToUserId, isNull);
  });

  test('forum message ignores malformed author and reply fields', () {
    final message = ForumMessage.fromMap('message-1', {
      'authorName': 123,
      'authorIsAdmin': 'true',
      'replyToMessageId': false,
      'replyToAuthorName': [],
      'replyToBody': {'bad': true},
    });

    expect(message.authorName, 'Người dùng');
    expect(message.authorIsAdmin, isFalse);
    expect(message.replyToMessageId, isNull);
    expect(message.replyToAuthorName, isNull);
    expect(message.replyToBody, isNull);
  });
}
