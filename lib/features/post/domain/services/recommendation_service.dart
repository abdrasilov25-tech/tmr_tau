import 'dart:math' as math;

import '../entities/post_entity.dart';
import '../entities/publication_feed_page_result.dart';
import '../entities/recommended_feed_result.dart';
import '../repositories/post_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RecommendationService
//
// Высокоуровневый сервис, который строит персонализированную ленту
// «Instagram-style» поверх [PostRepository].
//
// Алгоритм «70 / 20 / 10»:
//   70% — персонализированные посты  (author affinity + hashtags + категории)
//   20% — популярные                 (engagementScore = views×1+likes×3+comments×5+saves×7)
//   10% — новые                      (created_at DESC)
//
// Гео-бонус (Haversine):
//   ≤ 5 км  → +30 к score
//   ≤ 10 км → +15 к score
//   > 10 км → 0
//
// Кэш: результаты страниц хранятся 5 минут в памяти per-userId.
// Вызовите [invalidateCache] при logout или pull-to-refresh.
// ─────────────────────────────────────────────────────────────────────────────

class RecommendationService {
  RecommendationService(this._postRepository);

  final PostRepository _postRepository;

  // ── Кэш ──────────────────────────────────────────────────────────────────
  static const Duration _cacheTtl = Duration(minutes: 5);
  final Map<String, _UserCache> _cache = {};

  /// Инвалидировать кэш для пользователя (logout / pull-to-refresh).
  /// Передай `null`, чтобы очистить весь кэш.
  void invalidateCache(String? userId) {
    if (userId == null) {
      _cache.clear();
    } else {
      _cache.remove(userId);
    }
  }

  // ── Публичный API ─────────────────────────────────────────────────────────

  /// Возвращает смешанную рекомендованную ленту для [userId].
  ///
  /// Параметры:
  /// - [userId]       — текущий пользователь (null = анонимный, без персонализации)
  /// - [followingIds] — ID авторов, на которых подписан пользователь
  /// - [userLat/Lon]  — GPS-координаты (null = гео-бонус не применяется)
  /// - [page]         — страница (0-based) для пагинации
  /// - [limit]        — постов на страницу (рекомендуется 15–20)
  Future<RecommendedFeedResult> getRecommendedPosts({
    required String? userId,
    required List<String> followingIds,
    double? userLat,
    double? userLon,
    int page = 0,
    int limit = 15,
  }) async {
    // ── Проверяем кэш ─────────────────────────────────────────
    if (userId != null) {
      final cached = _cache[userId];
      if (cached != null && !cached.isExpired) {
        final cachedPage = cached.pages[page];
        if (cachedPage != null) return cachedPage;
      }
    }

    // ── Распределение слотов 70/20/10 ─────────────────────────
    final personalizedSlots = math.max(1, (limit * 0.70).round()); // ~10–11
    final popularSlots      = math.max(1, (limit * 0.20).round()); // ~3
    final newSlots          = math.max(1, limit - personalizedSlots - popularSlots); // ~1–2

    // С буфером для дедупликации
    final personalizedBuffer = personalizedSlots + 8;
    final feedBuffer         = popularSlots + newSlots + 12;

    // ── Параллельный fetch ────────────────────────────────────
    final fetched = await Future.wait<Object>([
      _postRepository.getPublicationsFeedRecommendations(
        currentUserId: userId,
        followingUserIds: followingIds,
        limit: personalizedBuffer,
        discoveryDbOffset: page * personalizedSlots,
      ),
      _postRepository.getFeedPosts(
        limit: feedBuffer,
        offset: page * (popularSlots + newSlots),
        currentUserId: userId,
      ),
    ]);

    final personalizedResult = fetched[0] as PublicationFeedPageResult;
    final allFeed            = fetched[1] as List<PostEntity>;

    final personalizedPosts = personalizedResult.posts;

    // ── Отслеживаем использованные ID (дедупликация) ──────────
    final usedIds = <String>{};

    // ── Сегмент 1 (70%): персонализированные ─────────────────
    final personalizedSorted = _sortByGeoAndEngagement(
      personalizedPosts,
      userLat,
      userLon,
    );
    final personalized = <PostEntity>[];
    for (final p in personalizedSorted) {
      if (personalized.length >= personalizedSlots) break;
      if (usedIds.add(p.id)) personalized.add(p);
    }

    // ── Сегмент 2 (20%): популярные ──────────────────────────
    final popularSorted = List<PostEntity>.from(allFeed)
      ..sort(
        (a, b) => _geoAdjustedEngagement(b, userLat, userLon)
            .compareTo(_geoAdjustedEngagement(a, userLat, userLon)),
      );
    final popular = <PostEntity>[];
    for (final p in popularSorted) {
      if (popular.length >= popularSlots) break;
      if (usedIds.add(p.id)) popular.add(p);
    }

    // ── Сегмент 3 (10%): новые ───────────────────────────────
    final newestSorted = List<PostEntity>.from(allFeed)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final newest = <PostEntity>[];
    for (final p in newestSorted) {
      if (newest.length >= newSlots) break;
      if (usedIds.add(p.id)) newest.add(p);
    }

    // ── Чередуем сегменты ────────────────────────────────────
    final mixed = _interleave(personalized, popular, newest);

    final result = RecommendedFeedResult(
      posts: mixed,
      page: page,
      hasMore: personalizedPosts.length >= personalizedSlots ||
          allFeed.length >= feedBuffer - 4,
      personalizedCount: personalized.length,
      popularCount: popular.length,
      newCount: newest.length,
    );

    // ── Кэшируем ──────────────────────────────────────────────
    if (userId != null) {
      (_cache[userId] ??= _UserCache()).pages[page] = result;
    }

    return result;
  }

  // ── Приватные хелперы ────────────────────────────────────────────────────

  /// Сортирует по engagement + гео-бонус (лучшее сначала).
  List<PostEntity> _sortByGeoAndEngagement(
    List<PostEntity> posts,
    double? lat,
    double? lon,
  ) {
    if (lat == null || lon == null) return posts;
    return [...posts]
      ..sort(
        (a, b) => _geoAdjustedEngagement(b, lat, lon)
            .compareTo(_geoAdjustedEngagement(a, lat, lon)),
      );
  }

  /// Базовый engagement + гео-бонус.
  static double _geoAdjustedEngagement(
    PostEntity p,
    double? userLat,
    double? userLon,
  ) =>
      p.engagementScore + _geoBonus(p, userLat, userLon);

  /// Гео-бонус по расстоянию Haversine.
  ///   ≤ 5 км  → +30
  ///   ≤ 10 км → +15
  ///   иначе   →  0
  static double _geoBonus(PostEntity p, double? userLat, double? userLon) {
    if (userLat == null || userLon == null) return 0;
    if (!p.hasGeo) return 0;
    final km = _haversineKm(userLat, userLon, p.latitude!, p.longitude!);
    if (km <= 5) return 30;
    if (km <= 10) return 15;
    return 0;
  }

  /// Формула Haversine — расстояние в километрах между двумя точками.
  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _deg2rad(double deg) => deg * math.pi / 180.0;

  /// Чередует 3 сегмента: каждые [_stride] персонализированных —
  /// 1 популярный + 1 новый. Делает ленту «живой» без скучных блоков.
  static const int _stride = 5;

  static List<PostEntity> _interleave(
    List<PostEntity> personalized,
    List<PostEntity> popular,
    List<PostEntity> newest,
  ) {
    final result = <PostEntity>[];
    var pi = 0; // personalized
    var ri = 0; // popular
    var ni = 0; // new
    var counter = 0;

    while (pi < personalized.length) {
      result.add(personalized[pi++]);
      counter++;

      if (counter % _stride == 0) {
        if (ri < popular.length) result.add(popular[ri++]);
        if (ni < newest.length)  result.add(newest[ni++]);
      }
    }

    // Оставшиеся popular и new добавляем в конец
    while (ri < popular.length) result.add(popular[ri++]);
    while (ni < newest.length)  result.add(newest[ni++]);

    return result;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Внутренние вспомогательные классы (приватные)
// ─────────────────────────────────────────────────────────────────────────────

class _UserCache {
  final DateTime _createdAt = DateTime.now();
  final Map<int, RecommendedFeedResult> pages = {};

  bool get isExpired =>
      DateTime.now().difference(_createdAt) > RecommendationService._cacheTtl;
}
