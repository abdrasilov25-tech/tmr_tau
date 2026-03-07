import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../domain/entities/notification_entity.dart';
import '../../domain/repositories/notifications_repository.dart';
import '../models/notification_model.dart';

class NotificationsRepositoryImpl implements NotificationsRepository {
  NotificationsRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<List<NotificationEntity>> getNotifications(String userId,
      {int limit = 50, int offset = 0}) async {
    final res = await _client
        .from(SupabaseConstants.notificationsTable)
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
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
  Future<void> markAllAsRead(String userId) async {
    await _client
        .from(SupabaseConstants.notificationsTable)
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('user_id', userId)
        .isFilter('read_at', null);
  }

  @override
  Future<int> getUnreadCount(String userId) async {
    final res = await _client
        .from(SupabaseConstants.notificationsTable)
        .select('id')
        .eq('user_id', userId)
        .isFilter('read_at', null);
    return (res as List).length;
  }
}
