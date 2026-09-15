import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../data/content_type.dart';
import '../data/database_helper.dart';
import '../data/models.dart';
import '../data/models_cloud.dart';
import '../features/catalog/catalog_cache_service.dart';

class RecommendationService {
  RecommendationService._();
  static final RecommendationService instance = RecommendationService._();

  /// Tính toán bảng điểm sở thích thể loại (Genre Affinity Score) dựa trên lịch sử & nhật ký đọc.
  /// Trả về `Map<GenreName, Score>` và `Set<MangaId>` đã đọc.
  Future<({Map<String, double> genreScores, Set<String> readMangaIds})>
      calculateUserPreferences({List<CloudManga>? catalog}) async {
    try {
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      final userIds = authUid == null ? [] : [authUid];

      final readMangaIds = <String>{};
      final genreWeights = <String, double>{};
      final now = DateTime.now();

      // 1. Lấy toàn bộ lịch sử đọc
      for (final uid in userIds) {
        final history = await DatabaseHelper.instance.getHistory(uid);
        for (final item in history) {
          if (item.mangaId.isNotEmpty) {
            readMangaIds.add(item.mangaId);
          }
        }
      }

      // 2. Lấy hoạt động đọc gần đây
      final activities = <ReadingActivity>[];
      for (final uid in userIds) {
        final userActivities =
            await DatabaseHelper.instance.getReadingActivity(uid);
        activities.addAll(userActivities);
      }

      // 3. Chuẩn bị catalog map để tra cứu thể loại
      Map<String, CloudManga> catalogMap = {};
      if (catalog != null && catalog.isNotEmpty) {
        catalogMap = {for (final m in catalog) m.id: m};
      } else {
        try {
          final cached =
              await CatalogCacheService.instance.getCachedCatalog();
          catalogMap = {for (final m in cached) m.id: m};
        } catch (_) {}
      }

      // 4. Phân tích điểm từ nhật ký đọc (Reading Activity có trọng số thời gian)
      for (final act in activities) {
        readMangaIds.add(act.mangaId);
        final manga = catalogMap[act.mangaId];
        if (manga == null || manga.genres.isEmpty) continue;

        final diffDays = now.difference(act.readAt).inDays;
        // Đọc trong 7 ngày: hệ số 3.0, trong 30 ngày: 2.0, cũ hơn: 1.0
        final recencyWeight = diffDays <= 7
            ? 3.0
            : (diffDays <= 30 ? 2.0 : 1.0);

        for (final genre in manga.genres) {
          final normalized = genre.trim().toLowerCase();
          if (normalized.isEmpty) continue;
          genreWeights[normalized] = (genreWeights[normalized] ?? 0.0) + recencyWeight;
        }
      }

      // 5. Bổ sung từ lịch sử đọc (History) nếu hoạt động ít
      for (final mangaId in readMangaIds) {
        final manga = catalogMap[mangaId];
        if (manga == null || manga.genres.isEmpty) continue;
        for (final genre in manga.genres) {
          final normalized = genre.trim().toLowerCase();
          if (normalized.isEmpty) continue;
          genreWeights[normalized] = (genreWeights[normalized] ?? 0.0) + 1.0;
        }
      }

      return (genreScores: genreWeights, readMangaIds: readMangaIds);
    } catch (e) {
      debugPrint('⚠️ Error calculating user preferences: $e');
      return (genreScores: <String, double>{}, readMangaIds: <String>{});
    }
  }

  /// Gợi ý thông minh cho Trang chủ (Personalized Home Recommendations)
  /// Phân tích sở thích người dùng, lọc theo contentType, ưu tiên truyện chưa đọc thuộc genre yêu thích.
  Future<List<CloudManga>> getPersonalizedRecommendations({
    required List<CloudManga> catalog,
    required MangaContentType contentType,
    int limit = 10,
  }) async {
    if (catalog.isEmpty) return [];

    final filteredCatalog =
        catalog.where((m) => m.contentType == contentType).toList();
    if (filteredCatalog.isEmpty) return [];

    final prefs = await calculateUserPreferences(catalog: catalog);
    final genreScores = prefs.genreScores;
    final readMangaIds = prefs.readMangaIds;

    // Nếu người dùng chưa có lịch sử đọc thể loại nào:
    // Trả về danh sách truyện hot / view cao kết hợp độ đa dạng
    if (genreScores.isEmpty) {
      final fallbackList = List<CloudManga>.from(filteredCatalog);
      fallbackList.sort((a, b) => b.viewCount.compareTo(a.viewCount));
      return fallbackList.take(limit).toList();
    }

    // Tính điểm phù hợp cho từng bộ truyện trong catalog
    final scoredList = <({CloudManga manga, double score})>[];

    for (final manga in filteredCatalog) {
      double score = 0.0;

      // Điểm thể loại trùng khớp
      for (final genre in manga.genres) {
        final normalized = genre.trim().toLowerCase();
        final genreAffinity = genreScores[normalized] ?? genreScores[genre.trim()] ?? 0.0;
        score += genreAffinity * 2.0;
      }

      // Điểm cộng lượt xem & yêu thích (logarithmic để không lấn át genre)
      if (manga.viewCount > 0) {
        score += log(manga.viewCount + 1) * 0.5;
      }
      if (manga.likeCount > 0) {
        score += log(manga.likeCount + 1) * 0.8;
      }

      // Ưu tiên truyện người dùng chưa đọc để khám phá mới
      final isAlreadyRead = readMangaIds.contains(manga.id);
      if (isAlreadyRead) {
        score *= 0.35; // Giảm trọng số nếu đã có trong lịch sử
      } else {
        score += 5.0; // Thưởng điểm khám phá truyện mới
      }

      scoredList.add((manga: manga, score: score));
    }

    // Sắp xếp điểm giảm dần
    scoredList.sort((a, b) => b.score.compareTo(a.score));

    return scoredList.map((e) => e.manga).take(limit).toList();
  }

  /// Gợi ý thông minh cho Trang Chi Tiết (Related Manga Recommendations)
  /// Kết hợp độ tương đồng thể loại với bộ truyện hiện tại + tác giả + sở thích người dùng.
  List<CloudManga> getRelatedMangas({
    required CloudManga currentManga,
    required List<CloudManga> catalog,
    Map<String, double>? userGenreScores,
    int limit = 10,
  }) {
    if (catalog.isEmpty) return [];

    final targetGenres = currentManga.genres.map((g) => g.trim().toLowerCase()).toSet();
    final targetAuthor = currentManga.author.trim().toLowerCase();
    final isAuthorMeaningful = targetAuthor.isNotEmpty &&
        targetAuthor != 'đang cập nhật' &&
        targetAuthor != 'chưa rõ' &&
        targetAuthor != 'khuyết danh';

    final candidates = catalog.where((m) => m.id != currentManga.id).toList();
    if (candidates.isEmpty) return [];

    final scoredCandidates = <({CloudManga manga, double score})>[];

    for (final candidate in candidates) {
      double score = 0.0;

      // Ưu tiên cùng loại truyện (Manga / Novel)
      if (candidate.contentType == currentManga.contentType) {
        score += 5.0;
      }

      // Trùng tác giả
      if (isAuthorMeaningful &&
          candidate.author.trim().toLowerCase() == targetAuthor) {
        score += 15.0;
      }

      // Điểm tương đồng thể loại (Jaccard / Overlap Similarity)
      final candidateGenres =
          candidate.genres.map((g) => g.trim().toLowerCase()).toSet();
      int matchCount = 0;
      for (final g in candidateGenres) {
        if (targetGenres.contains(g)) {
          matchCount++;
          // Cộng điểm affinity của user nếu có
          if (userGenreScores != null) {
            final userAffinity = userGenreScores[g] ?? userGenreScores[g.toLowerCase()] ?? 0.0;
            score += userAffinity * 0.5;
          }
        }
      }

      if (matchCount > 0) {
        score += matchCount * 10.0;
        // Jaccard index bonus
        final unionCount = targetGenres.union(candidateGenres).length;
        if (unionCount > 0) {
          score += (matchCount / unionCount) * 10.0;
        }
      }

      // Nhẹ nhàng cộng độ hot
      if (candidate.viewCount > 0) {
        score += log(candidate.viewCount + 1) * 0.3;
      }

      scoredCandidates.add((manga: candidate, score: score));
    }

    scoredCandidates.sort((a, b) => b.score.compareTo(a.score));

    // Nếu không có bộ nào có điểm trùng thể loại, fallback sang cùng contentType
    final top = scoredCandidates.map((e) => e.manga).take(limit).toList();
    if (top.isEmpty) {
      return candidates
          .where((m) => m.contentType == currentManga.contentType)
          .take(limit)
          .toList();
    }
    return top;
  }
}
