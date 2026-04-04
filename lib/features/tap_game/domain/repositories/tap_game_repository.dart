import '../entities/tap_game_leaderboard_entry.dart';
import '../entities/tap_game_play_state.dart';
import '../entities/tap_game_session_info.dart';

/// «Тап судьбы»: сессии, очки через RPC, Qarmet через [spendQarmet].
abstract class TapGameRepository {
  Future<String> getOrCreateSessionId();

  Future<TapGameSessionInfo?> fetchSession(String sessionId);

  /// Серверный анти-чит (токен-бакет) + расход энергии. [delta] 1 или 2 (буст).
  Future<TapGameTapResult> addScore({
    required String sessionId,
    required int delta,
  });

  /// Списание Qarmet и начисление энергии в одной транзакции на сервере.
  Future<TapGameStaminaPurchaseResult> purchaseStamina({
    required String sessionId,
    required int tier,
  });

  Future<void> applyBoost(String sessionId);

  Future<int> applyJump(String sessionId);

  Future<void> applyShield(String sessionId);

  Future<void> finalizeSession(String sessionId);

  /// Возвращает начисленные Qarmet (500/300/100) или 0, если не топ-3 / уже забрано.
  Future<int> claimMyReward(String sessionId);

  Future<List<TapGameLeaderboardEntry>> fetchLeaderboard(
    String sessionId, {
    int limit = 10,
  });

  Future<int> spendQarmet({required int amount, required String reason});

  Future<TapGameMyPlayState?> fetchMyPlayState({
    required String sessionId,
    required String userId,
  });
}
