import '../entities/battle_history_entry.dart';
import '../entities/donator_score.dart';
import '../entities/gift.dart';
import '../entities/live_battle.dart';
import '../entities/wallet.dart';

abstract class LiveBattleRepository {
  Future<LiveBattle> startBattle(String userA, String userB);

  /// Одноразовая загрузка строки баттла (не ждём первый пуш Realtime).
  Future<LiveBattle?> fetchBattle(String battleId);
  Future<void> sendLike({
    required String battleId,
    required String userId,
    required String targetHost,
  });
  Future<void> sendGift({
    required String battleId,
    required String giftId,
    required String senderId,
    required String targetHost,
  });

  Future<int> getBalance(String userId);
  Future<int> addQarmet(String userId, int amount);
  Future<int> deductQarmet(String userId, int amount);
  Future<Wallet> getWallet(String userId);

  Future<List<Gift>> getGifts();
  Stream<LiveBattle> watchBattle(String battleId);
  Stream<List<DonatorScore>> watchTopDonators(String battleId);
  Future<List<BattleHistoryEntry>> getBattleHistory(String userId);
  Future<void> finishBattle(String battleId);
}
