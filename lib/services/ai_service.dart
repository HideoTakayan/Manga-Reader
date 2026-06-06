import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../data/content_type.dart';
import '../data/database_helper.dart';
import '../data/drive_service.dart';
import '../data/models.dart';
import '../data/models_cloud.dart';
import '../features/catalog/catalog_cache_service.dart';
import 'history_service.dart';

class AiService {
  static final AiService instance = AiService._internal();
  AiService._internal();

  final List<Content> _chatHistory = [];

  void resetSession() {
    _chatHistory.clear();
  }

  Future<String> sendMessage(String message) async {
    try {
      final chatSession = await _createChatSession(message);
      final response = await chatSession.sendMessage(Content.text(message));
      final text = response.text?.trim();
      final answer = text == null || text.isEmpty
          ? 'Xin lỗi, tớ chưa có câu trả lời phù hợp.'
          : text;
      _chatHistory.add(Content.text(message));
      _chatHistory.add(Content.model([TextPart(answer)]));
      if (_chatHistory.length > 8) {
        _chatHistory.removeRange(0, _chatHistory.length - 8);
      }
      return answer;
    } catch (e) {
      throw Exception('Lỗi AI: ${e.toString()}');
    }
  }

  Future<ChatSession> _createChatSession(String message) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('Bạn cần đăng nhập để dùng MangaReader AI.');
    }

    final doc = await FirebaseFirestore.instance
        .collection('app_settings')
        .doc('api_keys')
        .get();

    final apiKey = (doc.data()?['gemini_key'] as String?)?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Chưa cấu hình API Key. Vui lòng báo admin.');
    }

    final mangas = await _loadCatalog();
    final history = await _loadHistory(currentUser.uid, mangas);
    final following = await _loadFollowing(currentUser.uid, mangas);
    final candidates = _selectCatalogCandidates(
      message,
      mangas,
      history,
      following,
    );
    final model = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: apiKey,
      systemInstruction: Content.system(
        _buildSystemPrompt(candidates, history, following),
      ),
      generationConfig: GenerationConfig(
        temperature: 0.45,
        maxOutputTokens: 500,
      ),
    );

    return model.startChat(history: List<Content>.from(_chatHistory));
  }

  Future<List<CloudManga>> _loadCatalog() async {
    final cached = DriveService.instance.cachedMangas;
    if (cached != null && cached.isNotEmpty) return cached;
    return DriveService.instance.getMangas();
  }

  Future<List<Map<String, dynamic>>> _loadHistory(
    String userId,
    List<CloudManga> mangas,
  ) async {
    var localHistory = <ReadingHistory>[];
    var cloudHistory = <ReadingHistory>[];
    try {
      localHistory = await DatabaseHelper.instance.getHistory(userId);
    } catch (_) {
      // Recommendations can still use cloud history.
    }
    try {
      cloudHistory = await HistoryService.instance.getAllHistory();
    } catch (_) {
      // Recommendations can still use local history.
    }
    final merged = <String, ReadingHistory>{};
    for (final item in [...cloudHistory, ...localHistory]) {
      final current = merged[item.mangaId];
      if (current == null || item.updatedAt.isAfter(current.updatedAt)) {
        merged[item.mangaId] = item;
      }
    }
    final mangaById = {for (final manga in mangas) manga.id: manga};
    final sortedHistory = merged.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return sortedHistory.take(20).map((history) {
      final manga = mangaById[history.mangaId];
      return {
        'mangaId': history.mangaId,
        'title': manga?.title ?? history.mangaId,
        'chapterTitle': history.chapterTitle,
        'contentType': manga == null
            ? contentTypeToJson(MangaContentType.manga)
            : contentTypeToJson(manga.contentType),
      };
    }).toList();
  }

  Future<List<CloudManga>> _loadFollowing(
    String userId,
    List<CloudManga> mangas,
  ) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('following')
          .limit(50)
          .get();
      final ids = snapshot.docs
          .map((doc) => (doc.data()['mangaId'] as String?) ?? doc.id)
          .toSet();
      return mangas.where((manga) => ids.contains(manga.id)).toList();
    } catch (_) {
      return [];
    }
  }

  List<CloudManga> _selectCatalogCandidates(
    String message,
    List<CloudManga> catalog,
    List<Map<String, dynamic>> history,
    List<CloudManga> following,
  ) {
    if (catalog.length <= 30) return catalog;

    final normalize = CatalogCacheService.instance.normalize;
    final normalizedMessage = normalize(message);
    final stopWords = {
      'anh',
      'ban',
      'biet',
      'bo',
      'cho',
      'co',
      'cua',
      'de',
      'doc',
      'duoc',
      'gi',
      'gioi',
      'goi',
      'hay',
      'khong',
      'la',
      'minh',
      'mot',
      'nao',
      'nhung',
      'toi',
      'truyen',
      'tu',
      'y',
    };
    final queryTokens = normalizedMessage
        .split(RegExp(r'\s+'))
        .map((token) => token.replaceAll(RegExp(r'[^a-z0-9]'), '').trim())
        .where((token) => token.length >= 2 && !stopWords.contains(token))
        .toSet();
    final followingIds = following.map((manga) => manga.id).toSet();
    final historyRank = <String, int>{};
    for (var index = 0; index < history.length; index++) {
      final mangaId = history[index]['mangaId'] as String?;
      if (mangaId != null) historyRank[mangaId] = history.length - index;
    }

    final scored = <({CloudManga manga, int score})>[];
    for (final manga in catalog) {
      final title = normalize(manga.title);
      final author = normalize(manga.author);
      final genres = normalize(manga.genres.join(' '));
      final description = normalize(manga.description);
      var score = 0;

      if (normalizedMessage.length >= 2 && title.contains(normalizedMessage)) {
        score += 30;
      }
      for (final token in queryTokens) {
        if (title.contains(token)) score += 10;
        if (genres.contains(token)) score += 6;
        if (author.contains(token)) score += 4;
        if (description.contains(token)) score += 1;
      }
      if (followingIds.contains(manga.id)) score += 8;
      score += historyRank[manga.id] ?? 0;
      scored.add((manga: manga, score: score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(30).map((item) => item.manga).toList();
  }

  String _buildSystemPrompt(
    List<CloudManga> catalog,
    List<Map<String, dynamic>> history,
    List<CloudManga> following,
  ) {
    final catalogLines = catalog.isEmpty
        ? '- Catalog hien dang rong.'
        : catalog
              .map((item) {
                final genres = item.genres.take(10).join(', ');
                final type = contentTypeToJson(item.contentType);
                final author = item.author.isEmpty ? 'khong ro' : item.author;
                final genreText = genres.isEmpty ? 'khong ro' : genres;
                final description = item.description
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim();
                final shortDescription = description.length > 120
                    ? '${description.substring(0, 120)}...'
                    : description;
                return '- ${item.title} (ID: ${item.id}, loai: $type, tac gia: $author, the loai: $genreText, mo ta: $shortDescription)';
              })
              .join('\n');

    final historyLines = history.isEmpty
        ? '- Chua co lich su doc gan day.'
        : history
              .map((item) {
                final title = item['title'];
                final chapterTitle = item['chapterTitle'];
                final chapter = chapterTitle == null
                    ? ''
                    : ', dang doc: $chapterTitle';
                return '- $title (${item['contentType']}$chapter)';
              })
              .join('\n');

    final followingLines = following.isEmpty
        ? '- Chua theo doi truyen nao.'
        : following
              .take(30)
              .map((item) {
                final genres = item.genres.take(8).join(', ');
                return '- ${item.title} (${contentTypeToJson(item.contentType)}, the loai: $genres)';
              })
              .join('\n');

    return '''
Ban la tro ly goi y truyen ngan gon cua MangaReader.

Nhiem vu:
1. Goi y truyen dua tren lich su doc va yeu cau cua nguoi dung.
2. Uu tien so thich suy ra tu lich su va danh sach theo doi.
3. Chi gioi thieu truyen co trong catalog. Tuyet doi khong bia ten truyen.
4. Moi lan chi goi y toi da 5 truyen, noi ngan gon ly do phu hop.
5. Tra loi bang tieng Viet.
6. Neu cau hoi khong lien quan den tim hoac goi y truyen, noi ngan gon rang ban chi ho tro goi y truyen trong MangaReader.
7. Neu khong co truyen phu hop, noi "Chua tim thay truyen phu hop trong kho hien co."

CATALOG GOOGLE DRIVE:
$catalogLines

LICH SU DOC GAN DAY:
$historyLines

DANH SACH DANG THEO DOI:
$followingLines
''';
  }
}
