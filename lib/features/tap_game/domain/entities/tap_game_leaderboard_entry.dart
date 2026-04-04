import 'package:equatable/equatable.dart';

class TapGameLeaderboardEntry extends Equatable {
  const TapGameLeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.score,
    this.shieldActive = false,
  });

  final int rank;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int score;
  final bool shieldActive;

  @override
  List<Object?> get props =>
      [rank, userId, displayName, avatarUrl, score, shieldActive];
}
