import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../features/reader/epub/epub_parser.dart';
import 'notification_service.dart';
import 'glossary_service.dart';

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

  List<String> _chunks = [];
  int _chunkIndex = 0;
  String? _lastFullText;

  Timer? _sleepTimer;
  int _sleepMinutesRemaining = 0;

  Future<void> Function()? onNextChapterRequested;
  Future<void> Function()? onPrevChapterRequested;

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
  String? get currentChunkText =>
      (_chunks.isNotEmpty && _chunkIndex >= 0 && _chunkIndex < _chunks.length)
          ? _chunks[_chunkIndex]
          : null;
  double get progress => _chunks.isEmpty ? 0.0 : (_chunkIndex + 1) / _chunks.length;
  int get sleepMinutesRemaining => _sleepMinutesRemaining;

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
    _tts.setCompletionHandler(() {
      _playNextChunk();
    });

    _tts.setErrorHandler((msg) {
      debugPrint('TTS Error: $msg');
      _isPlaying = false;
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

  List<String> splitTtsChunks(String text) {
    const maxChars = 2800;
    final source = text
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (source.isEmpty) return const [];

    final chunks = <String>[];
    final buffer = StringBuffer();
    final pieces = source.split(RegExp(r'(?<=[.!?…。！？])\s+|\n\s*\n'));
    for (final rawPiece in pieces) {
      final piece = rawPiece.trim();
      if (piece.isEmpty) continue;
      if (piece.length > maxChars) {
        if (buffer.isNotEmpty) {
          chunks.add(buffer.toString().trim());
          buffer.clear();
        }
        for (var i = 0; i < piece.length; i += maxChars) {
          chunks.add(piece.substring(i, min(i + maxChars, piece.length)));
        }
        continue;
      }
      if (buffer.length + piece.length + 1 > maxChars && buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
      buffer.writeln(piece);
    }
    if (buffer.toString().trim().isNotEmpty) {
      chunks.add(buffer.toString().trim());
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
    final body = '$statusText • Đoạn $current/$total • Tốc độ $speedText';

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
    int startChunkIndex = 0,
  }) async {
    final processedText = GlossaryService.instance.applyReplacements(text, mangaId: mangaId);
    final chunks = splitTtsChunks(processedText);
    if (chunks.isEmpty) return;

    _currentMangaId = mangaId;
    _currentChapterId = chapterId;
    _currentChapterTitle = chapterTitle;
    _mangaTitle = mangaTitle ?? _mangaTitle;
    _coverUrl = coverUrl ?? _coverUrl;
    _epubPath = epubPath ?? _epubPath;
    _currentChapterIndex = chapterIndex;
    _lastFullText = processedText;

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

  Future<void> _speakCurrentChunk() async {
    if (!_isPlaying || _chunks.isEmpty) return;
    final chunk = _chunks[_chunkIndex].trim();
    if (chunk.isEmpty) {
      await _playNextChunk();
      return;
    }
    WakelockPlus.enable();
    await _updateMediaNotification();
    await _tts.speak(chunk);
    notifyListeners();
  }

  Future<void> _playNextChunk() async {
    if (!_isPlaying || _chunks.isEmpty) return;
    _chunkIndex++;
    if (_chunkIndex >= _chunks.length) {
      if (onNextChapterRequested != null) {
        await onNextChapterRequested!();
        return;
      }

      // Tự động sang chương kế tiếp khi nghe Audiobook ngầm hoặc ngoài màn hình khóa
      if (_epubPath != null && File(_epubPath!).existsSync()) {
        final advanced = await _autoAdvanceToNextEpubChapter();
        if (advanced) return;
      }

      _isPlaying = false;
      WakelockPlus.disable();
      await _updateMediaNotification();
      notifyListeners();
      return;
    }
    await _speakCurrentChunk();
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

      _currentChapterIndex = nextIndex;
      _currentChapterId = 'chap_$nextIndex';
      _currentChapterTitle = nextChapter.title;
      _lastFullText = nextText;
      _chunks = splitTtsChunks(nextText);
      _chunkIndex = 0;

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
    WakelockPlus.disable();
    await _tts.stop();
    await _updateMediaNotification();
    notifyListeners();
  }

  Future<void> resume() async {
    if (_chunks.isEmpty && _lastFullText != null) {
      _chunks = splitTtsChunks(_lastFullText!);
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
      if (_isPlaying) {
        await _speakCurrentChunk();
      } else {
        await _updateMediaNotification();
        notifyListeners();
      }
    } else {
      // Đang ở đoạn cuối của chương -> Chuyển sang chương tiếp theo
      await _tts.stop();
      final advanced = await _autoAdvanceToNextEpubChapter();
      if (!advanced && onNextChapterRequested != null) {
        onNextChapterRequested!();
      }
    }
  }

  Future<void> prevChunk() async {
    if (_chunkIndex > 0) {
      await _tts.stop();
      _chunkIndex--;
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
    WakelockPlus.disable();
    await _tts.stop();
    await _updateMediaNotification();
    notifyListeners();
  }

  Future<void> stopAndHide() async {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepMinutesRemaining = 0;
    _isPlaying = false;
    _isVisible = false;
    _chunks = [];
    _chunkIndex = 0;
    _lastFullText = null;
    WakelockPlus.disable();
    await _tts.stop();
    await _updateMediaNotification();
    notifyListeners();
  }

  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
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

  static const List<double> availableSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  Future<void> cycleSpeed() async {
    final currentIndex = availableSpeeds.indexWhere((s) => (s - _rate).abs() < 0.05);
    final nextIndex = currentIndex == -1 ? 2 : (currentIndex + 1) % availableSpeeds.length;
    await setRate(availableSpeeds[nextIndex]);
  }

  Future<void> setRate(double value) async {
    _rate = value;
    await _tts.setSpeechRate(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('global_tts_rate', value);
    await _updateMediaNotification();
    notifyListeners();
  }

  Future<void> setPitch(double value) async {
    _pitch = value;
    await _tts.setPitch(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('global_tts_pitch', value);
    notifyListeners();
  }

  Future<void> setLanguage(String lang) async {
    _lang = lang;
    await _tts.setLanguage(lang);
    await _loadVoicesForLang(lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('global_tts_lang', lang);
    notifyListeners();
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
}
