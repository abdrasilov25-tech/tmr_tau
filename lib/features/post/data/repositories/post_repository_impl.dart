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
            caption: p.caption,
            videoUrl: p.videoUrl,
            videoDurationSeconds: p.videoDurationSeconds,
            createdAt: p.createdAt,
            likesCount: p.likesCount,
            dislikesCount: p.dislikesCount,
            commentsCount: p.commentsCount,
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
        .range(offset, offset + limit - 1);
    final list = (res as List)
        .map((e) => _mapPost(e as Map<String, dynamic>))
        .toList(growable: false);
    final enriched = await _applyPostUserState(list, me);
    return PublicationFeedPageResult(
      posts: enriched,
      nextOffset: offset + list.length,
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
    return scored.take(limit).map((e) => e.p).toList(growable: false);
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
    var res = await _client
        .from(SupabaseConstants.postsTable)
        .select('*, users!user_id(name, avatar)')
        .eq('kind', 'news')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    var list = (res as List)
        .map((e) => _mapPost(e as Map<String, dynamic>))
        .toList(growable: false);
    if (list.isEmpty) {
      final plainRes = await _client
          .from(SupabaseConstants.postsTable)
          .select()
          .eq('kind', 'news')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      list = (plainRes as List)
          .map((e) => _mapPost(e as Map<String, dynamic>))
          .toList(growable: false);
    }
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
            imageUrl: p.imageUrl,
            caption: p.caption,
            videoUrl: p.videoUrl,
            videoDurationSeconds: p.videoDurationSeconds,
            createdAt: p.createdAt,
            likesCount: p.likesCount,
            dislikesCount: p.dislikesCount,
            commentsCount: p.commentsCount,
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
                caption: p.caption,
                videoUrl: p.videoUrl,
                videoDurationSeconds: p.videoDurationSeconds,
                createdAt: p.createdAt,
                likesCount: p.likesCount,
                dislikesCount: p.dislikesCount,
                commentsCount: p.commentsCount,
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
    String caption = '',
    String? videoUrl,
    int videoDurationSeconds = 0,
    String kind = 'news',
  }) async {
    final normalizedKind = kind.trim().toLowerCase() == 'news'
        ? 'news'
        : 'publication';
    final data = <String, dynamic>{
      'user_id': userId,
      'image_url': imageUrl,
      'caption': caption,
      'kind': normalizedKind,
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
            caption: p.caption,
            videoUrl: p.videoUrl,
            videoDurationSeconds: p.videoDurationSeconds,
            createdAt: p.createdAt,
            likesCount: p.likesCount,
            dislikesCount: p.dislikesCount,
            commentsCount: p.commentsCount,
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
      await _client.from(SupabaseConstants.postCommentsTable).insert(data);
      await _createPostCommentNotification(
        postId: postId,
        actorId: userId,
        text: text,
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (data.containsKey('parent_id') && (msg.contains('parent_id') || (msg.contains('column') && msg.contains('exist')))) {
        data.remove('parent_id');
        await _client.from(SupabaseConstants.postCommentsTable).insert(data);
        await _createPostCommentNotification(
          postId: postId,
          actorId: userId,
          text: text,
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
            imageUrl: p.imageUrl,
            caption: p.caption,
            videoUrl: p.videoUrl,
            videoDurationSeconds: p.videoDurationSeconds,
            createdAt: p.createdAt,
            likesCount: p.likesCount,
            dislikesCount: p.dislikesCount,
            commentsCount: p.commentsCount,
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
  }) async {
    final normalizedQuery = query.trim();
    final hasQuery = normalizedQuery.isNotEmpty;
    try {
      final res = await (lastCreatedAt == null
          ? (hasQuery
              ? _client
                  .from(SupabaseConstants.postsTable)
                  .select('*, users!user_id(name, avatar)')
                  .eq('kind', 'publication')
                  .ilike('caption', '%$normalizedQuery%')
                  .order('created_at', ascending: false)
                  .limit(limit)
              : _client
                  .from(SupabaseConstants.postsTable)
                  .select('*, users!user_id(name, avatar)')
                  .eq('kind', 'publication')
                  .order('created_at', ascending: false)
                  .limit(limit))
          : (hasQuery
              ? _client
                  .from(SupabaseConstants.postsTable)
                  .select('*, users!user_id(name, avatar)')
                  .eq('kind', 'publication')
                  .ilike('caption', '%$normalizedQuery%')
                  .lt('created_at', lastCreatedAt.toIso8601String())
                  .order('created_at', ascending: false)
                  .limit(limit)
              : _client
                  .from(SupabaseConstants.postsTable)
                  .select('*, users!user_id(name, avatar)')
                  .eq('kind', 'publication')
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
              caption: p.caption,
              videoUrl: p.videoUrl,
              videoDurationSeconds: p.videoDurationSeconds,
              createdAt: p.createdAt,
              likesCount: p.likesCount,
              dislikesCount: p.dislikesCount,
              commentsCount: p.commentsCount,
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
        caption: post.caption,
        videoUrl: post.videoUrl,
        videoDurationSeconds: post.videoDurationSeconds,
        createdAt: post.createdAt,
        likesCount: post.likesCount,
        dislikesCount: post.dislikesCount,
        commentsCount: post.commentsCount,
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
    });
  }

  Future<void> _createPostCommentNotification({
    required String postId,
    required String actorId,
    required String text,
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
