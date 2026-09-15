import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/features/reader/epub/epub_models.dart';
import 'package:manga_reader/services/glossary_service.dart';
import 'package:manga_reader/services/community_glossary_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('GlossaryService & Word Replacement Tests', () {
    test('applyReplacements correctly replaces text case-insensitively', () async {
      final service = GlossaryService.instance;
      await service.addRule(from: 'Nã Phá Luân', to: 'Napoleon');
      await service.addRule(from: 'Ái Nhân Tôn', to: 'Edison');

      const original = 'Nã Phá Luân và Ái Nhân Tôn là những nhân vật lịch sử nổi tiếng. nã phá luân xuất quân.';
      final transformed = service.applyReplacements(original);

      expect(
        transformed,
        'Napoleon và Edison là những nhân vật lịch sử nổi tiếng. Napoleon xuất quân.',
      );
    });

    test('applyReplacements respects mangaId scope vs global scope', () async {
      final service = GlossaryService.instance;
      await service.addRule(
        from: 'Đế Vương',
        to: 'Hoàng Đế',
        mangaId: 'novel_123',
      );
      await service.addRule(
        from: 'Bách Phân Chi Bách',
        to: '100%',
        mangaId: null, // Global
      );

      const text = 'Đế Vương có sức mạnh Bách Phân Chi Bách.';

      // For novel_123: both rules apply
      final forNovel123 = service.applyReplacements(text, mangaId: 'novel_123');
      expect(forNovel123, 'Hoàng Đế có sức mạnh 100%.');

      // For another novel (novel_999): only global rule applies
      final forNovel999 = service.applyReplacements(text, mangaId: 'novel_999');
      expect(forNovel999, 'Đế Vương có sức mạnh 100%.');
    });

    test('EpubChapter applyReplacements updates chapter title and block spans', () {
      final service = GlossaryService.instance;
      final chapter = EpubChapter(
        title: 'Chương 1: Nã Phá Luân xuất chinh',
        blocks: [
          EpubBlock(
            type: EpubBlockType.paragraph,
            spans: [
              const EpubSpan(text: 'Đại quân của '),
              const EpubSpan(text: 'Nã Phá Luân', bold: true),
              const EpubSpan(text: ' tiến về phương đông.'),
            ],
          ),
        ],
      );

      final processed = chapter.applyReplacements(
        (text) => service.applyReplacements(text),
      );

      expect(processed.title, 'Chương 1: Napoleon xuất chinh');
      expect(processed.blocks.first.spans![1].text, 'Napoleon');
      expect(processed.blocks.first.spans![1].bold, isTrue);
    });

    test('Disabling a rule prevents replacement', () async {
      final service = GlossaryService.instance;
      await service.addRule(from: 'Thần Thánh La Mã', to: 'Holy Roman Empire');

      final rule = service.rules.firstWhere((r) => r.from == 'Thần Thánh La Mã');
      await service.toggleRule(rule.id);

      const text = 'Đế quốc Thần Thánh La Mã sụp đổ.';
      final result = service.applyReplacements(text);
      expect(result, text); // Unchanged since disabled
    });

    test('Longer phrases are prioritized over shorter substrings', () async {
      final service = GlossaryService.instance;
      await service.addRule(from: 'Thần Thánh La Mã', to: 'HRE');
      await service.addRule(from: 'Thần Thánh La Mã Đế Quốc', to: 'Holy Roman Empire');

      const text = 'Lịch sử về Thần Thánh La Mã Đế Quốc.';
      final result = service.applyReplacements(text);
      expect(result, 'Lịch sử về Holy Roman Empire.');
    });

    test('Special regex characters in pattern are escaped properly', () async {
      final service = GlossaryService.instance;
      await service.addRule(from: '(Convert/Raw)', to: '[Đã Biên Dịch]');

      const text = 'Chương 10 (Convert/Raw) mới nhất.';
      final result = service.applyReplacements(text);
      expect(result, 'Chương 10 [Đã Biên Dịch] mới nhất.');
    });

    test('CommunityGlossaryPack serializes rules accurately', () {
      final pack = CommunityGlossaryPack(
        id: 'pack_123',
        title: 'Bộ Chuẩn Hóa Convert Kiếm Hiệp',
        description: 'Tập hợp các từ convert thường gặp',
        authorId: 'user_456',
        authorName: 'NovelMaster',
        authorAvatar: '',
        mangaTitle: 'Tiên Nghịch',
        rules: [
          GlossaryRule(
            id: '1',
            from: 'Nã Phá Luân',
            to: 'Napoleon',
            createdAt: DateTime.now(),
          ),
          GlossaryRule(
            id: '2',
            from: 'Ái Nhân Tôn',
            to: 'Edison',
            createdAt: DateTime.now(),
          ),
        ],
        downloadsCount: 15,
        likesCount: 7,
        likedUserIds: ['user_456'],
        createdAt: DateTime(2026, 8, 29),
      );

      final map = pack.toFirestore();
      expect(map['title'], 'Bộ Chuẩn Hóa Convert Kiếm Hiệp');
      expect(map['mangaTitle'], 'Tiên Nghịch');
      expect(map['downloadsCount'], 15);
      expect((map['rules'] as List).length, 2);
      expect((map['rules'] as List)[0]['from'], 'Nã Phá Luân');
      expect((map['rules'] as List)[0]['to'], 'Napoleon');
    });

    test('addRulesBatch imports multiple rules in a single batch', () async {
      final service = GlossaryService.instance;
      final count = await service.addRulesBatch([
        {'from': 'Bất Cửu', 'to': 'Chẳng Bao Lâu'},
        {'from': 'Ái Nhân Tôn', 'to': 'Edison'},
      ], mangaId: 'batch_test_novel');

      expect(count, 2);
      final replaced = service.applyReplacements(
        'Bất Cửu sau đó, Ái Nhân Tôn phát minh bóng đèn.',
        mangaId: 'batch_test_novel',
      );
      expect(replaced, 'Chẳng Bao Lâu sau đó, Edison phát minh bóng đèn.');
    });

    test('Special characters including dollar signs in replacement string are treated literally', () async {
      final service = GlossaryService.instance;
      await service.addRule(from: 'USD', to: r'$100.00');

      const text = 'Giá trị là 1 USD.';
      final result = service.applyReplacements(text);
      expect(result, r'Giá trị là 1 $100.00.');
    });

    test('exportRulesAsJson, importRulesFromJson, and clearRules work correctly', () async {
      final service = GlossaryService.instance;
      await service.clearRules();
      expect(service.rules.isEmpty, isTrue);

      await service.addRule(from: 'Bản Đao', to: 'Thanh Đao Này', mangaId: 'novel_export');
      await service.addRule(from: 'Vi Sư', to: 'Thầy Đây', mangaId: 'novel_export');

      final jsonStr = service.exportRulesAsJson(mangaId: 'novel_export');
      expect(jsonStr.contains('Bản Đao'), isTrue);
      expect(jsonStr.contains('Thanh Đao Này'), isTrue);

      await service.clearRules(mangaId: 'novel_export');
      expect(service.getRulesForManga('novel_export').isEmpty, isTrue);

      final imported = await service.importRulesFromJson(jsonStr, targetMangaId: 'novel_export');
      expect(imported, 2);
      expect(service.getRulesForManga('novel_export').length, 2);
    });

    test('normalizeMangaId seamlessly bridges storageKey and realMangaId variants', () async {
      final service = GlossaryService.instance;
      await service.clearRules();

      await service.addRule(
        from: 'Tiêu Viêm',
        to: 'Tieu Viem',
        mangaId: 'LOCAL_NOVEL|/sdcard/Download/btth.epub',
      );

      // Should match when queried with plain path
      final rulesPlain = service.getRulesForManga('/sdcard/Download/btth.epub');
      expect(rulesPlain.length, 1);
      expect(rulesPlain.first.to, 'Tieu Viem');

      // Should match when queried with epub_ prefix
      final rulesEpub = service.getRulesForManga('epub_/sdcard/Download/btth.epub');
      expect(rulesEpub.length, 1);

      // Should apply replacements across different representations
      final result = service.applyReplacements(
        'Tiêu Viêm tiến vào sơn động.',
        mangaId: '/sdcard/Download/btth.epub',
      );
      expect(result, 'Tieu Viem tiến vào sơn động.');
    });
  });
}
