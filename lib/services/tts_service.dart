import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../features/reader/epub/epub_parser.dart';
import '../features/reader/epub/epub_models.dart';
import 'notification_service.dart';
import 'glossary_service.dart';

class TtsChunk {
  final String text;
  final int blockIndex;
  final int charStartInBlock;
  final int charEndInBlock;

  const TtsChunk({
    required this.text,
    this.blockIndex = 0,
    this.charStartInBlock = 0,
    this.charEndInBlock = 0,
  });

  @override
  String toString() => 'TtsChunk(b:$blockIndex, [$charStartInBlock..$charEndInBlock]: "$text")';
}

class TtsService extends ChangeNotifier {
  static final TtsService instance = TtsService._internal();
  TtsService._internal() {
    _initTts();
    _hookNotificationActions();
  }

  final FlutterTts _tts = FlutterTts();

  String? _currentMangaId;
  String? _currentChapterId;
  String? _currentChapterTitle;
  String? _mangaTitle;
  String? _coverUrl;
  String? _epubPath;
  int _currentChapterIndex = 0;

  bool _isPlaying = false;
  bool _isVisible = false;
  double _rate = 0.5;
  double _pitch = 1.0;
  String _lang = 'vi-VN';
  List<Map<String, String>> _availableVoices = [];
  Map<String, String>? _selectedVoice;

  List<TtsChunk> _chunks = [];
  int _chunkIndex = 0;
  String? _lastFullText;
  List<String>? _lastBlockTexts;

  int? _currentWordStart;
  int? _currentWordEnd;
  String? _currentWord;

  final ValueNotifier<({int? start, int? end})> wordProgressNotifier = ValueNotifier((start: null, end: null));

  Timer? _sleepTimer;
  int _sleepMinutesRemaining = 0;
  bool _stopAtEndOfChapter = false;

  Future<bool> Function()? onNextChapterRequested;
  Future<bool> Function()? onPrevChapterRequested;

  // Getters
  String? get currentMangaId => _currentMangaId;
  String? get currentChapterId => _currentChapterId;
  String? get currentChapterTitle => _currentChapterTitle;
  String? get mangaTitle => _mangaTitle;
  String? get coverUrl => _coverUrl;
  String? get epubPath => _epubPath;
  int get currentChapterIndex => _currentChapterIndex;
  bool get isPlaying => _isPlaying;
  bool get isVisible => _isVisible;
  double get rate => _rate;
  double get pitch => _pitch;
  String get lang => _lang;
  List<Map<String, String>> get availableVoices => _availableVoices;
  Map<String, String>? get selectedVoice => _selectedVoice;
  int get chunkIndex => _chunkIndex;
  int get totalChunks => _chunks.length;
  List<TtsChunk> get chunks => List.unmodifiable(_chunks);
  TtsChunk? get currentChunk =>
      (_chunks.isNotEmpty && _chunkIndex >= 0 && _chunkIndex < _chunks.length)
          ? _chunks[_chunkIndex]
          : null;
  String? get currentChunkText => currentChunk?.text;
  int? get currentBlockIndex => currentChunk?.blockIndex;
  int? get currentWordStart => _currentWordStart;
  int? get currentWordEnd => _currentWordEnd;
  String? get currentWord => _currentWord;
  double get progress => _chunks.isEmpty ? 0.0 : (_chunkIndex + 1) / _chunks.length;
  int get sleepMinutesRemaining => _sleepMinutesRemaining;
  bool get stopAtEndOfChapter => _stopAtEndOfChapter;

  void setStopAtEndOfChapter(bool value) {
    _stopAtEndOfChapter = value;
    notifyListeners();
  }

  void _hookNotificationActions() {
    NotificationService.onTtsActionReceived = (actionId) {
      switch (actionId) {
        case 'tts_play_pause':
          togglePlayPause();
          break;
        case 'tts_next':
          nextChunk();
          break;
        case 'tts_prev':
          prevChunk();
          break;
        case 'tts_stop':
          stopAndHide();
          break;
      }
    };
  }

  Future<void> _initTts() async {
    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {}

    _tts.setCompletionHandler(() {
      _currentWordStart = null;
      _currentWordEnd = null;
      _currentWord = null;
      wordProgressNotifier.value = (start: null, end: null);
      _playNextChunk();
    });

    _tts.setProgressHandler((String text, int start, int end, String word) {
      if (currentChunkText == null || text != currentChunkText) return;
      _currentWordStart = start.clamp(0, text.length);
      _currentWordEnd = end.clamp(0, text.length);
      _currentWord = word;
      wordProgressNotifier.value = (start: _currentWordStart, end: _currentWordEnd);
      // Không gọi notifyListeners() ở đây vì word-by-word progress gây rebuild toàn UI
      // Sử dụng wordProgressNotifier để update độc lập từng khối UI nhỏ (ValueListenableBuilder)
    });

    _tts.setErrorHandler((msg) {
      debugPrint('TTS Error: $msg');
      _isPlaying = false;
      _currentWordStart = null;
      _currentWordEnd = null;
      _currentWord = null;
      WakelockPlus.disable();
      _updateMediaNotification();
      notifyListeners();
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      _rate = prefs.getDouble('global_tts_rate') ?? 0.5;
      _pitch = prefs.getDouble('global_tts_pitch') ?? 1.0;
      _lang = prefs.getString('global_tts_lang') ?? 'vi-VN';
      await _loadVoicesForLang(_lang);
    } catch (_) {}
  }

  Future<void> _loadVoicesForLang(String lang) async {
    try {
      final voices = await _tts.getVoices;
      if (voices == null) {
        await _tts.setLanguage(lang);
        return;
      }
      final parsed = <Map<String, String>>[];
      final cleanLang = lang.replaceAll(RegExp(r'[-_]'), '').toLowerCase();

      for (final voice in voices) {
        if (voice is! Map) continue;
        final locale = voice['locale']?.toString() ?? '';
        final name = voice['name']?.toString() ?? '';
        final cleanLocale = locale.replaceAll(RegExp(r'[-_]'), '').toLowerCase();

        final isMatch = cleanLocale.contains(cleanLang) ||
            cleanLang.contains(cleanLocale) ||
            (cleanLang.startsWith('vi') &&
                (cleanLocale.contains('vi') ||
                    cleanLocale.contains('vie') ||
                    cleanLocale.contains('vnm') ||
                    cleanLocale.contains('vietnam')));

        if (isMatch) {
          parsed.add({'name': name, 'locale': locale});
        }
      }
      _availableVoices = parsed;
      final prefs = await SharedPreferences.getInstance();
      final savedVoiceName = prefs.getString('global_tts_voice_name');
      final savedVoiceLocale = prefs.getString('global_tts_voice_locale');

      Map<String, String>? matchingVoice;
      if (savedVoiceName != null && savedVoiceName.isNotEmpty) {
        matchingVoice = parsed.cast<Map<String, String>?>().firstWhere(
          (v) => v != null && v['name'] == savedVoiceName && (savedVoiceLocale == null || v['locale'] == savedVoiceLocale),
          orElse: () => null,
        );
      }

      _selectedVoice = matchingVoice ?? parsed.firstOrNull;
      if (_selectedVoice != null) {
        await _tts.setVoice({
          'name': _selectedVoice!['name']!,
          'locale': _selectedVoice!['locale']!,
        });
      } else {
        await _tts.setLanguage(lang);
      }
    } catch (e) {
      debugPrint('TTS loadVoices error: $e');
    }
  }

  /// Trích xuất danh sách câu kèm tọa độ ký tự chính xác tuyệt đối trong block.
  /// Không dùng indexOf sau khi trim/split giúp loại bỏ hoàn toàn lỗi lệch index highlight.
  static List<({String text, int start, int end})> extractSentenceSpans(String block) {
    if (block.isEmpty) return const [];

    final spans = <({String text, int start, int end})>[];
    // Khớp các câu kết thúc bởi: ! ? … 。！？ hoặc dấu . KHÔNG phải thập phân (1.5 an toàn)
    final sentenceRegex = RegExp(
      r'(?:[^.!?…。！？\n]|\d\.\d)*(?:(?<!\d)\.(?!\d)[“”‘\)]*|[!?…。！？]+[“”‘\)]*|\n+|$)',
      multiLine: true,
    );

    for (final match in sentenceRegex.allMatches(block)) {
      final raw = match.group(0) ?? '';
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;

      final leadingOffset = raw.indexOf(trimmed);
      final sentenceStart = match.start + (leadingOffset != -1 ? leadingOffset : 0);
      final sentenceEnd = sentenceStart + trimmed.length;

      // Chỉ cắt câu cực kỳ dài (> 240 ký tự) không có dấu chấm để TTS dễ thở hơn
      if (trimmed.length > 240) {
        final subRegex = RegExp(r'[^,;:\-—\n]+(?:[,;:\-—]+|\n+|$)');
        var curBuf = '';
        var curStart = sentenceStart;
        for (final subMatch in subRegex.allMatches(trimmed)) {
          final subRaw = subMatch.group(0) ?? '';
          if (curBuf.isNotEmpty && (curBuf.length + subRaw.length > 180)) {
            final tBuf = curBuf.trim();
            if (tBuf.isNotEmpty) {
              final lead = curBuf.indexOf(tBuf);
              final actualStart = curStart + (lead != -1 ? lead : 0);
              spans.add((text: tBuf, start: actualStart, end: actualStart + tBuf.length));
            }
            curBuf = subRaw;
            curStart = sentenceStart + subMatch.start;
          } else {
            curBuf += subRaw;
          }
        }
        final tBuf = curBuf.trim();
        if (tBuf.isNotEmpty) {
          final lead = curBuf.indexOf(tBuf);
          final actualStart = curStart + (lead != -1 ? lead : 0);
          spans.add((text: tBuf, start: actualStart, end: actualStart + tBuf.length));
        }
      } else {
        spans.add((text: trimmed, start: sentenceStart, end: sentenceEnd));
      }
    }

    return spans;
  }

  static List<String> splitParagraphIntoSentences(String para) {
    final spans = extractSentenceSpans(para);
    if (spans.isEmpty) return const [];
    return spans.map((s) => s.text).toList();
  }

  List<TtsChunk> splitTtsChunks(
    String text, {
    List<String>? blockTexts,
    String? mangaId,
  }) {
    final chunks = <TtsChunk>[];

    if (blockTexts != null && blockTexts.isNotEmpty) {
      for (var bIdx = 0; bIdx < blockTexts.length; bIdx++) {
        final rawBlock = blockTexts[bIdx];
        final block = GlossaryService.instance
            .applyReplacements(rawBlock, mangaId: mangaId);
        if (block.trim().isEmpty) continue;

        final sentenceSpans = extractSentenceSpans(block);
        for (final s in sentenceSpans) {
          chunks.add(TtsChunk(
            text: s.text,
            blockIndex: bIdx,
            charStartInBlock: s.start,
            charEndInBlock: s.end,
          ));
        }
      }
    } else {
      final processedText = GlossaryService.instance
          .applyReplacements(text, mangaId: mangaId);
      final paragraphs = processedText.split(RegExp(r'\n\s*\n'));
      for (var bIdx = 0; bIdx < paragraphs.length; bIdx++) {
        final para = paragraphs[bIdx];
        if (para.trim().isEmpty) continue;

        final sentenceSpans = extractSentenceSpans(para);
        for (final s in sentenceSpans) {
          chunks.add(TtsChunk(
            text: s.text,
            blockIndex: bIdx,
            charStartInBlock: s.start,
            charEndInBlock: s.end,
          ));
        }
      }
    }
    return chunks;
  }

  Future<void> _updateMediaNotification() async {
    if (!_isVisible) {
      await NotificationService.instance.cancelTtsMediaNotification();
      return;
    }
    final title = _currentChapterTitle ?? _mangaTitle ?? 'Audiobook Reader';
    final current = (_chunkIndex + 1).clamp(1, max(1, _chunks.length));
    final total = max(1, _chunks.length);
    final statusText = _isPlaying ? 'Đang đọc' : 'Tạm dừng';
    final speedText = '${_rate.toStringAsFixed(1)}x';
    final body = '$statusText • Câu $current/$total • Tốc độ $speedText';

    await NotificationService.instance.showTtsMediaNotification(
      title: title,
      body: body,
      isPlaying: _isPlaying,
      currentChunk: _chunkIndex,
      totalChunks: _chunks.length,
    );
  }

  Future<void> startReading({
    required String mangaId,
    required String chapterId,
    required String chapterTitle,
    String? mangaTitle,
    String? coverUrl,
    String? epubPath,
    int chapterIndex = 0,
    required String text,
    List<String>? blockTexts,
    int startChunkIndex = 0,
  }) async {
    final chunks = splitTtsChunks(
      text,
      blockTexts: blockTexts,
      mangaId: mangaId,
    );
    if (chunks.isEmpty) return;

    _currentMangaId = mangaId;
    _currentChapterId = chapterId;
    _currentChapterTitle = chapterTitle;
    _mangaTitle = mangaTitle ?? _mangaTitle;
    _coverUrl = coverUrl ?? _coverUrl;
    _epubPath = epubPath ?? _epubPath;
    _currentChapterIndex = chapterIndex;
    _lastFullText = text;
    _lastBlockTexts = blockTexts;

    _chunks = chunks;
    _chunkIndex = startChunkIndex.clamp(0, chunks.length - 1).toInt();
    _isVisible = true;

    await _applySettings();
    _isPlaying = true;
    WakelockPlus.enable();
    await _updateMediaNotification();
    notifyListeners();

    await _speakCurrentChunk();
  }

  bool _isSpeaking = false;

  Future<void> _speakCurrentChunk() async {
    if (!_isPlaying || _chunks.isEmpty) return;
    if (_chunkIndex < 0 || _chunkIndex >= _chunks.length) return;
    final chunk = _chunks[_chunkIndex].text.trim();
    if (chunk.isEmpty) {
      await _playNextChunk();
      return;
    }
    _currentWordStart = null;
    _currentWordEnd = null;
    _currentWord = null;
    WakelockPlus.enable();
    await _updateMediaNotification();
    // Báo cho UI highlight câu mới và tự động cuộn đến câu ĐỒNG THỜI khi câu bắt đầu phát!
    notifyListeners();

    if (_isSpeaking) {
      await _tts.stop();
    }
    _isSpeaking = true;
    try {
      await _tts.speak(chunk);
    } finally {
      _isSpeaking = false;
    }
  }

  Future<void> _playNextChunk() async {
    if (!_isPlaying || _chunks.isEmpty) return;
    _chunkIndex++;
    if (_chunkIndex >= _chunks.length) {
      if (_stopAtEndOfChapter) {
        _stopAtEndOfChapter = false;
        await stop();
        return;
      }

      if (onNextChapterRequested != null) {
        final handled = await onNextChapterRequested!();
        if (handled) return;
      }

      // Tự động sang chương kế tiếp khi nghe Audiobook ngầm hoặc ngoài màn hình khóa
      if (_epubPath != null && File(_epubPath!).existsSync()) {
        final advanced = await _autoAdvanceToNextEpubChapter();
        if (advanced) return;
      }

      // Đã đọc hết toàn bộ sách -> Dừng phát sạch sẽ
      await stop();
      return;
    }

    // Nghỉ nhẹ 100ms: Android audio buffer kịp flush, chống nuốt từ đầu câu tiếp theo và ngắt câu tự nhiên
    await Future.delayed(const Duration(milliseconds: 100));
    if (!_isPlaying) return;

    await _speakCurrentChunk();
  }

  Future<void> seekToChunk(int index) async {
    if (_chunks.isEmpty) return;
    final target = index.clamp(0, _chunks.length - 1);
    if (_chunkIndex == target && _isPlaying) return;
    _chunkIndex = target;
    _currentWordStart = null;
    _currentWordEnd = null;
    _currentWord = null;
    wordProgressNotifier.value = (start: null, end: null);
    await _tts.stop();
    if (_isPlaying) {
      await _speakCurrentChunk();
    } else {
      await _updateMediaNotification();
      notifyListeners();
    }
  }

  Future<bool> _autoAdvanceToNextEpubChapter() async {
    try {
      final path = _epubPath!;
      final parsedIndex = await compute(
        EpubParser.parseIndex,
        EpubParseArgs(path: path, title: _mangaTitle ?? 'Truyện chữ'),
      );
      final nextIndex = _currentChapterIndex + 1;
      if (nextIndex >= parsedIndex.chapters.length) {
        return false;
      }

      final nextRef = parsedIndex.chapters[nextIndex];
      final nextChapter = await compute(
        EpubParser.parseChapter,
        EpubChapterParseArgs(path: path, chapter: nextRef),
      );
      final rawText = EpubParser.formatChapterText(nextChapter);
      if (rawText.trim().isEmpty) return false;
      final nextText = GlossaryService.instance.applyReplacements(rawText, mangaId: _currentMangaId);

      // Giữ nguyên full block index: divider → empty string (skip bởi splitTtsChunks),
      // nhưng bIdx vẫn khớp với _blockKeys trong widget (full index).
      final nextBlocks = nextChapter.blocks
          .map((b) => (b.text != null && b.type != EpubBlockType.divider) ? b.text! : '')
          .toList();

      _currentChapterIndex = nextIndex;
      _currentChapterId = 'chap_$nextIndex';
      _currentChapterTitle = nextChapter.title;
      _lastFullText = nextText;
      _lastBlockTexts = nextBlocks;
      _chunks = splitTtsChunks(
        nextText,
        blockTexts: nextBlocks,
        mangaId: _currentMangaId,
      );
      _chunkIndex = 0;

      if (_currentMangaId != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'epub_flutter_progress_$_currentMangaId',
            jsonEncode({
              'chapter': nextIndex,
              'page': 0,
              'offset': 0.0,
              'blockIndex': 0,
            }),
          );
        } catch (_) {}
      }

      await _updateMediaNotification();
      notifyListeners();
      await _speakCurrentChunk();
      return true;
    } catch (e) {
      debugPrint('TTS Auto next chapter error: $e');
      return false;
    }
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> pause() async {
    _isPlaying = false;
    _currentWordStart = null;
    _currentWordEnd = null;
    _currentWord = null;
    wordProgressNotifier.value = (start: null, end: null);
    WakelockPlus.disable();
    await _tts.stop();
    await _updateMediaNotification();
    notifyListeners();
  }

  Future<void> resume() async {
    if (_chunks.isEmpty && _lastFullText != null) {
      _chunks = splitTtsChunks(
        _lastFullText!,
        blockTexts: _lastBlockTexts,
        mangaId: _currentMangaId,
      );
    }
    if (_chunks.isEmpty) return;
    _isPlaying = true;
    _isVisible = true;
    WakelockPlus.enable();
    await _updateMediaNotification();
    notifyListeners();
    await _speakCurrentChunk();
  }

  Future<void> nextChunk() async {
    if (_chunkIndex < _chunks.length - 1) {
      await _tts.stop();
      _chunkIndex++;
      _currentWordStart = null;
      _currentWordEnd = null;
      _currentWord = null;
      wordProgressNotifier.value = (start: null, end: null);
      if (_isPlaying) {
        await _speakCurrentChunk();
      } else {
        await _updateMediaNotification();
        notifyListeners();
      }
    } else {
      // Đang ở đoạn cuối của chương -> Chuyển sang chương tiếp theo
      await _tts.stop();
      if (_stopAtEndOfChapter) {
        _stopAtEndOfChapter = false;
        await stop();
        return;
      }
      if (onNextChapterRequested != null) {
        final handled = await onNextChapterRequested!();
        if (handled) return;
      }
      final advanced = await _autoAdvanceToNextEpubChapter();
      if (!advanced) {
        await stop();
      }
    }
  }

  Future<void> prevChunk() async {
    if (_chunkIndex > 0) {
      await _tts.stop();
      _chunkIndex--;
      _currentWordStart = null;
      _currentWordEnd = null;
      _currentWord = null;
      wordProgressNotifier.value = (start: null, end: null);
      if (_isPlaying) {
        await _speakCurrentChunk();
      } else {
        await _updateMediaNotification();
        notifyListeners();
      }
    } else {
      // Đang ở đoạn đầu tiên của chương -> Chuyển về cuối chương trước nếu có
      await _tts.stop();
      if (onPrevChapterRequested != null) {
        final handled = await onPrevChapterRequested!();
        if (handled) return;
      }
      // Không lùi được nữa (ở đầu chương 1), phát lại câu đầu
      if (_isPlaying) {
        await _speakCurrentChunk();
      } else {
        await _updateMediaNotification();
        notifyListeners();
      }
    }
  }

  Future<void> stop() async {
    _isPlaying = false;
    _currentWordStart = null;
    _currentWordEnd = null;
    _currentWord = null;
    wordProgressNotifier.value = (start: null, end: null);
    WakelockPlus.disable();
    await _tts.stop();
    await _updateMediaNotification();
    notifyListeners();
  }

  Future<void> stopAndHide() async {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepMinutesRemaining = 0;
    _stopAtEndOfChapter = false;
    _isPlaying = false;
    _isVisible = false;
    _chunks = [];
    _chunkIndex = 0;
    _lastFullText = null;
    _lastBlockTexts = null;
    _currentWordStart = null;
    _currentWordEnd = null;
    _currentWord = null;
    wordProgressNotifier.value = (start: null, end: null);
    WakelockPlus.disable();
    await _tts.stop();
    await _updateMediaNotification();
    notifyListeners();
  }

  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _stopAtEndOfChapter = false;
    if (minutes <= 0) {
      _sleepMinutesRemaining = 0;
      notifyListeners();
      return;
    }

    _sleepMinutesRemaining = minutes;
    notifyListeners();

    _sleepTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _sleepMinutesRemaining--;
      if (_sleepMinutesRemaining <= 0) {
        timer.cancel();
        _sleepTimer = null;
        _sleepMinutesRemaining = 0;
        stop();
      }
      notifyListeners();
    });
  }

  static const List<double> availableSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

  Future<void> cycleSpeed() async {
    final currentIndex = availableSpeeds.indexWhere((s) => (s - _rate).abs() < 0.05);
    final nextIndex = currentIndex == -1 ? 2 : (currentIndex + 1) % availableSpeeds.length;
    await setRate(availableSpeeds[nextIndex], restartIfPlaying: true);
  }

  Future<void> setRate(double value, {bool restartIfPlaying = false}) async {
    _rate = value;
    await _tts.setSpeechRate(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('global_tts_rate', value);
    await _updateMediaNotification();
    notifyListeners();
    if (restartIfPlaying && _isPlaying) {
      await _speakCurrentChunk();
    }
  }

  Future<void> setPitch(double value, {bool restartIfPlaying = false}) async {
    _pitch = value;
    await _tts.setPitch(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('global_tts_pitch', value);
    notifyListeners();
    if (restartIfPlaying && _isPlaying) {
      await _speakCurrentChunk();
    }
  }

  Future<void> setLanguage(String lang) async {
    _lang = lang;
    await _tts.setLanguage(lang);
    await _loadVoicesForLang(lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('global_tts_lang', lang);
    notifyListeners();
    if (_isPlaying) {
      await _speakCurrentChunk();
    }
  }

  Future<void> setVoice(Map<String, String> voice) async {
    _selectedVoice = voice;
    await _tts.setVoice({
      'name': voice['name']!,
      'locale': voice['locale']!,
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('global_tts_voice_name', voice['name'] ?? '');
      await prefs.setString('global_tts_voice_locale', voice['locale'] ?? '');
    } catch (_) {}
    notifyListeners();
    if (_isPlaying) {
      await _speakCurrentChunk();
    }
  }

  Future<void> _applySettings() async {
    await _tts.setLanguage(_lang);
    await _tts.setSpeechRate(_rate);
    await _tts.setPitch(_pitch);
    if (_selectedVoice != null) {
      await _tts.setVoice({
        'name': _selectedVoice!['name']!,
        'locale': _selectedVoice!['locale']!,
      });
    }
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _tts.stop();
    super.dispose();
  }
}
