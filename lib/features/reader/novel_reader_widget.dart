import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper.dart';
import '../../data/models.dart';

/// Widget đọc truyện chữ (EPUB) với TTS tích hợp.
/// Nhận [epubBytes] từ ReaderProvider và render bằng flutter_epub_viewer.
class NovelReaderWidget extends StatefulWidget {
  final Uint8List epubBytes;
  final String title;

  const NovelReaderWidget({
    super.key,
    required this.epubBytes,
    required this.title,
  });

  @override
  State<NovelReaderWidget> createState() => _NovelReaderWidgetState();
}

class _NovelReaderWidgetState extends State<NovelReaderWidget> {
  final _epubController = EpubController();
  final _tts = FlutterTts();

  bool _isTtsPlaying = false;
  bool _isEpubReady = false;
  bool _showTtsPanel = false;
  String? _epubPath;
  int _fontSize = 18;
  int _viewerRevision = 0;

  // Cài đặt TTS
  double _ttsRate = 0.5;
  double _ttsPitch = 1.0;
  String _ttsLang = 'vi-VN'; // Ngôn ngữ mặc định

  static const _supportedLangs = [
    ('vi-VN', 'Tiếng Việt'),
    ('en-US', 'English'),
    ('ja-JP', 'Nhật'),
    ('zh-CN', 'Trung'),
    ('ko-KR', 'Hàn'),
  ];

  // Các tính năng VIP PRO
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<EpubChapter> _chapters = [];

  List<Map<String, String>> _availableVoices = [];
  Map<String, String>? _selectedVoice;

  Timer? _sleepTimer;
  int _sleepTimeMinutes = 0;

  int _bgColor = 0xFF1C1C1E;
  int _textColor = 0xFFFFFFFF;
  int _flowType = 0; // 0: Paginated, 1: Scrolled
  String? _initialCfi;
  String? _currentCfi;
  bool _isCurrentCfiBookmarked = false;

  String get _bookKey => widget.title
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  int get _stableTitleHash => widget.title.codeUnits.fold<int>(
    0,
    (hash, codeUnit) => (hash * 31 + codeUnit) & 0x7fffffff,
  );

  String get _resolvedBookKey =>
      _bookKey.isEmpty ? _stableTitleHash.toString() : _bookKey;

  String get _mangaId => 'epub_$_resolvedBookKey';

  String get _chapterId => 'epub_${_resolvedBookKey}_chapter';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    final progress = await DatabaseHelper.instance.getReaderProgress(_mangaId);
    if (!mounted) return;
    _initialCfi =
        progress?.epubCfi ?? prefs.getString('epub_cfi_${widget.title}');
    _currentCfi = _initialCfi;
    await _refreshCurrentCfiBookmark();
    await _saveEpubToTemp();
    await _loadTtsSettings();
  }

  /// Ghi EPUB bytes ra file tạm để EpubViewer đọc theo đường dẫn.
  Future<void> _saveEpubToTemp() async {
    try {
      final dir = await getTemporaryDirectory();
      final safeTitle = widget.title.replaceAll(RegExp(r'[^\w\s]'), '_');
      final file = File('${dir.path}/$safeTitle.epub');
      await file.writeAsBytes(widget.epubBytes);
      if (mounted) {
        setState(() {
          _epubPath = file.path;
          _isEpubReady = true;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi ghi EPUB tạm: $e');
    }
  }

  Future<void> _loadTtsSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'tts_book_$_resolvedBookKey';
    if (!mounted) return;
    setState(() {
      _ttsRate =
          prefs.getDouble('${prefix}_rate') ?? prefs.getDouble('tts_rate') ?? 0.5;
      _ttsPitch =
          prefs.getDouble('${prefix}_pitch') ??
          prefs.getDouble('tts_pitch') ??
          1.0;
      _ttsLang =
          prefs.getString('${prefix}_lang') ??
          prefs.getString('tts_lang') ??
          'vi-VN';
      _fontSize = prefs.getInt('epub_font_size') ?? 18;
      _bgColor = prefs.getInt('epub_bg_color') ?? 0xFF1C1C1E;
      _textColor = prefs.getInt('epub_text_color') ?? 0xFFFFFFFF;
      _flowType = prefs.getInt('epub_flow_type') ?? 0;
    });
    await _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage(_ttsLang);
    await _tts.setSpeechRate(_ttsRate);
    await _tts.setPitch(_ttsPitch);

    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isTtsPlaying = false);
    });

    _tts.setErrorHandler((msg) {
      debugPrint('TTS Error: $msg');
      if (mounted) setState(() => _isTtsPlaying = false);
    });

    _loadVoicesForLang(_ttsLang);
  }

  Future<void> _loadVoicesForLang(String lang) async {
    try {
      final voices = await _tts.getVoices;
      if (voices != null && mounted) {
        final List<Map<String, String>> parsed = [];
        for (final v in voices) {
          if (v is Map) {
            final locale = v['locale']?.toString() ?? '';
            final name = v['name']?.toString() ?? '';
            if (locale.toLowerCase().contains(lang.toLowerCase()) ||
                lang.toLowerCase().contains(locale.toLowerCase())) {
              parsed.add({'name': name, 'locale': locale});
            }
          }
        }
        setState(() {
          _availableVoices = parsed;
          _selectedVoice = null;
        });

        if (parsed.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          if (!mounted) return;
          final savedName =
              prefs.getString('tts_book_${_resolvedBookKey}_voice_name_$lang') ??
              prefs.getString('tts_voice_name_$lang');
          if (savedName != null) {
            _selectedVoice = parsed
                .where((v) => v['name'] == savedName)
                .firstOrNull;
          }
          _selectedVoice ??= parsed.first;
          await _tts.setVoice({
            "name": _selectedVoice!['name']!,
            "locale": _selectedVoice!['locale']!,
          });
          if (mounted) setState(() {});
        }
      }
    } catch (e) {
      debugPrint('TTS getVoices error: $e');
    }
  }

  Future<void> _setTtsVoice(Map<String, String> voice) async {
    if (!mounted) return;
    setState(() => _selectedVoice = voice);
    await _tts.setVoice({"name": voice['name']!, "locale": voice['locale']!});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'tts_book_${_resolvedBookKey}_voice_name_$_ttsLang',
      voice['name']!,
    );
  }

  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    setState(() => _sleepTimeMinutes = minutes);
    if (minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        _tts.stop();
        if (mounted) {
          setState(() {
            _isTtsPlaying = false;
            _sleepTimeMinutes = 0;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã tắt đọc truyện theo hẹn giờ ngủ.'),
            ),
          );
        }
      });
    }
  }

  Future<void> _setBgColor(int color) async {
    if (!mounted) return;
    setState(() => _bgColor = color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('epub_bg_color', color);
    await _applyEpubTheme();
  }

  Future<void> _setTextColor(int color) async {
    if (!mounted) return;
    setState(() => _textColor = color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('epub_text_color', color);
    await _applyEpubTheme();
  }

  String _cssColor(int color) =>
      '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  EpubTheme? _cachedEpubTheme;
  int _lastThemeBg = 0;
  int _lastThemeFg = 0;

  EpubTheme _buildEpubTheme() {
    if (_cachedEpubTheme != null && _lastThemeBg == _bgColor && _lastThemeFg == _textColor) {
      return _cachedEpubTheme!;
    }
    
    final bg = _cssColor(_bgColor);
    final fg = _cssColor(_textColor);
    _lastThemeBg = _bgColor;
    _lastThemeFg = _textColor;
    
    _cachedEpubTheme = EpubTheme.custom(
      backgroundDecoration: BoxDecoration(color: Color(_bgColor)),
      foregroundColor: Color(_textColor),
      customCss: {
        'html': {
          'background': '$bg !important',
          'color': '$fg !important',
        },
        'body': {
          'background': '$bg !important',
          'color': '$fg !important',
          '-webkit-text-fill-color': '$fg !important',
        },
        'p, div, span, li, h1, h2, h3, h4, h5, h6': {
          'color': '$fg !important',
          '-webkit-text-fill-color': '$fg !important',
        },
      },
    );
    return _cachedEpubTheme!;
  }

  Future<void> _applyEpubTheme() async {
    try {
      await _epubController.updateTheme(theme: _buildEpubTheme());
    } catch (_) {
      // Controller có thể chưa sẵn sàng trong vài frame đầu. Bỏ qua ở đây để
      // tránh vòng reload liên tục; theme vẫn được truyền qua displaySettings.
    }
  }

  Future<void> _applyEpubFlow() async {
    // flutter_epub_viewer handles flow via EpubDisplaySettings now.
    // Manual css hacks break native epub.js scrolling.
    return;
  }

  Future<void> _setFontSize(int value) async {
    final next = value.clamp(12, 40);
    if (!mounted) return;
    setState(() => _fontSize = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('epub_font_size', next);
    try {
      await _epubController.setFontSize(fontSize: next.toDouble());
    } catch (_) {
      if (mounted) setState(() => _viewerRevision++);
    }
  }

  Future<void> _setFlowType(int value) async {
    final next = value == 1 ? 1 : 0;
    final cfiBeforeReload = _currentCfi ?? _initialCfi;
    if (!mounted) return;
    setState(() {
      _flowType = next;
      _initialCfi = cfiBeforeReload;
      _viewerRevision++;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('epub_flow_type', next);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _applyEpubFlow();
  }

  Future<void> _setTtsRate(double value) async {
    if (!mounted) return;
    setState(() => _ttsRate = value);
    await _tts.setSpeechRate(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('tts_book_${_resolvedBookKey}_rate', value);
  }

  Future<void> _setTtsPitch(double value) async {
    if (!mounted) return;
    setState(() => _ttsPitch = value);
    await _tts.setPitch(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('tts_book_${_resolvedBookKey}_pitch', value);
  }

  void _showColorSettings() {
    final bgColors = [
      0xFF1C1C1E,
      0xFFFFFFFF,
      0xFFF4ECD8,
      0xFF000000,
      0xFF112233,
    ];
    final textColors = [
      0xFFFFFFFF,
      0xFF000000,
      0xFF5B4636,
      0xFFDDDDDD,
      0xFFFFD700,
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2C2C2E),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Màu nền',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: bgColors
                        .map(
                          (color) => GestureDetector(
                            onTap: () {
                              _setBgColor(color);
                              setModalState(() {});
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Color(color),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _bgColor == color
                                      ? Colors.blueAccent
                                      : Colors.white24,
                                  width: _bgColor == color ? 3 : 1,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Màu chữ',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: textColors
                        .map(
                          (color) => GestureDetector(
                            onTap: () {
                              _setTextColor(color);
                              setModalState(() {});
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Color(color),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _textColor == color
                                      ? Colors.blueAccent
                                      : Colors.white24,
                                  width: _textColor == color ? 3 : 1,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _setTtsLang(String lang) async {
    if (!mounted) return;
    setState(() => _ttsLang = lang);
    await _tts.setLanguage(lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tts_book_${_resolvedBookKey}_lang', lang);
    await _loadVoicesForLang(lang);
  }

  Future<void> _saveEpubProgress(String cfi) async {
    final now = DateTime.now();
    await DatabaseHelper.instance.saveReaderProgress(
      ReaderProgress(
        mangaId: _mangaId,
        chapterId: _chapterId,
        pageIndex: 0,
        scrollOffset: 0,
        progressPercent: 0,
        epubCfi: cfi,
        updatedAt: now,
      ),
    );
  }

  Future<void> _jumpToChapter(EpubChapter chapter) async {
    Navigator.pop(context);
    final target = chapter.href.isNotEmpty ? chapter.href : chapter.id;
    if (target.isEmpty) return;

    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    try {
      _epubController.display(cfi: target);
      setState(() {
        _currentCfi = target;
        _initialCfi = target;
      });
    } catch (e) {
      debugPrint('EPUB chapter jump error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không mở được mục này trong EPUB')),
      );
    }
  }

  Future<void> _refreshCurrentCfiBookmark() async {
    final cfi = _currentCfi;
    if (cfi == null || cfi.isEmpty) {
      if (mounted) setState(() => _isCurrentCfiBookmarked = false);
      return;
    }

    final bookmarks = await DatabaseHelper.instance.getBookmarksForManga(
      _mangaId,
    );
    final isBookmarked = bookmarks.any(
      (bookmark) => bookmark.chapterId == _chapterId && bookmark.epubCfi == cfi,
    );
    if (mounted) setState(() => _isCurrentCfiBookmarked = isBookmarked);
  }

  Future<void> _toggleEpubBookmark() async {
    final cfi = _currentCfi ?? _initialCfi;
    if (cfi == null || cfi.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chua co vi tri EPUB de bookmark')),
      );
      return;
    }

    final bookmarks = await DatabaseHelper.instance.getBookmarksForManga(
      _mangaId,
    );
    final existing = bookmarks
        .where(
          (bookmark) =>
              bookmark.chapterId == _chapterId && bookmark.epubCfi == cfi,
        )
        .firstOrNull;

    if (existing != null) {
      await DatabaseHelper.instance.deleteBookmark(existing.id);
      if (!mounted) return;
      setState(() => _isCurrentCfiBookmarked = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Da bo bookmark EPUB')),
      );
      return;
    }

    final now = DateTime.now();
    await DatabaseHelper.instance.saveBookmark(
      ReaderBookmark(
        id: '$_mangaId-$_chapterId-${cfi.hashCode}',
        mangaId: _mangaId,
        chapterId: _chapterId,
        pageIndex: 0,
        scrollOffset: 0,
        epubCfi: cfi,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (!mounted) return;
    setState(() => _isCurrentCfiBookmarked = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Da them bookmark EPUB')),
    );
  }

  Future<void> _toggleTts() async {
    if (_isTtsPlaying) {
      await _tts.stop();
      setState(() => _isTtsPlaying = false);
    } else {
      try {
        // Trích xuất text từ trang hiện tại qua EPUB controller
        final res = await _epubController.extractCurrentPageText();
        final rawText = res.text;
        final textToRead = (rawText != null && rawText.isNotEmpty)
            ? rawText
            : 'Không thể đọc nội dung trang này';
        await _tts.speak(textToRead);
        setState(() => _isTtsPlaying = true);
      } catch (e) {
        debugPrint('TTS read error: $e');
        // Fallback: đọc tiêu đề chương
        await _tts.speak(widget.title);
        setState(() => _isTtsPlaying = true);
      }
    }
  }

  void _showReaderSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2C2C2E),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Cài đặt đọc',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.text_fields, color: Colors.white54),
                        const SizedBox(width: 12),
                        Text(
                          'Cỡ chữ $_fontSize',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                    Slider(
                      value: _fontSize.toDouble(),
                      min: 12,
                      max: 40,
                      divisions: 14,
                      activeColor: Colors.blueAccent,
                      onChanged: (value) async {
                        await _setFontSize(value.round());
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          icon: Icon(Icons.swap_horiz),
                          label: Text('Ngang'),
                        ),
                        ButtonSegment(
                          value: 1,
                          icon: Icon(Icons.swap_vert),
                          label: Text('Dọc'),
                        ),
                      ],
                      selected: {_flowType},
                      onSelectionChanged: (values) async {
                        await _setFlowType(values.first);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 20),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showColorSettings();
                      },
                      icon: const Icon(Icons.palette),
                      label: const Text('Màu nền và màu chữ'),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _showTtsPanel,
                      onChanged: (value) {
                        setState(() => _showTtsPanel = value);
                        setModalState(() {});
                      },
                      title: const Text(
                        'Mở bảng TTS',
                        style: TextStyle(color: Colors.white),
                      ),
                      secondary: const Icon(
                        Icons.record_voice_over,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _tts.stop();
    _sleepTimer?.cancel();
    // Xóa file EPUB tạm khi widget bị dispose — tránh temp dir đầy sau nhiều lần mở truyện
    if (_epubPath != null) {
      try {
        final f = File(_epubPath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  EpubDisplaySettings? _cachedDisplaySettings;
  int _lastFontSize = 0;

  EpubDisplaySettings _buildDisplaySettings() {
    final currentTheme = _buildEpubTheme();
    final flow = _flowType == 1 ? EpubFlow.scrolled : EpubFlow.paginated;
    final snap = _flowType == 0;
    
    if (_cachedDisplaySettings != null && 
        _lastFontSize == _fontSize && 
        _cachedEpubTheme == currentTheme &&
        _cachedDisplaySettings!.flow == flow) {
      return _cachedDisplaySettings!;
    }
    _lastFontSize = _fontSize;
    _cachedDisplaySettings = EpubDisplaySettings(
      fontSize: _fontSize,
      flow: flow,
      allowScriptedContent: true,
      snap: snap,
      theme: currentTheme,
    );
    return _cachedDisplaySettings!;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEpubReady || _epubPath == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.redAccent),
              SizedBox(height: 12),
              Text(
                'Đang mở file truyện...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Color(_bgColor),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: _showTtsPanel ? 220 : 72),
        child: FloatingActionButton.small(
          heroTag: 'epub-reader-settings-${widget.title}',
          backgroundColor: const Color(0xFF2C2C2E),
          foregroundColor: Colors.white,
          tooltip: 'Cài đặt đọc',
          onPressed: _showReaderSettings,
          child: const Icon(Icons.tune),
        ),
      ),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2C2C2E),
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 16, color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book),
            tooltip: 'Mục lục',
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
          IconButton(
            icon: Icon(
              _isCurrentCfiBookmarked
                  ? Icons.bookmark
                  : Icons.bookmark_border,
              color: _isCurrentCfiBookmarked ? Colors.amber : Colors.white,
            ),
            tooltip: _isCurrentCfiBookmarked
                ? 'Bỏ bookmark EPUB'
                : 'Bookmark vị trí EPUB',
            onPressed: _toggleEpubBookmark,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Cài đặt đọc',
            onPressed: _showReaderSettings,
          ),
          const SizedBox(width: 4),
        ],
      ),
      endDrawer: Drawer(
        backgroundColor: const Color(0xFF1C1C1E),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.only(top: 40, bottom: 16),
              color: const Color(0xFF2C2C2E),
              width: double.infinity,
              child: const Text(
                'Mục Lục',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: _chapters.isEmpty
                  ? const Center(
                      child: Text(
                        'Đang tải...',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _chapters.length,
                      itemBuilder: (context, index) {
                        final ch = _chapters[index];
                        return ListTile(
                          title: Text(
                            ch.title,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          onTap: () {
                            _jumpToChapter(ch);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // ── EPUB Viewer ──────────────────────────────────────────
          EpubViewer(
            key: ValueKey('epub-${_flowType}_$_viewerRevision'),
            epubSource: EpubSource.fromFile(File(_epubPath!)),
            epubController: _epubController,
            initialCfi: _initialCfi,
            displaySettings: _buildDisplaySettings(),
            onEpubLoaded: () async {
              await _applyEpubTheme();
              await _applyEpubFlow();
            },
            onChaptersLoaded: (chapters) {
              debugPrint('📚 EPUB loaded: ${chapters.length} chapters');
              if (mounted) setState(() => _chapters = chapters);
            },
            onRelocated: (loc) async {
              final startCfi = loc.startCfi;
              _currentCfi = startCfi;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('epub_cfi_${widget.title}', startCfi);
              await _saveEpubProgress(startCfi);
              await _refreshCurrentCfiBookmark();
            },
          ),

          // ── TTS Control Bar (bottom) ─────────────────────────────
          Positioned(left: 0, right: 0, bottom: 0, child: _buildTtsBar()),
        ],
      ),
    );
  }

  Widget _buildTtsSlider({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.white54),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: color,
          inactiveColor: Colors.white12,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildTtsBar() {
    if (!_showTtsPanel) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _flowType == 1 ? 'Cuộn dọc' : 'Vuốt ngang',
                      icon: Icon(
                        _flowType == 1 ? Icons.swap_vert : Icons.swap_horiz,
                        color: Colors.white,
                      ),
                      onPressed: () => _setFlowType(_flowType == 1 ? 0 : 1),
                    ),
                    _TtsButton(
                      icon: _isTtsPlaying
                          ? Icons.stop_rounded
                          : Icons.volume_up_rounded,
                      label: _isTtsPlaying ? 'Dừng' : 'Đọc',
                      color: _isTtsPlaying
                          ? Colors.redAccent
                          : Colors.blueAccent,
                      onTap: _toggleTts,
                    ),
                    IconButton(
                      tooltip: 'Mở TTS',
                      icon: const Icon(
                        Icons.keyboard_arrow_up,
                        color: Colors.white,
                      ),
                      onPressed: () => setState(() => _showTtsPanel = true),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _showTtsPanel = false),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    _flowType == 1 ? Icons.swap_vert : Icons.swap_horiz,
                    color: Colors.white,
                  ),
                  tooltip: _flowType == 1
                      ? 'Chế độ cuộn dọc'
                      : 'Chế độ vuốt ngang',
                  onPressed: () => _setFlowType(_flowType == 1 ? 0 : 1),
                ),
                const SizedBox(width: 8),
                _TtsButton(
                  icon: _isTtsPlaying
                      ? Icons.stop_rounded
                      : Icons.volume_up_rounded,
                  label: _isTtsPlaying ? 'Dừng' : 'Đọc',
                  color: _isTtsPlaying ? Colors.redAccent : Colors.blueAccent,
                  onTap: _toggleTts,
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'Ngôn ngữ',
                  icon: const Icon(Icons.language, color: Colors.white54),
                  color: const Color(0xFF3A3A3C),
                  onSelected: _setTtsLang,
                  itemBuilder: (_) => _supportedLangs
                      .map(
                        (entry) => PopupMenuItem<String>(
                          value: entry.$1,
                          child: Row(
                            children: [
                              Text(entry.$2),
                              if (_ttsLang == entry.$1) ...const [
                                SizedBox(width: 8),
                                Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.blueAccent,
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildTtsSlider(
              icon: Icons.speed,
              label: 'Tốc độ: ${_ttsRate.toStringAsFixed(1)}x',
              value: _ttsRate,
              min: 0.2,
              max: 1.0,
              divisions: 8,
              color: Colors.blueAccent,
              onChanged: _setTtsRate,
            ),
            _buildTtsSlider(
              icon: Icons.music_note,
              label: 'Cao độ: ${_ttsPitch.toStringAsFixed(1)}',
              value: _ttsPitch,
              min: 0.5,
              max: 2.0,
              divisions: 15,
              color: Colors.purpleAccent,
              onChanged: _setTtsPitch,
            ),

            // Dòng thứ 2: Chọn Giọng Đọc và Hẹn Giờ Ngủ
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A3A3C),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Map<String, String>>(
                        isExpanded: true,
                        dropdownColor: const Color(0xFF3A3A3C),
                        hint: const Text(
                          'Chọn giọng đọc',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        value: _selectedVoice,
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.white54,
                        ),
                        items: _availableVoices.map((v) {
                          return DropdownMenuItem<Map<String, String>>(
                            value: v,
                            child: Text(
                              v['name'] ?? 'Giọng mặc định',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) _setTtsVoice(val);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: PopupMenuButton<int>(
                    tooltip: 'Hẹn giờ tắt',
                    // Keep the visible trigger near tooltip for readability.
                    // ignore: sort_child_properties_last
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _sleepTimeMinutes > 0
                            ? Colors.redAccent.withValues(alpha: 0.2)
                            : const Color(0xFF3A3A3C),
                        borderRadius: BorderRadius.circular(8),
                        border: _sleepTimeMinutes > 0
                            ? Border.all(color: Colors.redAccent)
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.snooze,
                            size: 16,
                            color: _sleepTimeMinutes > 0
                                ? Colors.redAccent
                                : Colors.white54,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _sleepTimeMinutes > 0
                                ? '$_sleepTimeMinutes p'
                                : 'Tắt',
                            style: TextStyle(
                              color: _sleepTimeMinutes > 0
                                  ? Colors.redAccent
                                  : Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    color: const Color(0xFF3A3A3C),
                    onSelected: _setSleepTimer,
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 0,
                        child: Text(
                          'Không hẹn giờ',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 15,
                        child: Text(
                          '15 phút',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 30,
                        child: Text(
                          '30 phút',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 45,
                        child: Text(
                          '45 phút',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 60,
                        child: Text(
                          '60 phút',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Nút điều khiển TTS nhỏ gọn.
class _TtsButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _TtsButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
