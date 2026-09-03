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

  test('forum poll round-trips data and handles voting counts correctly', () {
    final postWithPoll = ForumPost.fromMap('post-poll-1', {
      'authorName': 'AnimeFan',
      'body': 'Bình chọn nhân vật yêu thích',
      'poll': {
        'question': 'Ai là best girl?',
        'options': ['Rem', 'Emilia', 'Ram'],
        'votes': {'0': 15, '1': 10, '2': 3},
        'voterUids': ['uid1', 'uid2'],
        'userVotes': {'uid1': 0, 'uid2': 1},
      },
    });

    expect(postWithPoll.poll, isNotNull);
    expect(postWithPoll.poll!.question, 'Ai là best girl?');
    expect(postWithPoll.poll!.options, ['Rem', 'Emilia', 'Ram']);
    expect(postWithPoll.poll!.totalVotes, 28);
    expect(postWithPoll.poll!.votes['0'], 15);
    expect(postWithPoll.poll!.voterUids.contains('uid1'), isTrue);
    expect(postWithPoll.poll!.userVotes['uid2'], 1);
  });

  test('ForumPost extractHashtags parses hashtags accurately', () {
    const text = 'Hôm nay xem tập mới đỉnh quá #skibidi #onepiece #anime #Skibidi';
    final tags = ForumPost.extractHashtags(text);
    expect(tags, contains('skibidi'));
    expect(tags, contains('onepiece'));
    expect(tags, contains('anime'));
    expect(tags.length, 3); // De-duplicated

    const viText = 'Mọi người thảo luận nhé #thảoluận #đề_xuất';
    final viTags = ForumPost.extractHashtags(viText);
    expect(viTags, contains('thảoluận'));
    expect(viTags, contains('đề_xuất'));
  });

  test('ForumPost parses explicit tags and falls back to body hashtags', () {
    final postWithExplicitTags = ForumPost.fromMap('post-tags-1', {
      'body': 'Nội dung bình thường',
      'tags': ['skibidi', 'review', '#anime'],
    });
    expect(postWithExplicitTags.tags, ['skibidi', 'review', 'anime']);

    final postWithBodyHashtags = ForumPost.fromMap('post-tags-2', {
      'body': 'Đọc bộ này cuốn cực #spoil #siêu_phẩm',
    });
    expect(postWithBodyHashtags.tags, ['spoil', 'siêu_phẩm']);
  });
}
