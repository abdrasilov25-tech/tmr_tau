import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../domain/entities/notification_entity.dart';
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
            'id, user_id, actor_id, type, title, body, product_id, post_id, comment_id, read_at, created_at, '
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
  Future<NotificationUnreadSummary> getUnreadSummary(String userId) async {
    final results = await Future.wait([
      _countUnread(userId),
      _countUnreadTypes(userId, [
        'post_like',
        'product_like',
        'product_favorite',
      ]),
      _countUnreadTypes(userId, ['post_comment', 'product_comment']),
      _countUnreadTypes(userId, ['post_repost', 'product_repost']),
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
}
