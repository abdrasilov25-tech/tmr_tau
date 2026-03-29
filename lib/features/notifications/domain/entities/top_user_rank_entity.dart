import 'package:equatable/equatable.dart';

class TopUserRankEntity extends Equatable {
  const TopUserRankEntity({
    required this.userId,
    required this.name,
    required this.totalLikes,
    this.avatarUrl,
    this.followersCount = 0,
  });

  final String userId;
  final String name;
  final int totalLikes;
  final String? avatarUrl;
  final int followersCount;

  @override
  List<Object?> get props => [
        userId,
        name,
        totalLikes,
        avatarUrl,
        followersCount,
      ];
}
