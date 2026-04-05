import '../entities/tap_game_leaderboard_entry.dart';
import '../entities/tap_game_local_hall_entry.dart';

/// Персистентный топ‑50 на устройстве (SharedPreferences).
abstract class TapGameLocalHallRepository {
  static const int maxEntries = 50;

  Future<List<TapGameLocalHallEntry>> getTop50();

  /// Объединяет строки лидерборда сессии: для каждого userId хранится max(score).
  Future<void> mergeFromLeaderboard(List<TapGameLeaderboardEntry> entries);

  /// Фиксирует лучший результат текущего пользователя (после синка с сервером).
  Future<void> recordMyBestScore({
    required String userId,
    required String displayName,
    String? avatarUrl,
    required int score,
  });
}
