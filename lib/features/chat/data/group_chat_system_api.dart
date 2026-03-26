import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/supabase_constants.dart';

/// Системные строки в [chat_group_messages] (как события в Instagram).
abstract final class GroupChatSystemApi {
  static Future<void> notifyGroupCreated(
    SupabaseClient client, {
    required String groupId,
    required String ownerId,
    required String title,
  }) async {
    await client.from(SupabaseConstants.chatGroupMessagesTable).insert({
      'group_id': groupId,
      'sender_id': ownerId,
      'text': 'Группа «$title» создана',
      'kind': 'system_created',
    });
  }

  static Future<void> notifyMemberJoined(
    SupabaseClient client, {
    required String groupId,
    required String ownerId,
    required String memberName,
  }) async {
    await client.from(SupabaseConstants.chatGroupMessagesTable).insert({
      'group_id': groupId,
      'sender_id': ownerId,
      'text': '$memberName присоединился(ась) к группе',
      'kind': 'system_join',
    });
  }

  static Future<void> notifyMemberRemoved(
    SupabaseClient client, {
    required String groupId,
    required String ownerId,
    required String memberName,
  }) async {
    await client.from(SupabaseConstants.chatGroupMessagesTable).insert({
      'group_id': groupId,
      'sender_id': ownerId,
      'text': '$memberName удалён(а) из группы',
      'kind': 'system_removed',
    });
  }

  /// Участник сам выходит (sender_id = этот пользователь).
  static Future<void> notifySelfLeft(
    SupabaseClient client, {
    required String groupId,
    required String userId,
    required String displayName,
  }) async {
    await client.from(SupabaseConstants.chatGroupMessagesTable).insert({
      'group_id': groupId,
      'sender_id': userId,
      'text': '$displayName вышел(ла) из группы',
      'kind': 'system_leave',
    });
  }
}
