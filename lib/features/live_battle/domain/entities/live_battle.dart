class LiveBattle {
  const LiveBattle({
    required this.id,
    required this.hostA,
    required this.hostB,
    required this.scoreA,
    required this.scoreB,
    required this.endTime,
    required this.isActive,
  });

  final String id;
  final String hostA;
  final String hostB;
  final int scoreA;
  final int scoreB;
  final DateTime endTime;
  final bool isActive;
}
