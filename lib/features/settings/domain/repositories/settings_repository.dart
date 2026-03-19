import '../entities/blocked_user_entity.dart';
import '../entities/login_history_entity.dart';
import '../entities/support_ticket_entity.dart';
import '../entities/user_session_entity.dart';
import '../entities/user_settings_entity.dart';

abstract class SettingsRepository {
  /// Returns user settings row; if it doesn't exist, repository should return defaults.
  Future<UserSettingsEntity> getMySettings({
    required String userId,
  });

  /// Upserts settings row for the given user.
  Future<void> upsertMySettings({
    required UserSettingsEntity settings,
  });

  Future<List<BlockedUserEntity>> getBlockedUsersCursor({
    required String blockerId,
    int limit = 20,
    DateTime? lastBlockedAt,
  });

  Future<void> blockUser({
    required String blockerId,
    required String blockedUserId,
  });

  Future<void> unblockUser({
    required String blockerId,
    required String blockedUserId,
  });

  Future<void> createSupportTicket({
    required String userId,
    required String title,
    required String description,
  });

  Future<List<SupportTicketEntity>> getMySupportTickets({
    required String userId,
    int limit = 10,
  });

  Future<List<LoginHistoryEntity>> getMyLoginHistory({
    required String userId,
    int limit = 20,
  });

  Future<List<UserSessionEntity>> getMyUserSessions({
    required String userId,
    int limit = 20,
  });

  /// Clears stored session records (if any) and signs user out from Supabase.
  Future<void> clearSessionsAndLogout({
    required String userId,
  });
}

