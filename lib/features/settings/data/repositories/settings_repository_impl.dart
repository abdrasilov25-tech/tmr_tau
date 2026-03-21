import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/blocked_user_entity.dart';
import '../../domain/entities/login_history_entity.dart';
import '../../domain/entities/support_ticket_entity.dart';
import '../../domain/entities/user_session_entity.dart';
import '../../domain/entities/user_settings_entity.dart';
import '../../domain/repositories/settings_repository.dart';
import '../models/blocked_user_model.dart';
import '../models/login_history_model.dart';
import '../models/support_ticket_model.dart';
import '../models/user_session_model.dart';
import '../models/user_settings_model.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._client);

  final SupabaseClient _client;

  static const String _userSettingsTable = 'user_settings';
  static const String _blockedUsersTable = 'blocked_users';
  static const String _supportTicketsTable = 'support_tickets';
  static const String _loginHistoryTable = 'login_history';
  static const String _userSessionsTable = 'user_sessions';
  static const String _usersTable = 'users';

  UserSettingsEntity _defaults(String userId) {
    return UserSettingsEntity(
      userId: userId,
      pushNotificationsEnabled: true,
      emailNotificationsEnabled: true,
      inAppNotificationsEnabled: true,
      activityStatusEnabled: true,
      storyVisibility: 'followers',
      postVisibility: 'followers',
      twoFactorEnabled: false,
      updatedAt: null,
    );
  }

  @override
  Future<UserSettingsEntity> getMySettings({
    required String userId,
  }) async {
    final res = await _client
        .from(_userSettingsTable)
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (res == null) {
      final defaults = _defaults(userId);
      await upsertMySettings(settings: defaults);
      return defaults;
    }

    return UserSettingsModel.fromJson(res);
  }

  @override
  Future<void> upsertMySettings({
    required UserSettingsEntity settings,
  }) async {
    await _client.from(_userSettingsTable).upsert({
      'user_id': settings.userId,
      'push_notifications_enabled': settings.pushNotificationsEnabled,
      'email_notifications_enabled': settings.emailNotificationsEnabled,
      'in_app_notifications_enabled': settings.inAppNotificationsEnabled,
      'activity_status_enabled': settings.activityStatusEnabled,
      'story_visibility': settings.storyVisibility,
      'post_visibility': settings.postVisibility,
      'two_factor_enabled': settings.twoFactorEnabled,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<List<BlockedUserEntity>> getBlockedUsersCursor({
    required String blockerId,
    int limit = 20,
    DateTime? lastBlockedAt,
  }) async {
    final res = await (lastBlockedAt == null
        ? _client
            .from(_blockedUsersTable)
            .select('blocked_user_id, created_at')
            .eq('blocker_id', blockerId)
            .order('created_at', ascending: false)
            .limit(limit)
        : _client
            .from(_blockedUsersTable)
            .select('blocked_user_id, created_at')
            .eq('blocker_id', blockerId)
            .lt('created_at', lastBlockedAt.toIso8601String())
            .order('created_at', ascending: false)
            .limit(limit));

    final blockedRows = (res as List).cast<Map<String, dynamic>>();
    final blockedAtList = blockedRows
        .map((r) => BlockedUserModel.fromJson({
              'blocked_user_id': r['blocked_user_id'],
              'created_at': r['created_at'],
              // These will be resolved in the next query.
              'blocked_user_name': null,
              'blocked_user_avatar_url': null,
            }))
        .toList(growable: false);

    if (blockedAtList.isEmpty) return blockedAtList;

    final blockedIds = blockedAtList
        .map((e) => e.blockedUserId)
        .toList(growable: false);

    final usersRes = await _client
        .from(_usersTable)
        .select('id, name, avatar')
        .inFilter('id', blockedIds);

    final usersRows = (usersRes as List).cast<Map<String, dynamic>>();
    final userMap = <String, Map<String, dynamic>>{
      for (final u in usersRows) u['id'] as String: u,
    };

    return blockedAtList
        .map((b) {
          final u = userMap[b.blockedUserId];
          return BlockedUserEntity(
            blockedUserId: b.blockedUserId,
            blockedUserName: u?['name'] as String?,
            blockedUserAvatarUrl: u?['avatar'] as String?,
            blockedAt: b.blockedAt,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> blockUser({
    required String blockerId,
    required String blockedUserId,
  }) async {
    await _client.from(_blockedUsersTable).insert({
      'blocker_id': blockerId,
      'blocked_user_id': blockedUserId,
    });
  }

  @override
  Future<void> unblockUser({
    required String blockerId,
    required String blockedUserId,
  }) async {
    await _client
        .from(_blockedUsersTable)
        .delete()
        .eq('blocker_id', blockerId)
        .eq('blocked_user_id', blockedUserId);
  }

  @override
  Future<void> createSupportTicket({
    required String userId,
    required String title,
    required String description,
  }) async {
    await _client.from(_supportTicketsTable).insert({
      'user_id': userId,
      'title': title,
      'description': description,
    });
  }

  @override
  Future<List<SupportTicketEntity>> getMySupportTickets({
    required String userId,
    int limit = 10,
  }) async {
    final res = await _client
        .from(_supportTicketsTable)
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (res as List)
        .map((e) => SupportTicketModel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<List<LoginHistoryEntity>> getMyLoginHistory({
    required String userId,
    int limit = 20,
  }) async {
    final res = await _client
        .from(_loginHistoryTable)
        .select()
        .eq('user_id', userId)
        .order('logged_in_at', ascending: false)
        .limit(limit);

    return (res as List)
        .map((e) => LoginHistoryModel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<List<UserSessionEntity>> getMyUserSessions({
    required String userId,
    int limit = 20,
  }) async {
    final res = await _client
        .from(_userSessionsTable)
        .select()
        .eq('user_id', userId)
        .order('last_seen_at', ascending: false)
        .limit(limit);

    return (res as List)
        .map((e) => UserSessionModel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<void> clearSessionsAndLogout({
    required String userId,
  }) async {
    // We intentionally clear records first, so UI reflects the action.
    await _client.from(_loginHistoryTable).delete().eq('user_id', userId);
    await _client.from(_userSessionsTable).delete().eq('user_id', userId);
    await _client.auth.signOut();
  }
}

