import 'package:equatable/equatable.dart';

/// Represents a user that the current user has blocked.
class BlockedUserEntity extends Equatable {
  const BlockedUserEntity({
    required this.blockedUserId,
    this.blockedUserName,
    this.blockedUserAvatarUrl,
    required this.blockedAt,
  });

  final String blockedUserId;
  final String? blockedUserName;
  final String? blockedUserAvatarUrl;

  final DateTime blockedAt;

  @override
  List<Object?> get props => [
        blockedUserId,
        blockedUserName,
        blockedUserAvatarUrl,
        blockedAt,
      ];
}

