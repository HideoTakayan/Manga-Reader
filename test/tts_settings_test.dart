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

    test('extractSentenceSpans splits sentences cleanly with accurate offsets', () {
      const text = 'Hắn mở mắt ra. Căn phòng hoàn toàn yên tĩnh! Có ai không?';
      final spans = TtsService.extractSentenceSpans(text);
      expect(spans.length, 3);
      expect(spans[0].text, 'Hắn mở mắt ra.');
      expect(text.substring(spans[0].start, spans[0].end), spans[0].text);
      expect(spans[1].text, 'Căn phòng hoàn toàn yên tĩnh!');
      expect(text.substring(spans[1].start, spans[1].end), spans[1].text);
      expect(spans[2].text, 'Có ai không?');
      expect(text.substring(spans[2].start, spans[2].end), spans[2].text);

      const numText = 'Tốc độ tăng 1.5 lần so với trước đó.';
      final numSpans = TtsService.extractSentenceSpans(numText);
      expect(numSpans.length, 1);
      expect(numSpans[0].text, 'Tốc độ tăng 1.5 lần so với trước đó.');
    });

    test('stopAtEndOfChapter flag operates correctly', () {
      final tts = TtsService.instance;
      expect(tts.stopAtEndOfChapter, isFalse);
      tts.setStopAtEndOfChapter(true);
      expect(tts.stopAtEndOfChapter, isTrue);
      tts.setStopAtEndOfChapter(false);
      expect(tts.stopAtEndOfChapter, isFalse);
    });

    test('splitTtsChunks creates valid chunks with block index', () {
      final tts = TtsService.instance;
      final blocks = ['Đoạn văn thứ nhất.', 'Đoạn văn thứ hai có hai câu! Câu thứ hai đây.'];
      final chunks = tts.splitTtsChunks('', blockTexts: blocks);
      expect(chunks.length, 3);
      expect(chunks[0].blockIndex, 0);
      expect(chunks[0].text, 'Đoạn văn thứ nhất.');
      expect(chunks[1].blockIndex, 1);
      expect(chunks[1].text, 'Đoạn văn thứ hai có hai câu!');
      expect(chunks[2].blockIndex, 1);
      expect(chunks[2].text, 'Câu thứ hai đây.');
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
