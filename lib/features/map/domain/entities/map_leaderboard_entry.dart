import 'package:equatable/equatable.dart';

class MapLeaderboardEntry extends Equatable {
  const MapLeaderboardEntry({
    required this.userId,
    required this.userName,
    required this.score,
    this.userAvatarUrl,
    this.isMe = false,
  });

  final String userId;
  final String userName;
  final int score;
  final String? userAvatarUrl;
  final bool isMe;

  @override
  List<Object?> get props => [userId, score];
}
