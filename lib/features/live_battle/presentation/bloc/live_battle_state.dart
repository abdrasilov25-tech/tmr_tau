import '../../domain/entities/donator_score.dart';
import '../../domain/entities/gift.dart';
import '../../domain/entities/live_battle.dart';
import '../../domain/entities/wallet.dart';

class LiveBattleState {
  const LiveBattleState({
    this.loading = true,
    this.battle,
    this.wallet,
    this.gifts = const <Gift>[],
    this.topDonators = const <DonatorScore>[],
    this.error,
    this.remainingSeconds = 0,
    this.lastLikeAt,
  });

  final bool loading;
  final LiveBattle? battle;
  final Wallet? wallet;
  final List<Gift> gifts;
  final List<DonatorScore> topDonators;
  final String? error;
  final int remainingSeconds;
  final DateTime? lastLikeAt;

  String? get mvpUserId => topDonators.isEmpty ? null : topDonators.first.userId;

  LiveBattleState copyWith({
    bool? loading,
    LiveBattle? battle,
    Wallet? wallet,
    List<Gift>? gifts,
    List<DonatorScore>? topDonators,
    String? error,
    int? remainingSeconds,
    DateTime? lastLikeAt,
  }) {
    return LiveBattleState(
      loading: loading ?? this.loading,
      battle: battle ?? this.battle,
      wallet: wallet ?? this.wallet,
      gifts: gifts ?? this.gifts,
      topDonators: topDonators ?? this.topDonators,
      error: error,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      lastLikeAt: lastLikeAt ?? this.lastLikeAt,
    );
  }
}
