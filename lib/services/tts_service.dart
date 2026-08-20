import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TtsService extends ChangeNotifier {
  static final TtsService instance = TtsService._internal();
  TtsService._internal() {
    _initTts();
  }

  final FlutterTts _tts = FlutterTts();

  String? _currentMangaId;
  String? _currentChapterId;
  String? _currentChapterTitle;
  String? _mangaTitle;
  String? _coverUrl;
  String? _epubPath;

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
  bool get isPlaying => _isPlaying;
  bool get isVisible => _isVisible;
  double get rate => _rate;
  double get pitch => _pitch;
  String get lang => _lang;
  List<Map<String, String>> get availableVoices => _availableVoices;
  Map<String, String>? get selectedVoice => _selectedVoice;
  int get chunkIndex => _chunkIndex;
  int get totalChunks => _chunks.length;
  double get progress => _chunks.isEmpty ? 0.0 : (_chunkIndex + 1) / _chunks.length;
  int get sleepMinutesRemaining => _sleepMinutesRemaining;

  Future<void> _initTts() async {
    _tts.setCompletionHandler(() {
      _playNextChunk();
    });

    _tts.setErrorHandler((msg) {
      debugPrint('TTS Error: $msg');
      _isPlaying = false;
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
      if (voices == null) return;
      final parsed = <Map<String, String>>[];
      for (final voice in voices) {
        if (voice is! Map) continue;
        final locale = voice['locale']?.toString() ?? '';
        final name = voice['name']?.toString() ?? '';
        if (locale.toLowerCase().contains(lang.toLowerCase()) ||
            lang.toLowerCase().contains(locale.toLowerCase())) {
          parsed.add({'name': name, 'locale': locale});
        }
      }
      _availableVoices = parsed;
      _selectedVoice = parsed.firstOrNull;
      if (_selectedVoice != null) {
        await _tts.setVoice({
          'name': _selectedVoice!['name']!,
          'locale': _selectedVoice!['locale']!,
        });
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

  Future<void> startReading({
    required String mangaId,
    required String chapterId,
    required String chapterTitle,
    String? mangaTitle,
    String? coverUrl,
    String? epubPath,
    required String text,
    int startChunkIndex = 0,
  }) async {
    final chunks = splitTtsChunks(text);
    if (chunks.isEmpty) return;

    _currentMangaId = mangaId;
    _currentChapterId = chapterId;
    _currentChapterTitle = chapterTitle;
    _mangaTitle = mangaTitle ?? _mangaTitle;
    _coverUrl = coverUrl ?? _coverUrl;
    _epubPath = epubPath ?? _epubPath;
    _lastFullText = text;

    _chunks = chunks;
    _chunkIndex = startChunkIndex.clamp(0, chunks.length - 1).toInt();
    _isVisible = true;

    await _applySettings();
    _isPlaying = true;
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
    await _tts.speak(chunk);
    notifyListeners();
  }

  Future<void> _playNextChunk() async {
    if (!_isPlaying || _chunks.isEmpty) return;
    _chunkIndex++;
    if (_chunkIndex >= _chunks.length) {
      _isPlaying = false;
      notifyListeners();
      if (onNextChapterRequested != null) {
        await onNextChapterRequested!();
      }
      return;
    }
    await _speakCurrentChunk();
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
    await _tts.stop();
    notifyListeners();
  }

  Future<void> resume() async {
    if (_chunks.isEmpty && _lastFullText != null) {
      _chunks = splitTtsChunks(_lastFullText!);
    }
    if (_chunks.isEmpty) return;
    _isPlaying = true;
    _isVisible = true;
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
        notifyListeners();
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
        notifyListeners();
      }
    }
  }

  Future<void> stop() async {
    _isPlaying = false;
    await _tts.stop();
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
    await _tts.stop();
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
