import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/features/reader/epub/epub_parser.dart';
import 'package:manga_reader/features/reader/epub/epub_models.dart';

void main() {
  group('EpubParser', () {
    Uint8List createMockEpubBytes({
      required String containerContent,
      required String opfContent,
      required Map<String, String> htmlContents,
      String? ncxContent,
      String? navContent,
      Map<String, Uint8List>? images,
    }) {
      final archive = Archive();

      archive.addFile(
        ArchiveFile(
          'META-INF/container.xml',
          utf8.encode(containerContent).length,
          containerContent,
        ),
      );

      archive.addFile(
        ArchiveFile(
          'OEBPS/content.opf',
          utf8.encode(opfContent).length,
          opfContent,
        ),
      );

      htmlContents.forEach((path, content) {
        archive.addFile(
          ArchiveFile('OEBPS/$path', utf8.encode(content).length, content),
        );
      });

      if (ncxContent != null) {
        archive.addFile(
          ArchiveFile(
            'OEBPS/toc.ncx',
            utf8.encode(ncxContent).length,
            ncxContent,
          ),
        );
      }

      if (navContent != null) {
        archive.addFile(
          ArchiveFile(
            'OEBPS/nav.xhtml',
            utf8.encode(navContent).length,
            navContent,
          ),
        );
      }

      images?.forEach((path, content) {
        archive.addFile(ArchiveFile('OEBPS/$path', content.length, content));
      });

      return Uint8List.fromList(ZipEncoder().encode(archive)!);
    }

    test('EPUB3 parsing with nav.xhtml and inline images', () {
      final bytes = createMockEpubBytes(
        containerContent: '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
    </rootfiles>
</container>''',
        opfContent: '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
    <manifest>
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="ch1" href="chap1.xhtml" media-type="application/xhtml+xml"/>
        <item id="img1" href="image.jpg" media-type="image/jpeg"/>
    </manifest>
    <spine>
        <itemref idref="ch1"/>
    </spine>
</package>''',
        navContent: '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
    <body>
        <nav epub:type="toc">
            <ol>
                <li><a href="chap1.xhtml">Chương 1: Mở đầu</a></li>
            </ol>
        </nav>
    </body>
</html>''',
        htmlContents: {
          'chap1.xhtml': '''
<html xmlns="http://www.i3.org/1999/xhtml">
    <body>
        <h1>Tiêu đề 1</h1>
        <p>Đoạn văn có chữ <b>in đầm</b>, <i>in nghiêng</i> và <u>gạch chân</u>.</p>
        <img src="image.jpg" alt="test image"/>
    </body>
</html>''',
        },
        images: {
          'image.jpg': Uint8List.fromList([1, 2, 3, 4]),
        },
      );

      final args = EpubParseArgs(bytes: bytes, title: 'Test EPUB3');
      final epub = EpubParser.parse(args);

      expect(epub.title, 'Test EPUB3');
      expect(epub.chapters.length, 1);

      final ch1 = epub.chapters.first;
      expect(ch1.title, 'Chương 1: Mở đầu');
      expect(ch1.text, contains('Tiêu đề 1'));
      expect(
        ch1.text,
        contains('Đoạn văn có chữ in đầm, in nghiêng và gạch chân.'),
      );
      expect(ch1.images.length, 1);
      expect(ch1.images.first, [1, 2, 3, 4]);
      final richParagraph = ch1.blocks.firstWhere(
        (block) => block.text?.contains('Đoạn văn có chữ') ?? false,
      );
      expect(richParagraph.spans?.map((span) => span.text).toList(), [
        'Đoạn văn có chữ ',
        'in đầm',
        ', ',
        'in nghiêng',
        ' và ',
        'gạch chân',
        '.',
      ]);
      expect(richParagraph.spans?[1].bold, true);
      expect(richParagraph.spans?[3].italic, true);
      expect(richParagraph.spans?[5].underline, true);
    });

    test('EPUB2 parsing with toc.ncx fallback', () {
      final bytes = createMockEpubBytes(
        containerContent: '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
    </rootfiles>
</container>''',
        opfContent: '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
    <manifest>
        <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
        <item id="ch1" href="chap1.xhtml" media-type="application/xhtml+xml"/>
    </manifest>
    <spine toc="ncx">
        <itemref idref="ch1"/>
    </spine>
</package>''',
        ncxContent: '''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
    <navMap>
        <navPoint id="navPoint-1" playOrder="1">
            <navLabel><text>Chương 1 (EPUB2)</text></navLabel>
            <content src="chap1.xhtml"/>
        </navPoint>
    </navMap>
</ncx>''',
        htmlContents: {
          'chap1.xhtml':
              '<html xmlns="http://www.w3.org/1999/xhtml"><body>Nội dung 1</body></html>',
        },
      );

      final args = EpubParseArgs(bytes: bytes, title: 'Test EPUB2');
      final epub = EpubParser.parse(args);

      expect(epub.chapters.length, 1);
      expect(epub.chapters.first.title, 'Chương 1 (EPUB2)');
      expect(epub.chapters.first.text, 'Chương 1 (EPUB2)\n\nNội dung 1');
    });

    test(
      'Finding 3.1 & 3.2: Custom nav filename, missing image asset, properties="nav"',
      () {
        final bytes = createMockEpubBytes(
          containerContent: '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
    </rootfiles>
</container>''',
          opfContent: '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
    <manifest>
        <item id="nav" href="random-nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="ch1" href="chap1.xhtml" media-type="application/xhtml+xml"/>
    </manifest>
    <spine>
        <itemref idref="ch1"/>
    </spine>
</package>''',
          htmlContents: {
            "random-nav.xhtml": '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
    <body>
        <nav epub:type="landmarks">
            <ol><li><a href="chap1.xhtml">Landmark (Should be ignored)</a></li></ol>
        </nav>
        <nav epub:type="toc">
            <ol>
                <li><a href="chap1.xhtml">Chương 1 Custom Nav</a></li>
            </ol>
        </nav>
    </body>
</html>''',
            "chap1.xhtml": '''
<html xmlns="http://www.i3.org/1999/xhtml">
    <body>
        <p>Text before missing image.</p>
        <img src="missing.jpg" alt="missing"/>
        <p>Text after missing image.</p>
    </body>
</html>''',
          },
        );

        final args = EpubParseArgs(bytes: bytes, title: 'Test Custom Nav');
        final epub = EpubParser.parse(args);

        expect(epub.chapters.length, 1);
        final ch1 = epub.chapters.first;
        expect(ch1.title, 'Chương 1 Custom Nav');
        expect(ch1.text, contains('Text before missing image.'));
        expect(ch1.text, contains('Text after missing image.'));
        expect(ch1.images.isEmpty, true);
      },
    );

    test('Finding 3.3: Invalid XHTML fallback text does not crash', () {
      final bytes = createMockEpubBytes(
        containerContent: '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
    </rootfiles>
</container>''',
        opfContent: '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
    <manifest>
        <item id="ch1" href="chap1.xhtml" media-type="application/xhtml+xml"/>
    </manifest>
    <spine>
        <itemref idref="ch1"/>
    </spine>
</package>''',
        htmlContents: {
          'chap1.xhtml':
              '<html xmlns="http://www.w3.org/1999/xhtml"><body><div>Nội dung thiếu đóng tag <br> Text tiẽp theo</body></html>',
        },
      );

      final args = EpubParseArgs(bytes: bytes, title: 'Test Invalid XHTML');
      final epub = EpubParser.parse(args);

      expect(epub.chapters.length, 1);
      expect(epub.chapters.first.text, contains('Nội dung thiếu đóng tag'));
      expect(epub.chapters.first.text, contains('Text tiẽp theo'));
    });

    test(
      'Finding 3.4 & 3.5: Smoke test multiple chapters and image ordering prep',
      () {
        final bytes = createMockEpubBytes(
          containerContent: '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
    </rootfiles>
</container>''',
          opfContent: '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
    <manifest>
        <item id="ch1" href="chap1.xhtml" media-type="application/xhtml+xml"/>
        <item id="ch2" href="chap2.xhtml" media-type="application/xhtml+xml"/>
        <item id="img1" href="image.jpg" media-type="image/jpeg"/>
    </manifest>
    <spine>
        <itemref idref="ch1"/>
        <itemref idref="ch2"/>
    </spine>
</package>''',
          htmlContents: {
            'chap1.xhtml': '''
<html xmlns="http://www.w3.org/1999/xhtml">
    <body>
        <p>Text block 1</p>
        <img src="image.jpg" alt="test"/>
        <p>Text block 2</p>
    </body>
</html>''',
            'chap2.xhtml': '''
<html xmlns="http://www.w3.org/1999/xhtml">
    <body>
        <p>Chapter 2 content</p>
    </body>
</html>''',
          },
          images: {
            'image.jpg': Uint8List.fromList([5, 6, 7, 8]),
          },
        );

        final args = EpubParseArgs(bytes: bytes, title: 'Smoke Test EPUB');
        final epub = EpubParser.parse(args);

        expect(epub.chapters.length, 2);

        final ch1 = epub.chapters[0];
        expect(ch1.text, contains('Text block 1'));
        expect(ch1.text, contains('Text block 2'));
        expect(ch1.images.length, 1);

        final ch2 = epub.chapters[1];
        expect(ch2.text, contains('Chapter 2 content'));
      },
    );

    test('Finding 5: Integration compute() test', () async {
      final bytes = createMockEpubBytes(
        containerContent: '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
    </rootfiles>
</container>''',
        opfContent: '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
    <manifest>
        <item id="ch1" href="chap1.xhtml" media-type="application/xhtml+xml"/>
    </manifest>
    <spine>
        <itemref idref="ch1"/>
    </spine>
</package>''',
        htmlContents: {
          'chap1.xhtml':
              '<html xmlns="http://www.w3.org/1999/xhtml"><body>Isolate Content</body></html>',
        },
      );

      final args = EpubParseArgs(bytes: bytes, title: 'Isolate EPUB');

      final epub = await compute(EpubParser.parse, args);

      expect(epub.title, 'Isolate EPUB');
      expect(epub.chapters.length, 1);
      expect(epub.chapters.first.text, 'Chương 1\n\nIsolate Content');
    });

    test('Regression Phase EPUB-2: Structured blocks parsing', () {
      final bytes = createMockEpubBytes(
        containerContent: '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''',
        opfContent: '''<?xml version="1.0"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata></metadata>
  <manifest>
    <item id="toc" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="img1" href="img1.jpg" media-type="image/jpeg"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>''',
        navContent:
            '<nav epub:type="toc"><a href="ch1.xhtml">Chương Một</a></nav>',
        htmlContents: {
          'ch1.xhtml': '''
            <h1>Tiêu đề</h1>
            <p>Đoạn 1</p>
            <img src="img1.jpg"/>
            <p>Đoạn 2</p>
            <blockquote><p>Quote lồng p</p></blockquote>
            <hr/>
          ''',
          'ch2.xhtml': '''
            <p>Dòng 1</p>
            <br/>
            
            <p>Dòng 2 không bị mất</p>
          ''',
        },
        images: {
          'img1.jpg': Uint8List.fromList([1, 2, 3]),
        },
      );

      final epub = EpubParser.parse(
        EpubParseArgs(bytes: bytes, title: 'Test Book'),
      );
      expect(epub.chapters.length, 2);

      final ch1 = epub.chapters[0];
      expect(ch1.title, 'Chương Một');
      expect(ch1.blocks.length, 7);

      expect(ch1.blocks[0].type, EpubBlockType.heading);
      expect(ch1.blocks[0].text, 'Chương Một');

      expect(ch1.blocks[1].type, EpubBlockType.heading);
      expect(ch1.blocks[1].text, 'Tiêu đề');

      expect(ch1.blocks[2].type, EpubBlockType.paragraph);
      expect(ch1.blocks[2].text, 'Đoạn 1');

      expect(ch1.blocks[3].type, EpubBlockType.image);
      expect(ch1.blocks[3].image, [1, 2, 3]);

      expect(ch1.blocks[4].type, EpubBlockType.paragraph);
      expect(ch1.blocks[4].text, 'Đoạn 2');

      expect(ch1.blocks[5].type, EpubBlockType.quote);
      expect(ch1.blocks[5].text, 'Quote lồng p');

      expect(ch1.blocks[6].type, EpubBlockType.divider);

      final ch2 = epub.chapters[1];
      expect(ch2.title, 'Chương 2');
      expect(ch2.blocks.length, 3);
      expect(ch2.blocks[0].text, 'Chương 2');
      expect(ch2.blocks[1].text, 'Dòng 1');
      expect(ch2.blocks[2].text, 'Dòng 2 không bị mất');
    });

    test('Injects title block when missing from content', () {
      final bytes = createMockEpubBytes(
        containerContent: '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''',
        opfContent: '''<?xml version="1.0"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata></metadata>
  <manifest>
    <item id="toc" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
  </spine>
</package>''',
        navContent:
            '<nav epub:type="toc"><a href="ch1.xhtml">Chapter One</a></nav>',
        htmlContents: {
          'ch1.xhtml': '''
            <p>This is the first paragraph without a heading.</p>
          ''',
        },
      );

      final epub = EpubParser.parse(
        EpubParseArgs(bytes: bytes, title: 'Test Book'),
      );
      expect(epub.chapters.length, 1);

      final ch1 = epub.chapters[0];
      expect(ch1.title, 'Chapter One');

      // The parser should inject the title as a heading block
      expect(ch1.blocks.length, 2);
      expect(ch1.blocks[0].type, EpubBlockType.heading);
      expect(ch1.blocks[0].text, 'Chapter One');
      expect(ch1.blocks[1].type, EpubBlockType.paragraph);
      expect(
        ch1.blocks[1].text,
        'This is the first paragraph without a heading.',
      );
    });

    test('Lazy index parses large spine without opening chapter XHTML', () {
      const chapterCount = 300;
      final manifest = StringBuffer();
      final spine = StringBuffer();
      final nav = StringBuffer('<nav epub:type="toc">');
      final htmlContents = <String, String>{};

      for (var index = 1; index <= chapterCount; index++) {
        manifest.writeln(
          '<item id="ch$index" href="ch$index.xhtml" media-type="application/xhtml+xml"/>',
        );
        spine.writeln('<itemref idref="ch$index"/>');
        nav.write('<a href="ch$index.xhtml">Chương $index</a>');
        htmlContents['ch$index.xhtml'] = index == 175
            ? '<html><body><p>${String.fromCharCode(0)}</p></body></html>'
            : '<html><body><p>Nội dung chương $index</p></body></html>';
      }
      nav.write('</nav>');

      final bytes = createMockEpubBytes(
        containerContent: '''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''',
        opfContent:
            '''
<package version="3.0" xmlns="http://www.idpf.org/2007/opf">
  <manifest>
    <item id="toc" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    $manifest
  </manifest>
  <spine>$spine</spine>
</package>''',
        navContent: nav.toString(),
        htmlContents: htmlContents,
      );

      final stopwatch = Stopwatch()..start();
      final index = EpubParser.parseIndex(
        EpubParseArgs(bytes: bytes, title: 'Large Book'),
      );
      stopwatch.stop();

      expect(index.chapters.length, chapterCount);
      expect(index.chapters.first.title, 'Chương 1');
      expect(index.chapters.last.title, 'Chương 300');
      expect(index.chapters[174].href, 'OEBPS/ch175.xhtml');
      // Keep a visible benchmark log without asserting device-specific timing.
      debugPrint(
        'Lazy EPUB index benchmark: $chapterCount chapters in '
        '${stopwatch.elapsedMilliseconds}ms',
      );
    });

    test('Lazy chapter parser opens only requested chapter', () {
      final bytes = createMockEpubBytes(
        containerContent: '''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''',
        opfContent: '''
<package version="3.0" xmlns="http://www.idpf.org/2007/opf">
  <manifest>
    <item id="toc" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>''',
        navContent: '''
<nav epub:type="toc">
  <a href="ch1.xhtml">Chương Một</a>
  <a href="ch2.xhtml">Chương Hai</a>
</nav>''',
        htmlContents: {
          'ch1.xhtml': '<html><body><p>Nội dung một</p></body></html>',
          'ch2.xhtml': '<html><body><p>Nội dung hai</p></body></html>',
        },
      );
      final index = EpubParser.parseIndex(
        EpubParseArgs(bytes: bytes, title: 'Lazy Book'),
      );

      final chapter = EpubParser.parseChapter(
        EpubChapterParseArgs(bytes: bytes, chapter: index.chapters[1]),
      );

      expect(chapter.title, 'Chương Hai');
      expect(chapter.text, contains('Nội dung hai'));
      expect(chapter.text, isNot(contains('Nội dung một')));
    });
  });
}
