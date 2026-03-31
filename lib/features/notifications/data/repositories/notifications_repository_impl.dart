import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../domain/entities/notification_entity.dart';
import '../../domain/entities/notification_feed_unread_counts.dart';
import '../../domain/entities/top_user_rank_entity.dart';
import '../../domain/entities/notification_unread_summary.dart';
import '../../domain/repositories/notifications_repository.dart';
import '../models/notification_model.dart';

class NotificationsRepositoryImpl implements NotificationsRepository {
  NotificationsRepositoryImpl(this._client);
  final SupabaseClient _client;

  /// Точное число непрочитанных (без загрузки строк — без лимита PostgREST на выборку).
  Future<int> _countUnread(
    String userId, {
    String? type,
  }) async {
    var q = _client
        .from(SupabaseConstants.notificationsTable)
        .count(CountOption.exact)
        .eq('user_id', userId)
        .isFilter('read_at', null);
    if (type != null) {
      q = q.eq('type', type);
    }
    return q;
  }

  Future<int> _countUnreadTypes(String userId, List<String> types) async {
    if (types.isEmpty) return 0;
    if (types.length == 1) return _countUnread(userId, type: types.first);
    final orClause = types.map((t) => 'type.eq.$t').join(',');
    return _client
        .from(SupabaseConstants.notificationsTable)
        .count(CountOption.exact)
        .eq('user_id', userId)
        .isFilter('read_at', null)
        .or(orClause);
  }

  Future<List<String>> _previewAvatarUrlsForUnread(String userId) async {
    dynamic res;
    try {
      res = await _client
          .from(SupabaseConstants.notificationsTable)
          .select(
            'actor:users!notifications_actor_id_fkey(avatar)',
          )
          .eq('user_id', userId)
          .isFilter('read_at', null)
          .order('created_at', ascending: false)
          .limit(32);
    } catch (_) {
      return [];
    }
    final out = <String>[];
    final seen = <String>{};
    for (final raw in res as List) {
      if (out.length >= 3) break;
      final m = raw as Map<String, dynamic>;
      final actor = m['actor'];
      if (actor is Map) {
        final url = actor['avatar'] as String?;
        if (url != null && url.isNotEmpty && seen.add(url)) {
          out.add(url);
        }
      }
    }
    return out;
  }

  @override
  Future<List<NotificationEntity>> getNotifications(String userId,
      {int limit = 100, int offset = 0}) async {
    dynamic res;
    try {
      res = await _client
          .from(SupabaseConstants.notificationsTable)
          .select(
            'id, user_id, actor_id, type, title, body, product_id, post_id, story_id, comment_id, read_at, created_at, '
            'actor:users!notifications_actor_id_fkey(name, avatar), '
            'post:posts!notifications_post_id_fkey(image_url, video_url, kind), '
            'product:products!notifications_product_id_fkey(image_url)',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
    } catch (_) {
      res = await _client
          .from(SupabaseConstants.notificationsTable)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
    }
    return (res as List)
        .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> markAsRead(String notificationId, String userId) async {
    await _client
        .from(SupabaseConstants.notificationsTable)
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('id', notificationId)
        .eq('user_id', userId);
  }

  @override
  Future<void> markAsReadMany(List<String> notificationIds, String userId) async {
    if (notificationIds.isEmpty) return;
    await _client
        .from(SupabaseConstants.notificationsTable)
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('user_id', userId)
        .inFilter('id', notificationIds);
  }

  @override
  Future<void> markAllAsRead(String userId) async {
    await _client
        .from(SupabaseConstants.notificationsTable)
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('user_id', userId)
        .isFilter('read_at', null);
  }

  @override
  Future<int> getUnreadCount(String userId) async {
    return _countUnread(userId);
  }

  @override
  Future<NotificationFeedUnreadCounts> getFeedUnreadCounts(String userId) async {
    try {
      final res = await _client.rpc(
        'notification_feed_unread_counts',
        params: {'p_user_id': userId},
      );
      final rows = res as List;
      if (rows.isEmpty) {
        return const NotificationFeedUnreadCounts(publications: 0, news: 0);
      }
      final row = rows.first as Map<String, dynamic>;
      final p =
          (row['publications_count'] as num?)?.toInt() ??
          (row['publicationsCount'] as num?)?.toInt() ??
          0;
      final n =
          (row['news_count'] as num?)?.toInt() ??
          (row['newsCount'] as num?)?.toInt() ??
          0;
      return NotificationFeedUnreadCounts(publications: p, news: n);
    } catch (_) {
      return const NotificationFeedUnreadCounts(publications: 0, news: 0);
    }
  }

  @override
  Future<NotificationUnreadSummary> getUnreadSummary(String userId) async {
    final results = await Future.wait([
      _countUnread(userId),
      _countUnreadTypes(userId, [
        'post_like',
        'product_like',
        'product_favorite',
        'story_like',
      ]),
      _countUnreadTypes(userId, ['post_comment', 'product_comment', 'story_reply']),
      _countUnreadTypes(userId, ['post_repost', 'product_repost', 'post_mention_story']),
      _previewAvatarUrlsForUnread(userId),
    ]);

    final totalUnread = results[0] as int;
    final likes = results[1] as int;
    final comments = results[2] as int;
    final reposts = results[3] as int;
    final avatarUrls = results[4] as List<String>;

    return NotificationUnreadSummary(
      unreadLikes: likes,
      unreadComments: comments,
      unreadReposts: reposts,
      totalUnread: totalUnread,
      previewAvatarUrls: avatarUrls,
    );
  }

  @override
  Future<List<TopUserRankEntity>> getTopUsersByLikes({int limit = 20}) async {
    dynamic res;
    try {
      res = await _client
          .from(SupabaseConstants.usersTable)
          .select('id, name, avatar, followers_count, total_received_post_likes')
          .order('total_received_post_likes', ascending: false)
          .order('followers_count', ascending: false)
          .limit(limit);
    } on PostgrestException catch (_) {
      // Fallback for old schema without total_received_post_likes.
      res = await _client
          .from(SupabaseConstants.usersTable)
          .select('id, name, avatar, followers_count')
          .order('followers_count', ascending: false)
          .limit(limit);
    }
    return (res as List)
        .map((raw) {
          final m = Map<String, dynamic>.from(raw as Map);
          return TopUserRankEntity(
            userId: (m['id'] as String?) ?? '',
            name: (m['name'] as String?)?.trim().isNotEmpty == true
                ? (m['name'] as String)
                : 'Пользователь',
            avatarUrl: m['avatar'] as String?,
            followersCount: (m['followers_count'] as num?)?.toInt() ?? 0,
            totalLikes: (m['total_received_post_likes'] as num?)?.toInt() ?? 0,
          );
        })
        .where((e) => e.userId.isNotEmpty)
        .toList(growable: false);
  }
}
