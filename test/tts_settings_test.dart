import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/services/tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('TTS Service & Settings Tests', () {
    test('availableSpeeds includes speeds up to 3.0x', () {
      expect(TtsService.availableSpeeds.contains(0.5), isTrue);
      expect(TtsService.availableSpeeds.contains(1.0), isTrue);
      expect(TtsService.availableSpeeds.contains(2.0), isTrue);
      expect(TtsService.availableSpeeds.contains(2.5), isTrue);
      expect(TtsService.availableSpeeds.contains(3.0), isTrue);
    });

    test('splitTtsChunks creates valid chunks matching entire blocks (paragraphs)', () {
      final tts = TtsService.instance;
      final blocks = ['Đoạn văn thứ nhất.', 'Đoạn văn thứ hai có hai câu! Câu thứ hai đây.'];
      final chunks = tts.splitTtsChunks('', blockTexts: blocks);
      expect(chunks.length, 2);
      expect(chunks[0].blockIndex, 0);
      expect(chunks[0].text, 'Đoạn văn thứ nhất.');
      expect(chunks[1].blockIndex, 1);
      expect(chunks[1].text, 'Đoạn văn thứ hai có hai câu! Câu thứ hai đây.');
    });

    test('stopAtEndOfChapter flag operates correctly', () {
      final tts = TtsService.instance;
      expect(tts.stopAtEndOfChapter, isFalse);
      tts.setStopAtEndOfChapter(true);
      expect(tts.stopAtEndOfChapter, isTrue);
      tts.setStopAtEndOfChapter(false);
      expect(tts.stopAtEndOfChapter, isFalse);
    });

    test('onNextChapterRequested and onPrevChapterRequested support boolean returns', () async {
      final tts = TtsService.instance;
      tts.onNextChapterRequested = () async => true;
      tts.onPrevChapterRequested = () async => false;
      expect(await tts.onNextChapterRequested!(), isTrue);
      expect(await tts.onPrevChapterRequested!(), isFalse);
      tts.onNextChapterRequested = null;
      tts.onPrevChapterRequested = null;
    });
  });
}
