import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../domain/entities/post_comment_entity.dart';
import '../../domain/entities/post_entity.dart';
import '../../domain/entities/publication_feed_page_result.dart';
import '../../domain/exceptions/post_comment_exceptions.dart';
import '../../domain/repositories/post_repository.dart';
import '../models/post_comment_model.dart';
import '../models/post_model.dart';

class PostRepositoryImpl implements PostRepository {
  PostRepositoryImpl(this._client);
  final SupabaseClient _client;

  static const String _postSelect = '*, users!user_id(name, avatar)';

  @override
  Future<List<PostEntity>> getFeedPosts({
    int limit = 20,
    int offset = 0,
    String? currentUserId,
  }) async {
    var res = await _client
        .from(SupabaseConstants.postsTable)
        .select(_postSelect)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    var list =
        (res as List).map((e) => _mapPost(e as Map<String, dynamic>)).toList();
    if (list.isEmpty) {
      final plainRes = await _client
          .from(SupabaseConstants.postsTable)
          .select()
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      list = (plainRes as List)
          .map((e) => _mapPost(e as Map<String, dynamic>))
          .toList();
    }
    return await _applyPostUserState(list, currentUserId);
  }

  Future<List<PostEntity>> _applyPostUserState(
    List<PostEntity> list,
    String? currentUserId,
  ) async {
    if (currentUserId == null || list.isEmpty) return list;
    final ids = list.map((e) => e.id).toList();
    final likes = await _client
        .from(SupabaseConstants.postLikesTable)
        .select('post_id')
        .eq('user_id', currentUserId)
        .inFilter('post_id', ids);
    final reposts = await _client
        .from(SupabaseConstants.repostsTable)
        .select('post_id')
        .eq('user_id', currentUserId)
        .inFilter('post_id', ids);
    final saves = await _client
        .from(SupabaseConstants.postSavesTable)
        .select('post_id')
        .eq('user_id', currentUserId)
        .inFilter('post_id', ids);
    final likedIds =
        (likes as List).map((e) => (e as Map)['post_id'] as String).toSet();
    final repostedIds =
        (reposts as List).map((e) => (e as Map)['post_id'] as String).toSet();
    final savedIds =
        (saves as List).map((e) => (e as Map)['post_id'] as String).toSet();
    return list
        .map(
          (p) => PostModel(
            id: p.id,
            userId: p.userId,
            kind: p.kind,
            imageUrl: p.imageUrl,
            imageUrls: p.imageUrls,
            caption: p.caption,
            videoUrl: p.videoUrl,
            videoDurationSeconds: p.videoDurationSeconds,
            createdAt: p.createdAt,
            likesCount: p.likesCount,
            dislikesCount: p.dislikesCount,
            commentsCount: p.commentsCount,
            viewsCount: p.viewsCount,
            repostsCount: p.repostsCount,
            userName: p.userName,
            userAvatarUrl: p.userAvatarUrl,
            isLikedByMe: likedIds.contains(p.id),
            isDislikedByMe: p.isDislikedByMe,
            isRepostedByMe: repostedIds.contains(p.id),
            isSavedByMe: savedIds.contains(p.id),
          ),
        )
        .toList();
  }

  @override
  Future<PublicationFeedPageResult> getPublicationsFeedSubscriptions({
    String? currentUserId,
    required List<String> followingUserIds,
    int limit = 10,
    int offset = 0,
  }) async {
    final me = currentUserId;
    final safeLimit = limit <= 0 ? 10 : limit;
    final safeOffset = offset < 0 ? 0 : offset;
    final fetchWindow = math.max(safeLimit * 3, 30);
    final fetchFrom = math.max(safeOffset * 3, 0);
    final fetchTo = fetchFrom + fetchWindow - 1;
    final following =
        followingUserIds.where((id) => id != me).toList(growable: false);
    if (following.isEmpty) {
      return const PublicationFeedPageResult(posts: [], nextOffset: 0);
    }
    final res = await _client
        .from(SupabaseConstants.postsTable)
        .select(_postSelect)
        .eq('kind', 'publication')
        .inFilter('user_id', following)
        .order('created_at', ascending: false)
        .range(fetchFrom, fetchTo);
    final rawList = (res as List)
        .map((e) => _mapPost(e as Map<String, dynamic>))
        .toList(growable: false);
    List<PostEntity> list;
    if (me != null) {
      final signals = await _loadRecommendationSignals(me);
      list = _rankSubscriptionPublications(
        rawList,
        signals,
        safeLimit,
      );
    } else {
      list = _applyDiversityByAuthor(
        posts: rawList,
        limit: safeLimit,
      );
    }
    final enriched = await _applyPostUserState(list, me);
    return PublicationFeedPageResult(
      posts: enriched,
      nextOffset: safeOffset + list.length,
    );
  }

  @override
  Future<PublicationFeedPageResult> getPublicationsFeedRecommendations({
    String? currentUserId,
    required List<String> followingUserIds,
    int limit = 10,
    int discoveryDbOffset = 0,
  }) async {
    final me = currentUserId;
    final followingIdsSet =
        followingUserIds.where((id) => id != me).toSet();

    final targetPool = math.max(limit * 4, limit);
    final discoveryPosts = <PostEntity>[];
    var nextDiscoveryDb = discoveryDbOffset;
    const batchSize = 40;
    var scanned = 0;
    const maxScan = 2000;

    while (discoveryPosts.length < targetPool && scanned < maxScan) {
      final res = await _client
          .from(SupabaseConstants.postsTable)
          .select(_postSelect)
          .eq('kind', 'publication')
          .order('created_at', ascending: false)
          .range(nextDiscoveryDb, nextDiscoveryDb + batchSize - 1);
      final batch = (res as List)
          .map((e) => _mapPost(e as Map<String, dynamic>))
          .toList(growable: false);
      if (batch.isEmpty) {
        break;
      }
      for (final p in batch) {
        if (me != null && p.userId == me) {
          continue;
        }
        if (followingIdsSet.contains(p.userId)) {
          continue;
        }
        discoveryPosts.add(p);
        if (discoveryPosts.length >= targetPool) {
          break;
        }
      }
      nextDiscoveryDb += batch.length;
      scanned += batch.length;
    }

    final rng = math.Random();
    List<PostEntity> ranked;
    if (me == null) {
      discoveryPosts.shuffle(rng);
      ranked = discoveryPosts.take(limit).toList(growable: false);
    } else {
      final signals = await _loadRecommendationSignals(me);
      ranked = _rankRecommendations(
        discoveryPosts,
        signals,
        rng,
        limit,
      );
    }

    final enriched = await _applyPostUserState(ranked, me);

    return PublicationFeedPageResult(
      posts: enriched,
      nextOffset: nextDiscoveryDb,
    );
  }

  @override
  Future<void> recordPublicationFeedImpression({
    required String postId,
    required int watchedMsDelta,
    bool completed = false,
  }) async {
    if (_client.auth.currentUser == null) return;
    if (watchedMsDelta <= 0 && !completed) return;
    try {
      await _client.rpc<void>(
        'increment_publication_feed_impression',
        params: {
          'p_post_id': postId,
          'p_delta_ms': watchedMsDelta,
          'p_completed': completed,
        },
      );
    } catch (_) {
      // Таблица/RPC могут быть ещё не применены на стенде.
    }
  }

  /// Хэштеги: `#слово` или `#word123` (Unicode).
  static final RegExp _hashtagRe = RegExp(
    r'#([^\s#]+)',
    unicode: true,
  );

  static List<String> _extractHashtags(String caption) {
    final tags = <String>[];
    for (final m in _hashtagRe.allMatches(caption)) {
      final raw = m.group(1);
      if (raw == null || raw.isEmpty) continue;
      tags.add(raw.toLowerCase());
    }
    return tags;
  }

  static List<List<T>> _chunkList<T>(List<T> list, int size) {
    final out = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      final end = i + size > list.length ? list.length : i + size;
      out.add(list.sublist(i, end));
    }
    return out;
  }

  static void _normalize01(Map<String, double> m) {
    if (m.isEmpty) return;
    var mx = 0.0;
    for (final v in m.values) {
      if (v > mx) mx = v;
    }
    if (mx <= 0) return;
    for (final k in m.keys.toList()) {
      m[k] = m[k]! / mx;
    }
  }

  static void _mergeScores(
    Map<String, double> dest,
    Map<String, double> src, {
    double scale = 1,
  }) {
    for (final e in src.entries) {
      dest[e.key] = (dest[e.key] ?? 0) + e.value * scale;
    }
  }

  Future<Map<String, double>> _authorWeightsFromPostIds(
    List<String> postIds,
    double weightPerHit,
  ) async {
    final scores = <String, double>{};
    if (postIds.isEmpty) return scores;
    for (final batch in _chunkList(postIds, 120)) {
      final res = await _client
          .from(SupabaseConstants.postsTable)
          .select('id, user_id, kind')
          .inFilter('id', batch);
      for (final row in res as List) {
        final m = row as Map<String, dynamic>;
        if (m['kind'] != 'publication') continue;
        final uid = m['user_id'] as String;
        scores[uid] = (scores[uid] ?? 0) + weightPerHit;
      }
    }
    return scores;
  }

  Future<Map<String, double>> _authorWeightsFromLikes(String userId) async {
    final res = await _client
        .from(SupabaseConstants.postLikesTable)
        .select('post_id')
        .eq('user_id', userId)
        .limit(500);
    final ids = (res as List)
        .map((e) => (e as Map)['post_id'] as String)
        .toList(growable: false);
    return _authorWeightsFromPostIds(ids, 5.0);
  }

  Future<Map<String, double>> _authorWeightsFromSaves(String userId) async {
    final res = await _client
        .from(SupabaseConstants.postSavesTable)
        .select('post_id')
        .eq('user_id', userId)
        .limit(500);
    final ids = (res as List)
        .map((e) => (e as Map)['post_id'] as String)
        .toList(growable: false);
    return _authorWeightsFromPostIds(ids, 4.0);
  }

  Future<Map<String, double>> _authorWeightsFromImpressions(
    String userId,
  ) async {
    final res = await _client
        .from(SupabaseConstants.publicationFeedImpressionsTable)
        .select('post_id, watched_ms')
        .eq('user_id', userId)
        .limit(800);
    final rows = (res as List)
        .map((e) => e as Map<String, dynamic>)
        .toList(growable: false);
    if (rows.isEmpty) return {};
    final ids = rows.map((e) => e['post_id'] as String).toList(growable: false);
    final authorByPost = <String, String>{};
    for (final batch in _chunkList(ids, 120)) {
      final pres = await _client
          .from(SupabaseConstants.postsTable)
          .select('id, user_id, kind')
          .inFilter('id', batch);
      for (final row in pres as List) {
        final m = row as Map<String, dynamic>;
        if (m['kind'] != 'publication') continue;
        authorByPost[m['id'] as String] = m['user_id'] as String;
      }
    }
    final scores = <String, double>{};
    for (final row in rows) {
      final pid = row['post_id'] as String;
      final ms = (row['watched_ms'] as num?)?.toInt() ?? 0;
      final author = authorByPost[pid];
      if (author == null) continue;
      final w = math.min(ms / 25000.0, 4.0);
      scores[author] = (scores[author] ?? 0) + w;
    }
    return scores;
  }

  Future<Map<String, double>> _hashtagAffinityFromLikes(String userId) async {
    final res = await _client
        .from(SupabaseConstants.postLikesTable)
        .select('post_id')
        .eq('user_id', userId)
        .limit(400);
    final ids = (res as List)
        .map((e) => (e as Map)['post_id'] as String)
        .toList(growable: false);
    if (ids.isEmpty) return {};
    final tagCounts = <String, double>{};
    for (final batch in _chunkList(ids, 80)) {
      final pres = await _client
          .from(SupabaseConstants.postsTable)
          .select('caption, kind')
          .inFilter('id', batch);
      for (final row in pres as List) {
        final m = row as Map<String, dynamic>;
        if (m['kind'] != 'publication') continue;
        final cap = m['caption'] as String? ?? '';
        for (final t in _extractHashtags(cap)) {
          tagCounts[t] = (tagCounts[t] ?? 0) + 1;
        }
      }
    }
    _normalize01(tagCounts);
    return tagCounts;
  }

  Future<_RecommendationSignals> _loadRecommendationSignals(String userId) async {
    final futures = await Future.wait([
      _authorWeightsFromLikes(userId),
      _authorWeightsFromSaves(userId),
      _authorWeightsFromImpressions(userId),
      _hashtagAffinityFromLikes(userId),
    ]);
    final likes = futures[0];
    final saves = futures[1];
    final impressions = futures[2];
    final tags = futures[3];

    final author = <String, double>{};
    _mergeScores(author, likes);
    _mergeScores(author, saves);
    _mergeScores(author, impressions);
    _normalize01(author);

    return _RecommendationSignals(authorNorm: author, hashtagNorm: tags);
  }

  static List<PostEntity> _rankRecommendations(
    List<PostEntity> candidates,
    _RecommendationSignals signals,
    math.Random rng,
    int limit,
  ) {
    if (candidates.isEmpty) return [];
    final scored = <({PostEntity p, double s})>[];
    for (final p in candidates) {
      final s = _scorePublication(p, signals, rng);
      scored.add((p: p, s: s));
    }
    scored.sort((a, b) => b.s.compareTo(a.s));
    final ranked = scored.map((e) => e.p).toList(growable: false);
    return _applyDiversityByAuthor(posts: ranked, limit: limit);
  }

  static double _scorePublication(
    PostEntity p,
    _RecommendationSignals signals,
    math.Random rng,
  ) {
    final a = signals.authorNorm[p.userId] ?? 0.0;
    final tags = _extractHashtags(p.caption);
    double t = 0;
    if (tags.isNotEmpty) {
      for (final tag in tags) {
        t += signals.hashtagNorm[tag] ?? 0.0;
      }
      t /= tags.length;
    }
    final pop = math.log(1 + p.likesCount) / 12.0;
    final ageH = DateTime.now().difference(p.createdAt).inHours;
    final recency = math.exp(-ageH / 96.0);
    return 4.2 * a +
        2.5 * t +
        0.9 * pop +
        1.8 * recency +
        0.35 * rng.nextDouble();
  }

  @override
  Future<List<PostEntity>> getPopularPosts({String? userId}) async {
    return getFeedPosts(limit: 50, offset: 0, currentUserId: userId);
  }

  @override
  Future<List<PostEntity>> getNewsPosts({
    int limit = 20,
    int offset = 0,
    String? currentUserId,
  }) async {
    final safeLimit = limit <= 0 ? 20 : limit;
    final safeOffset = offset < 0 ? 0 : offset;
    final fetchWindow = math.max(safeLimit * 3, 30);
    final fetchFrom = math.max(safeOffset * 3, 0);
    final fetchTo = fetchFrom + fetchWindow - 1;

    var res = await _client
        .from(SupabaseConstants.postsTable)
        .select('*, users!user_id(name, avatar)')
        .eq('kind', 'news')
        .order('created_at', ascending: false)
        .range(fetchFrom, fetchTo);
    var list = (res as List)
        .map((e) => _mapPost(e as Map<String, dynamic>))
        .toList(growable: false);
    if (list.isEmpty) {
      final plainRes = await _client
          .from(SupabaseConstants.postsTable)
          .select()
          .eq('kind', 'news')
          .order('created_at', ascending: false)
          .range(fetchFrom, fetchTo);
      list = (plainRes as List)
          .map((e) => _mapPost(e as Map<String, dynamic>))
          .toList(growable: false);
    }
    if (list.isEmpty) return list;
    if (currentUserId == null) {
      list = _applySmartNewsRanking(list).take(safeLimit).toList(growable: false);
      return list;
    }
    list = await _applyPersonalizedSmartNewsRanking(
      source: list,
      currentUserId: currentUserId,
      limit: safeLimit,
    );

    final ids = list.map((e) => e.id).toList(growable: false);
    final likes = await _client
        .from(SupabaseConstants.postLikesTable)
        .select('post_id')
        .eq('user_id', currentUserId)
        .inFilter('post_id', ids);
    final reposts = await _client
        .from(SupabaseConstants.repostsTable)
        .select('post_id')
        .eq('user_id', currentUserId)
        .inFilter('post_id', ids);
    final saves = await _client
        .from(SupabaseConstants.postSavesTable)
        .select('post_id')
        .eq('user_id', currentUserId)
        .inFilter('post_id', ids);
    final likedIds =
        (likes as List).map((e) => (e as Map)['post_id'] as String).toSet();
    final repostedIds = (reposts as List)
        .map((e) => (e as Map)['post_id'] as String)
        .toSet();
    final savedIds =
        (saves as List).map((e) => (e as Map)['post_id'] as String).toSet();

    return list
        .map(
          (p) => PostModel(
            id: p.id,
            userId: p.userId,
            kind: p.kind,
            imageUrl: p.imageUrl,
            imageUrls: p.imageUrls,
            caption: p.caption,
            videoUrl: p.videoUrl,
            videoDurationSeconds: p.videoDurationSeconds,
            createdAt: p.createdAt,
            likesCount: p.likesCount,
            dislikesCount: p.dislikesCount,
            commentsCount: p.commentsCount,
            viewsCount: p.viewsCount,
            repostsCount: p.repostsCount,
            userName: p.userName,
            userAvatarUrl: p.userAvatarUrl,
            isLikedByMe: likedIds.contains(p.id),
            isDislikedByMe: p.isDislikedByMe,
            isRepostedByMe: repostedIds.contains(p.id),
            isSavedByMe: savedIds.contains(p.id),
          ),
        )
        .toList(growable: false);
  }

  List<PostEntity> _applySmartNewsRanking(List<PostEntity> source) {
    if (source.length < 2) return source;
    final now = DateTime.now();
    final ranked = List<PostEntity>.from(source);
    ranked.sort((a, b) {
      final aScore = _newsSmartScore(a, now);
      final bScore = _newsSmartScore(b, now);
      return bScore.compareTo(aScore);
    });
    return _applyDiversityByAuthor(posts: ranked, limit: ranked.length);
  }

  Future<List<PostEntity>> _applyPersonalizedSmartNewsRanking({
    required List<PostEntity> source,
    required String currentUserId,
    required int limit,
  }) async {
    if (source.length < 2) return source.take(limit).toList(growable: false);
    final affinityByAuthor = await _loadNewsAuthorAffinity(
      currentUserId: currentUserId,
      candidateAuthorIds: source.map((p) => p.userId).toSet(),
    );
    final now = DateTime.now();
    final ranked = List<PostEntity>.from(source);
    ranked.sort((a, b) {
      final aBase = _newsSmartScore(a, now);
      final bBase = _newsSmartScore(b, now);
      final aAffinity = affinityByAuthor[a.userId] ?? 0.0;
      final bAffinity = affinityByAuthor[b.userId] ?? 0.0;
      final aScore = aBase * 0.74 + aAffinity * 0.26;
      final bScore = bBase * 0.74 + bAffinity * 0.26;
      return bScore.compareTo(aScore);
    });
    return _applyDiversityByAuthor(posts: ranked, limit: limit);
  }

  List<PostEntity> _rankSubscriptionPublications(
    List<PostEntity> source,
    _RecommendationSignals signals,
    int limit,
  ) {
    if (source.length < 2) return source.take(limit).toList(growable: false);
    final now = DateTime.now();
    final ranked = List<PostEntity>.from(source);
    ranked.sort((a, b) {
      final aEng = math.log(1 + a.likesCount + (a.commentsCount * 2) + (a.repostsCount * 2.2));
      final bEng = math.log(1 + b.likesCount + (b.commentsCount * 2) + (b.repostsCount * 2.2));
      final aFresh = math.exp(-now.difference(a.createdAt).inHours / 42.0);
      final bFresh = math.exp(-now.difference(b.createdAt).inHours / 42.0);
      final aAff = signals.authorNorm[a.userId] ?? 0.0;
      final bAff = signals.authorNorm[b.userId] ?? 0.0;
      final aScore = aFresh * 0.5 + aEng * 0.28 + aAff * 0.22;
      final bScore = bFresh * 0.5 + bEng * 0.28 + bAff * 0.22;
      return bScore.compareTo(aScore);
    });
    return _applyDiversityByAuthor(posts: ranked, limit: limit);
  }

  static List<PostEntity> _applyDiversityByAuthor({
    required List<PostEntity> posts,
    required int limit,
  }) {
    if (posts.isEmpty || limit <= 0) return const [];
    final cappedLimit = limit.clamp(1, posts.length);
    final byAuthor = <String, List<PostEntity>>{};
    for (final post in posts) {
      byAuthor.putIfAbsent(post.userId, () => <PostEntity>[]).add(post);
    }
    final result = <PostEntity>[];
    String? lastAuthor;
    while (result.length < cappedLimit) {
      PostEntity? picked;
      String? pickedAuthor;
      for (final entry in byAuthor.entries) {
        final queue = entry.value;
        if (queue.isEmpty) continue;
        if (entry.key == lastAuthor) continue;
        picked = queue.removeAt(0);
        pickedAuthor = entry.key;
        break;
      }
      picked ??= () {
        for (final entry in byAuthor.entries) {
          final queue = entry.value;
          if (queue.isEmpty) continue;
          pickedAuthor = entry.key;
          return queue.removeAt(0);
        }
        return null;
      }();
      if (picked == null) break;
      result.add(picked);
      lastAuthor = pickedAuthor;
    }
    return result;
  }

  Future<Map<String, double>> _loadNewsAuthorAffinity({
    required String currentUserId,
    required Set<String> candidateAuthorIds,
  }) async {
    if (candidateAuthorIds.isEmpty) return const <String, double>{};
    final authorScores = <String, double>{};

    Future<void> addSignal({
      required String table,
      required double weight,
    }) async {
      final rows = await _client
          .from(table)
          .select('post_id')
          .eq('user_id', currentUserId)
          .limit(400);
      final postIds = (rows as List<dynamic>)
          .map((e) => (e as Map<String, dynamic>)['post_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList(growable: false);
      if (postIds.isEmpty) return;
      for (final chunk in _chunkList(postIds, 120)) {
        final postRows = await _client
            .from(SupabaseConstants.postsTable)
            .select('id,user_id')
            .inFilter('id', chunk);
        for (final row in (postRows as List<dynamic>)) {
          final map = row as Map<String, dynamic>;
          final authorId = (map['user_id'] ?? '').toString();
          if (authorId.isEmpty || !candidateAuthorIds.contains(authorId)) continue;
          authorScores[authorId] = (authorScores[authorId] ?? 0) + weight;
        }
      }
    }

    await addSignal(
      table: SupabaseConstants.postLikesTable,
      weight: 1.0,
    );
    await addSignal(
      table: SupabaseConstants.repostsTable,
      weight: 1.8,
    );
    await addSignal(
      table: SupabaseConstants.postSavesTable,
      weight: 1.5,
    );
    _normalize01(authorScores);
    return authorScores;
  }

  double _newsSmartScore(PostEntity post, DateTime now) {
    final ageHours = now.difference(post.createdAt).inMinutes / 60.0;
    final freshness = math.exp(-ageHours / 20.0); // strong boost for recent posts
    final engagementRaw =
        (post.likesCount * 1.0) + (post.commentsCount * 2.0) + (post.repostsCount * 2.4);
    final engagement = math.log(1 + engagementRaw) / 4.5;
    final hasMedia = post.videoUrl != null && post.videoUrl!.isNotEmpty || post.displayImageUrls.isNotEmpty;
    final mediaBoost = hasMedia ? 0.08 : 0.0;
    return freshness * 0.64 + engagement * 0.33 + mediaBoost;
  }

  @override
  Future<List<PostEntity>> getPostsByUser(String userId, {String? currentUserId}) async {
    var res = await _client
        .from(SupabaseConstants.postsTable)
        .select('*, users!user_id(name, avatar)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    var list =
        (res as List).map((e) => _mapPost(e as Map<String, dynamic>)).toList();
    if (list.isEmpty) {
      final plainRes = await _client
          .from(SupabaseConstants.postsTable)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      list = (plainRes as List)
          .map((e) => _mapPost(e as Map<String, dynamic>))
          .toList();
    }
    if (currentUserId != null && list.isNotEmpty) {
      final ids = list.map((e) => e.id).toList();
      final likes = await _client
          .from(SupabaseConstants.postLikesTable)
          .select('post_id')
          .eq('user_id', currentUserId)
          .inFilter('post_id', ids);
      final saves = await _client
          .from(SupabaseConstants.postSavesTable)
          .select('post_id')
          .eq('user_id', currentUserId)
          .inFilter('post_id', ids);
      final likedIds = (likes as List).map((e) => (e as Map)['post_id'] as String).toSet();
      final savedIds = (saves as List).map((e) => (e as Map)['post_id'] as String).toSet();
      return list
          .map((p) => PostModel(
                id: p.id,
                userId: p.userId,
                kind: p.kind,
                imageUrl: p.imageUrl,
                imageUrls: p.imageUrls,
                caption: p.caption,
                videoUrl: p.videoUrl,
                videoDurationSeconds: p.videoDurationSeconds,
                createdAt: p.createdAt,
                likesCount: p.likesCount,
                dislikesCount: p.dislikesCount,
                commentsCount: p.commentsCount,
                viewsCount: p.viewsCount,
                repostsCount: p.repostsCount,
                userName: p.userName,
                userAvatarUrl: p.userAvatarUrl,
                isLikedByMe: likedIds.contains(p.id),
                isDislikedByMe: p.isDislikedByMe,
                isRepostedByMe: p.isRepostedByMe,
                isSavedByMe: savedIds.contains(p.id),
              ))
          .toList();
    }
    return list;
  }

  PostEntity _mapPost(Map<String, dynamic> json) {
    final users = json['users'];
    Map<String, dynamic>? userMap;
    if (users is Map) {
      userMap = Map<String, dynamic>.from(users);
    }
    final row = Map<String, dynamic>.from(json)
      ..remove('users')
      ..['user_name'] = userMap?['name']
      ..['user_avatar'] = userMap?['avatar'];
    return PostModel.fromJson(row);
  }

  @override
  Future<PostEntity> createPost({
    required String userId,
    String imageUrl = '',
    List<String> imageUrls = const [],
    String caption = '',
    String? videoUrl,
    int videoDurationSeconds = 0,
    String kind = 'news',
  }) async {
    final normalizedKind = kind.trim().toLowerCase() == 'news'
        ? 'news'
        : 'publication';
    final urls = imageUrls.isNotEmpty
        ? imageUrls
        : (imageUrl.isNotEmpty ? <String>[imageUrl] : <String>[]);
    final primaryImage = urls.isNotEmpty ? urls.first : '';
    final data = <String, dynamic>{
      'user_id': userId,
      'image_url': primaryImage,
      'caption': caption,
      'kind': normalizedKind,
      'image_urls': urls.length > 1 ? urls : <String>[],
    };
    if (videoUrl != null && videoUrl.isNotEmpty) {
      data['video_url'] = videoUrl;
      data['video_duration_seconds'] = videoDurationSeconds;
    }
    final res = await _client
        .from(SupabaseConstants.postsTable)
        .insert(data)
        .select('*, users!user_id(name, avatar)')
        .single();
    final created = _mapPost(Map<String, dynamic>.from(res as Map));

    if (created.kind == normalizedKind) return created;

    // "Железная" защита от смешивания kind в БД:
    // если запись вернулась с неверным kind — принудительно обновляем и подтверждаем чтением.
    await _client
        .from(SupabaseConstants.postsTable)
        .update({'kind': normalizedKind})
        .eq('id', created.id);

    final verify = await _client
        .from(SupabaseConstants.postsTable)
        .select('*, users!user_id(name, avatar)')
        .eq('id', created.id)
        .single();

    final verified = _mapPost(Map<String, dynamic>.from(verify as Map));
    if (verified.kind != normalizedKind) {
      throw Exception(
        'Post kind mismatch after update: expected=$normalizedKind, got=${verified.kind}',
      );
    }
    return verified;
  }

  @override
  Future<void> toggleLike(String postId, String userId) async {
    final existing = await _client
        .from(SupabaseConstants.postLikesTable)
        .select('post_id')
        .eq('post_id', postId)
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) {
      await _client
          .from(SupabaseConstants.postLikesTable)
          .delete()
          .eq('post_id', postId)
          .eq('user_id', userId);
    } else {
      await _client.from(SupabaseConstants.postLikesTable).insert({
        'post_id': postId,
        'user_id': userId,
      });
      await _createPostLikeNotification(postId: postId, actorId: userId);
    }
  }

  @override
  Future<void> toggleDislike(String postId, String userId) async {
    final existing = await _client
        .from(SupabaseConstants.postDislikesTable)
        .select('post_id')
        .eq('post_id', postId)
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) {
      await _client
          .from(SupabaseConstants.postDislikesTable)
          .delete()
          .eq('post_id', postId)
          .eq('user_id', userId);
    } else {
      await _client.from(SupabaseConstants.postDislikesTable).insert({
        'post_id': postId,
        'user_id': userId,
      });
    }
  }

  @override
  Future<void> toggleRepost(String postId, String userId) async {
    final existing = await _client
        .from(SupabaseConstants.repostsTable)
        .select('post_id')
        .eq('post_id', postId)
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) {
      await _client
          .from(SupabaseConstants.repostsTable)
          .delete()
          .eq('post_id', postId)
          .eq('user_id', userId);
    } else {
      await _client.from(SupabaseConstants.repostsTable).insert({
        'post_id': postId,
        'user_id': userId,
      });
      await _createPostRepostNotification(postId: postId, actorId: userId);
    }
  }

  @override
  Future<void> toggleSave(String postId, String userId) async {
    final existing = await _client
        .from(SupabaseConstants.postSavesTable)
        .select('post_id')
        .eq('post_id', postId)
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) {
      await _client
          .from(SupabaseConstants.postSavesTable)
          .delete()
          .eq('post_id', postId)
          .eq('user_id', userId);
    } else {
      await _client.from(SupabaseConstants.postSavesTable).insert({
        'post_id': postId,
        'user_id': userId,
      });
    }
  }

  @override
  Future<List<PostEntity>> getSavedPublications(
    String userId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final saves = await _client
        .from(SupabaseConstants.postSavesTable)
        .select('post_id, created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    final postIds = (saves as List)
        .map((e) => (e as Map<String, dynamic>)['post_id'] as String?)
        .whereType<String>()
        .toList(growable: false);
    if (postIds.isEmpty) return const [];

    final res = await _client
        .from(SupabaseConstants.postsTable)
        .select('*, users!user_id(name, avatar)')
        .eq('kind', 'publication')
        .inFilter('id', postIds);
    final list = (res as List)
        .map((e) => _mapPost(e as Map<String, dynamic>))
        .toList(growable: false);
    final order = {for (var i = 0; i < postIds.length; i++) postIds[i]: i};
    list.sort((a, b) => (order[a.id] ?? 1 << 20).compareTo(order[b.id] ?? 1 << 20));

    return list
        .map(
          (p) => PostModel(
            id: p.id,
            userId: p.userId,
            kind: p.kind,
            imageUrl: p.imageUrl,
            imageUrls: p.imageUrls,
            caption: p.caption,
            videoUrl: p.videoUrl,
            videoDurationSeconds: p.videoDurationSeconds,
            createdAt: p.createdAt,
            likesCount: p.likesCount,
            dislikesCount: p.dislikesCount,
            commentsCount: p.commentsCount,
            viewsCount: p.viewsCount,
            repostsCount: p.repostsCount,
            userName: p.userName,
            userAvatarUrl: p.userAvatarUrl,
            isLikedByMe: p.isLikedByMe,
            isDislikedByMe: p.isDislikedByMe,
            isRepostedByMe: p.isRepostedByMe,
            isSavedByMe: true,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<PostEntity>> getLikedPublications(
    String userId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final likes = await _client
        .from(SupabaseConstants.postLikesTable)
        .select('post_id, created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    final postIds = (likes as List)
        .map((e) => (e as Map<String, dynamic>)['post_id'] as String?)
        .whereType<String>()
        .toList(growable: false);
    if (postIds.isEmpty) return const [];

    final res = await _client
        .from(SupabaseConstants.postsTable)
        .select('*, users!user_id(name, avatar)')
        .eq('kind', 'publication')
        .inFilter('id', postIds);
    final list = (res as List)
        .map((e) => _mapPost(e as Map<String, dynamic>))
        .toList(growable: false);
    final order = {for (var i = 0; i < postIds.length; i++) postIds[i]: i};
    list.sort((a, b) => (order[a.id] ?? 1 << 20).compareTo(order[b.id] ?? 1 << 20));

    return list
        .map(
          (p) => PostModel(
            id: p.id,
            userId: p.userId,
            kind: p.kind,
            imageUrl: p.imageUrl,
            imageUrls: p.imageUrls,
            caption: p.caption,
            videoUrl: p.videoUrl,
            videoDurationSeconds: p.videoDurationSeconds,
            createdAt: p.createdAt,
            likesCount: p.likesCount,
            dislikesCount: p.dislikesCount,
            commentsCount: p.commentsCount,
            viewsCount: p.viewsCount,
            repostsCount: p.repostsCount,
            userName: p.userName,
            userAvatarUrl: p.userAvatarUrl,
            isLikedByMe: true,
            isDislikedByMe: p.isDislikedByMe,
            isRepostedByMe: p.isRepostedByMe,
            isSavedByMe: p.isSavedByMe,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<PostCommentEntity>> getComments(String postId) async {
    final res = await _client
        .from(SupabaseConstants.postCommentsTable)
        .select('*, users!user_id(name, avatar)')
        .eq('post_id', postId)
        .order('created_at', ascending: true);
    final list = (res as List)
        .map((e) {
          final m = e as Map<String, dynamic>;
          final users = m['users'];
          Map<String, dynamic>? u;
          if (users is Map) u = Map<String, dynamic>.from(users);
          final row = Map<String, dynamic>.from(m)
            ..remove('users')
            ..['user_name'] = u?['name']
            ..['user_avatar'] = u?['avatar'];
          return PostCommentModel.fromJson(row);
        })
        .toList();
    final idToName = {for (final c in list) c.id: c.userName};
    return list.map((c) {
      if (c.parentId == null) return c as PostCommentEntity;
      return c.copyWith(replyToUserName: idToName[c.parentId]);
    }).toList();
  }

  @override
  Future<void> addComment({
    required String postId,
    required String userId,
    required String text,
    String? parentCommentId,
  }) async {
    final data = <String, dynamic>{
      'post_id': postId,
      'user_id': userId,
      'text': text,
    };
    if (parentCommentId != null && parentCommentId.isNotEmpty) {
      data['parent_id'] = parentCommentId;
    }
    try {
      final inserted = await _client
          .from(SupabaseConstants.postCommentsTable)
          .insert(data)
          .select('id')
          .single();
      final commentId = inserted['id'] as String;
      await _createPostCommentNotification(
        postId: postId,
        actorId: userId,
        text: text,
        commentId: commentId,
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (data.containsKey('parent_id') && (msg.contains('parent_id') || (msg.contains('column') && msg.contains('exist')))) {
        data.remove('parent_id');
        final inserted = await _client
            .from(SupabaseConstants.postCommentsTable)
            .insert(data)
            .select('id')
            .single();
        final commentId = inserted['id'] as String;
        await _createPostCommentNotification(
          postId: postId,
          actorId: userId,
          text: text,
          commentId: commentId,
        );
        throw const PostCommentReplyFallbackException();
      } else {
        rethrow;
      }
    }
  }

  @override
  Future<List<PostEntity>> searchPostsByCursor({
    required String query,
    int limit = 10,
    DateTime? lastCreatedAt,
    String? currentUserId,
  }) async {
    final normalizedQuery = query.trim();
    final hasQuery = normalizedQuery.isNotEmpty;
    final res = await (lastCreatedAt == null
        ? (hasQuery
            ? _client
                .from(SupabaseConstants.postsTable)
                .select('*, users!user_id(name, avatar)')
                .ilike('caption', '%$normalizedQuery%')
                .order('created_at', ascending: false)
                .limit(limit)
            : _client
                .from(SupabaseConstants.postsTable)
                .select('*, users!user_id(name, avatar)')
                .order('created_at', ascending: false)
                .limit(limit))
        : (hasQuery
            ? _client
                .from(SupabaseConstants.postsTable)
                .select('*, users!user_id(name, avatar)')
                .ilike('caption', '%$normalizedQuery%')
                .lt('created_at', lastCreatedAt.toIso8601String())
                .order('created_at', ascending: false)
                .limit(limit)
            : _client
                .from(SupabaseConstants.postsTable)
                .select('*, users!user_id(name, avatar)')
                .lt('created_at', lastCreatedAt.toIso8601String())
                .order('created_at', ascending: false)
                .limit(limit)));
    final list = (res as List)
        .map((e) => _mapPost(e as Map<String, dynamic>))
        .toList(growable: false);

    if (currentUserId == null || list.isEmpty) return list;

    final ids = list.map((e) => e.id).toList(growable: false);
    final likes = await _client
        .from(SupabaseConstants.postLikesTable)
        .select('post_id')
        .eq('user_id', currentUserId)
        .inFilter('post_id', ids);
    final reposts = await _client
        .from(SupabaseConstants.repostsTable)
        .select('post_id')
        .eq('user_id', currentUserId)
        .inFilter('post_id', ids);
    final saves = await _client
        .from(SupabaseConstants.postSavesTable)
        .select('post_id')
        .eq('user_id', currentUserId)
        .inFilter('post_id', ids);

    final likedIds =
        (likes as List).map((e) => (e as Map)['post_id'] as String).toSet();
    final repostedIds =
        (reposts as List).map((e) => (e as Map)['post_id'] as String).toSet();
    final savedIds =
        (saves as List).map((e) => (e as Map)['post_id'] as String).toSet();

    return list
        .map(
          (p) => PostModel(
            id: p.id,
            userId: p.userId,
            kind: p.kind,
            imageUrl: p.imageUrl,
            imageUrls: p.imageUrls,
            caption: p.caption,
            videoUrl: p.videoUrl,
            videoDurationSeconds: p.videoDurationSeconds,
            createdAt: p.createdAt,
            likesCount: p.likesCount,
            dislikesCount: p.dislikesCount,
            commentsCount: p.commentsCount,
            viewsCount: p.viewsCount,
            repostsCount: p.repostsCount,
            userName: p.userName,
            userAvatarUrl: p.userAvatarUrl,
            isLikedByMe: likedIds.contains(p.id),
            isDislikedByMe: p.isDislikedByMe,
            isRepostedByMe: repostedIds.contains(p.id),
            isSavedByMe: savedIds.contains(p.id),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<PostEntity>> searchPublicationsByCursor({
    required String query,
    int limit = 10,
    DateTime? lastCreatedAt,
    String? currentUserId,
    bool videoPublicationsOnly = false,
  }) async {
    final normalizedQuery = query.trim();
    final hasQuery = normalizedQuery.isNotEmpty;
    try {
      dynamic qb = _client
          .from(SupabaseConstants.postsTable)
          .select('*, users!user_id(name, avatar)')
          .eq('kind', 'publication');
      if (videoPublicationsOnly) {
        qb = qb.not('video_url', 'is', null).neq('video_url', '');
      }
      if (hasQuery) {
        qb = qb.ilike('caption', '%$normalizedQuery%');
      }
      if (lastCreatedAt != null) {
        qb = qb.lt('created_at', lastCreatedAt.toIso8601String());
      }
      final res = await qb
          .order('created_at', ascending: false)
          .limit(limit);

      final list = (res as List)
          .map((e) => _mapPost(e as Map<String, dynamic>))
          .toList(growable: false);
      if (currentUserId == null || list.isEmpty) return list;
      final ids = list.map((e) => e.id).toList(growable: false);
      final likes = await _client
          .from(SupabaseConstants.postLikesTable)
          .select('post_id')
          .eq('user_id', currentUserId)
          .inFilter('post_id', ids);
      final reposts = await _client
          .from(SupabaseConstants.repostsTable)
          .select('post_id')
          .eq('user_id', currentUserId)
          .inFilter('post_id', ids);
      final saves = await _client
          .from(SupabaseConstants.postSavesTable)
          .select('post_id')
          .eq('user_id', currentUserId)
          .inFilter('post_id', ids);
      final likedIds =
          (likes as List).map((e) => (e as Map)['post_id'] as String).toSet();
      final repostedIds = (reposts as List)
          .map((e) => (e as Map)['post_id'] as String)
          .toSet();
      final savedIds =
          (saves as List).map((e) => (e as Map)['post_id'] as String).toSet();
      return list
          .map(
            (p) => PostModel(
              id: p.id,
              userId: p.userId,
              kind: p.kind,
              imageUrl: p.imageUrl,
              imageUrls: p.imageUrls,
              caption: p.caption,
              videoUrl: p.videoUrl,
              videoDurationSeconds: p.videoDurationSeconds,
              createdAt: p.createdAt,
              likesCount: p.likesCount,
              dislikesCount: p.dislikesCount,
              commentsCount: p.commentsCount,
              viewsCount: p.viewsCount,
              repostsCount: p.repostsCount,
              userName: p.userName,
              userAvatarUrl: p.userAvatarUrl,
              isLikedByMe: likedIds.contains(p.id),
              isDislikedByMe: p.isDislikedByMe,
              isRepostedByMe: repostedIds.contains(p.id),
              isSavedByMe: savedIds.contains(p.id),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<PostEntity?> getPostById(String postId, {String? currentUserId}) async {
    final res = await _client
        .from(SupabaseConstants.postsTable)
        .select('*, users!user_id(name, avatar)')
        .eq('id', postId)
        .maybeSingle();
    if (res == null) return null;
    final post = _mapPost(Map<String, dynamic>.from(res as Map));
    if (currentUserId != null) {
      final like = await _client
          .from(SupabaseConstants.postLikesTable)
          .select('post_id')
          .eq('post_id', postId)
          .eq('user_id', currentUserId)
          .maybeSingle();
      final repost = await _client
          .from(SupabaseConstants.repostsTable)
          .select('post_id')
          .eq('post_id', postId)
          .eq('user_id', currentUserId)
          .maybeSingle();
      final save = await _client
          .from(SupabaseConstants.postSavesTable)
          .select('post_id')
          .eq('post_id', postId)
          .eq('user_id', currentUserId)
          .maybeSingle();
      return PostModel(
        id: post.id,
        userId: post.userId,
        kind: post.kind,
        imageUrl: post.imageUrl,
        imageUrls: post.imageUrls,
        caption: post.caption,
        videoUrl: post.videoUrl,
        videoDurationSeconds: post.videoDurationSeconds,
        createdAt: post.createdAt,
        likesCount: post.likesCount,
        dislikesCount: post.dislikesCount,
        commentsCount: post.commentsCount,
        viewsCount: post.viewsCount,
        repostsCount: post.repostsCount,
        userName: post.userName,
        userAvatarUrl: post.userAvatarUrl,
        isLikedByMe: like != null,
        isDislikedByMe: post.isDislikedByMe,
        isRepostedByMe: repost != null,
        isSavedByMe: save != null,
      );
    }
    return post;
  }

  @override
  Future<void> updatePost({
    required String postId,
    String? caption,
    String? imageUrl,
    String? videoUrl,
    int? videoDurationSeconds,
    bool clearImage = false,
    bool clearVideo = false,
  }) async {
    final data = <String, dynamic>{};
    if (caption != null) data['caption'] = caption;
    if (imageUrl != null) data['image_url'] = imageUrl;
    if (clearImage) data['image_url'] = '';
    if (videoUrl != null) data['video_url'] = videoUrl;
    if (clearVideo) {
      data['video_url'] = null;
      data['video_duration_seconds'] = 0;
    }
    if (videoDurationSeconds != null) data['video_duration_seconds'] = videoDurationSeconds;
    if (data.isEmpty) return;
    await _client.from(SupabaseConstants.postsTable).update(data).eq('id', postId);
  }

  @override
  Future<void> deletePost(String postId, String userId) async {
    await _client
        .from(SupabaseConstants.postsTable)
        .delete()
        .eq('id', postId)
        .eq('user_id', userId);
  }

  @override
  Future<void> deletePostComment(String commentId, String userId) async {
    await _client
        .from(SupabaseConstants.postCommentsTable)
        .delete()
        .eq('id', commentId)
        .eq('user_id', userId);
  }

  @override
  Future<void> togglePostCommentLike(String commentId, String userId) async {
    final existing = await _client
        .from(SupabaseConstants.postCommentLikesTable)
        .select('comment_id')
        .eq('comment_id', commentId)
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) {
      await _client
          .from(SupabaseConstants.postCommentLikesTable)
          .delete()
          .eq('comment_id', commentId)
          .eq('user_id', userId);
    } else {
      await _client.from(SupabaseConstants.postCommentLikesTable).insert({
        'comment_id': commentId,
        'user_id': userId,
      });
    }
  }

  @override
  Future<bool> isPostCommentLikedOwn(String commentId, String userId) async {
    final row = await _client
        .from(SupabaseConstants.postCommentLikesTable)
        .select('comment_id')
        .eq('comment_id', commentId)
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
  }

  Future<void> _createPostRepostNotification({
    required String postId,
    required String actorId,
  }) async {
    final postOwnerId = await _findPostOwnerId(postId);
    if (postOwnerId == null || postOwnerId == actorId) return;
    await _client.from(SupabaseConstants.notificationsTable).insert({
      'user_id': postOwnerId,
      'actor_id': actorId,
      'type': 'post_repost',
      'title': 'Репост',
      'body': 'Поделились вашей публикацией [post:$postId]',
      'post_id': postId,
    });
  }

  Future<void> _createPostLikeNotification({
    required String postId,
    required String actorId,
  }) async {
    final postOwnerId = await _findPostOwnerId(postId);
    if (postOwnerId == null || postOwnerId == actorId) return;
    await _client.from(SupabaseConstants.notificationsTable).insert({
      'user_id': postOwnerId,
      'actor_id': actorId,
      'type': 'post_like',
      'title': 'Новый лайк',
      'body': 'Вашу публикацию лайкнули [post:$postId]',
      'post_id': postId,
    });
  }

  Future<void> _createPostCommentNotification({
    required String postId,
    required String actorId,
    required String text,
    required String commentId,
  }) async {
    final postOwnerId = await _findPostOwnerId(postId);
    if (postOwnerId == null || postOwnerId == actorId) return;
    final body = text.trim().isEmpty
        ? 'Новый комментарий к вашей публикации [post:$postId]'
        : 'Комментарий: ${text.trim()} [post:$postId]';
    await _client.from(SupabaseConstants.notificationsTable).insert({
      'user_id': postOwnerId,
      'actor_id': actorId,
      'type': 'post_comment',
      'title': 'Новый комментарий',
      'body': body,
      'post_id': postId,
      'comment_id': commentId,
    });
  }

  Future<String?> _findPostOwnerId(String postId) async {
    final post = await _client
        .from(SupabaseConstants.postsTable)
        .select('user_id')
        .eq('id', postId)
        .maybeSingle();
    if (post == null) return null;
    return post['user_id'] as String?;
  }
}

class _RecommendationSignals {
  const _RecommendationSignals({
    required this.authorNorm,
    required this.hashtagNorm,
  });

  final Map<String, double> authorNorm;
  final Map<String, double> hashtagNorm;
}
