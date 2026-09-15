import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quy tắc thay thế từ ngữ / thuật ngữ trong truyện chữ & TTS
class GlossaryRule {
  final String id;
  final String from;
  final String to;
  final String? mangaId; // null => Global (toàn bộ app), non-null => chỉ áp dụng cho bộ truyện này
  final bool isEnabled;
  final DateTime createdAt;

  const GlossaryRule({
    required this.id,
    required this.from,
    required this.to,
    this.mangaId,
    this.isEnabled = true,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'from': from,
        'to': to,
        'mangaId': mangaId,
        'isEnabled': isEnabled,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory GlossaryRule.fromMap(Map<String, dynamic> map) => GlossaryRule(
        id: map['id']?.toString() ?? '',
        from: map['from']?.toString() ?? '',
        to: map['to']?.toString() ?? '',
        mangaId: map['mangaId']?.toString(),
        isEnabled: map['isEnabled'] == true || map['isEnabled'] == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          map['createdAt'] is int
              ? map['createdAt'] as int
              : int.tryParse(map['createdAt']?.toString() ?? '') ?? 0,
        ),
      );
}

/// Dịch vụ quản lý từ điển & thay thế từ ngữ hàng loạt
class GlossaryService extends ChangeNotifier {
  static final GlossaryService instance = GlossaryService._internal();
  GlossaryService._internal() {
    _loadRules();
  }

  static const String _prefKey = 'novel_glossary_rules_v1';
  final List<GlossaryRule> _rules = [];

  List<GlossaryRule> get rules => List.unmodifiable(_rules);

  static String? normalizeMangaId(String? id) {
    if (id == null) return null;
    var clean = id.trim();
    if (clean.startsWith('LOCAL_NOVEL|')) {
      clean = clean.substring('LOCAL_NOVEL|'.length);
    }
    if (clean.startsWith('epub_')) {
      clean = clean.substring('epub_'.length);
    }
    return clean.isEmpty ? null : clean;
  }

  List<GlossaryRule> getRulesForManga(String? mangaId) {
    final norm = normalizeMangaId(mangaId);
    return _rules.where((r) => r.mangaId == null || normalizeMangaId(r.mangaId) == norm).toList();
  }

  Future<void> _loadRules() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefKey) ?? [];
      _rules.clear();
      for (final item in list) {
        try {
          final map = jsonDecode(item) as Map<String, dynamic>;
          _rules.add(GlossaryRule.fromMap(map));
        } catch (_) {}
      }
      _invalidateCache();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> addRule({
    required String from,
    required String to,
    String? mangaId,
  }) async {
    final cleanFrom = from.trim();
    final cleanTo = to.trim();
    if (cleanFrom.isEmpty) return;
    final normalizedMangaId = normalizeMangaId(mangaId);

    // Xóa quy tắc trùng 'from' và 'mangaId' nếu có từ trước
    _rules.removeWhere(
      (r) =>
          r.from.toLowerCase() == cleanFrom.toLowerCase() &&
          normalizeMangaId(r.mangaId) == normalizedMangaId,
    );

    _rules.insert(
      0,
      GlossaryRule(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        from: cleanFrom,
        to: cleanTo,
        mangaId: normalizedMangaId,
        isEnabled: true,
        createdAt: DateTime.now(),
      ),
    );

    await _save();
  }

  /// Thêm hoặc cập nhật hàng loạt từ ngữ trong 1 lần lưu (tối ưu hiệu năng khi nhập gói cộng đồng)
  Future<int> addRulesBatch(
    List<Map<String, String>> pairs, {
    String? mangaId,
  }) async {
    if (pairs.isEmpty) return 0;
    int count = 0;
    final now = DateTime.now();
    final normalizedMangaId = normalizeMangaId(mangaId);

    for (int i = 0; i < pairs.length; i++) {
      final cleanFrom = pairs[i]['from']?.trim() ?? '';
      final cleanTo = pairs[i]['to']?.trim() ?? '';
      if (cleanFrom.isEmpty) continue;

      _rules.removeWhere(
        (r) =>
            r.from.toLowerCase() == cleanFrom.toLowerCase() &&
            normalizeMangaId(r.mangaId) == normalizedMangaId,
      );

      _rules.insert(
        0,
        GlossaryRule(
          id: '${now.millisecondsSinceEpoch}_$i',
          from: cleanFrom,
          to: cleanTo,
          mangaId: normalizedMangaId,
          isEnabled: true,
          createdAt: now,
        ),
      );
      count++;
    }

    if (count > 0) {
      await _save();
    }
    return count;
  }

  Future<void> updateRule(GlossaryRule rule) async {
    final index = _rules.indexWhere((r) => r.id == rule.id);
    if (index != -1) {
      _rules[index] = rule;
      await _save();
    }
  }

  Future<void> deleteRule(String id) async {
    _rules.removeWhere((r) => r.id == id);
    await _save();
  }

  Future<void> toggleRule(String id) async {
    final index = _rules.indexWhere((r) => r.id == id);
    if (index != -1) {
      final current = _rules[index];
      _rules[index] = GlossaryRule(
        id: current.id,
        from: current.from,
        to: current.to,
        mangaId: current.mangaId,
        isEnabled: !current.isEnabled,
        createdAt: current.createdAt,
      );
      await _save();
    }
  }

  /// Xóa toàn bộ quy tắc (hoặc chỉ quy tắc thuộc mangaId nhất định)
  Future<void> clearRules({String? mangaId, bool globalOnly = false}) async {
    if (globalOnly) {
      _rules.removeWhere((r) => r.mangaId == null);
    } else if (mangaId != null) {
      final normalizedMangaId = normalizeMangaId(mangaId);
      _rules.removeWhere((r) => normalizeMangaId(r.mangaId) == normalizedMangaId);
    } else {
      _rules.clear();
    }
    await _save();
  }

  /// Xuất danh sách từ điển ra định dạng JSON string (để sao lưu hoặc chia sẻ)
  String exportRulesAsJson({String? mangaId}) {
    final targetRules = getRulesForManga(mangaId);
    final list = targetRules.map((r) => r.toMap()).toList();
    return const JsonEncoder.withIndent('  ').convert(list);
  }

  /// Nhập danh sách từ điển từ chuỗi JSON
  Future<int> importRulesFromJson(String jsonStr, {String? targetMangaId}) async {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! List) return 0;
      final pairs = <Map<String, String>>[];
      for (final item in decoded) {
        if (item is Map) {
          final from = item['from']?.toString().trim() ?? '';
          final to = item['to']?.toString().trim() ?? '';
          if (from.isNotEmpty) {
            pairs.add({'from': from, 'to': to});
          }
        }
      }
      return await addRulesBatch(pairs, mangaId: targetMangaId);
    } catch (_) {
      return 0;
    }
  }

  Future<void> _save() async {
    _invalidateCache();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _rules.map((r) => jsonEncode(r.toMap())).toList();
      await prefs.setStringList(_prefKey, list);
    } catch (_) {}
  }

  // Cache variables to prevent heavy RegExp compilations on every build
  final Map<String, List<GlossaryRule>> _activeRulesCache = {};
  final Map<String, RegExp> _regexCache = {};

  void _invalidateCache() {
    _activeRulesCache.clear();
    _regexCache.clear();
  }

  /// Áp dụng các quy tắc thay thế từ ngữ vào văn bản
  String applyReplacements(String text, {String? mangaId}) {
    if (text.isEmpty) return text;
    
    final normalizedMangaId = normalizeMangaId(mangaId);
    final cacheKey = normalizedMangaId ?? 'global';
    
    List<GlossaryRule>? activeRules = _activeRulesCache[cacheKey];
    RegExp? combinedRegex = _regexCache[cacheKey];
    
    if (activeRules == null) {
      activeRules = _rules.where((r) {
        if (!r.isEnabled || r.from.isEmpty) return false;
        return r.mangaId == null || normalizeMangaId(r.mangaId) == normalizedMangaId;
      }).toList()
        ..sort((a, b) => b.from.length.compareTo(a.from.length));
        
      _activeRulesCache[cacheKey] = activeRules;
      
      if (activeRules.isNotEmpty) {
        try {
          final pattern = activeRules.map((r) => RegExp.escape(r.from)).join('|');
          combinedRegex = RegExp(pattern, caseSensitive: false);
          _regexCache[cacheKey] = combinedRegex;
        } catch (_) {}
      }
    }

    if (activeRules.isEmpty || combinedRegex == null) return text;

    return text.replaceAllMapped(combinedRegex, (match) {
      final matchedString = match.group(0)?.toLowerCase();
      if (matchedString == null) return match.group(0) ?? '';
      
      for (final rule in activeRules!) {
        if (rule.from.toLowerCase() == matchedString) {
          return rule.to;
        }
      }
      return match.group(0) ?? '';
    });
  }
}
