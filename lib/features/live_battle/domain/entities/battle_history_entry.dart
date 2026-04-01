class BattleHistoryEntry {
  const BattleHistoryEntry({
    required this.battleId,
    required this.winnerId,
    required this.scoreA,
    required this.scoreB,
    required this.maybeMvpSenderId,
    required this.createdAt,
  });

  final String battleId;
  final String? winnerId;
  final int scoreA;
  final int scoreB;
  final String? maybeMvpSenderId;
  final DateTime createdAt;
}
