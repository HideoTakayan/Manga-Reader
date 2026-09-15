import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/features/reader/epub/epub_models.dart';
import 'package:manga_reader/features/reader/epub/epub_paginator.dart';

void main() {
  test('EpubPaginator.buildHighlightedTextSpan splits sentences and words correctly', () {
    const block = EpubBlock(
      type: EpubBlockType.paragraph,
      spans: [
        EpubSpan(text: 'Kusanagi đang đứng trước cửa phòng tập thể dục, mắt nhìn vào bên trong. '),
        EpubSpan(text: 'ở khoảng sân đối diện Kusanagi, Yugawa đang cầm vợt với tư thế sẵn sang. '),
        EpubSpan(text: 'So với hồi còn trẻ, cơ bắp của Yugawa có vẻ đã hơi yếu đi nhưng hình thể thì không có gì thay đổi.'),
      ],
    );

    const baseStyle = TextStyle(color: Colors.white, fontSize: 16);
    final span = EpubPaginator.buildHighlightedTextSpan(
      block,
      baseStyle,
      sentenceStart: 0,
      sentenceEnd: 71,
      wordStart: 14,
      wordEnd: 18,
    );

    expect(span.children, isNotNull);
    final texts = span.children!.map((c) => (c as TextSpan).text).toList();
    expect(texts, contains('đứng'));
  });
}
