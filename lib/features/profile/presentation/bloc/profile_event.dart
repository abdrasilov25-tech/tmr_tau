part of 'profile_bloc.dart';

sealed class ProfileEvent extends Equatable {
  const ProfileEvent();
  @override
  List<Object?> get props => [];
}

final class ProfileLoadRequested extends ProfileEvent {
  const ProfileLoadRequested(this.sellerId, {this.currentUserId});
  final String sellerId;
  final String? currentUserId;
  @override
  List<Object?> get props => [sellerId, currentUserId];
}

final class ProfileToggleFollow extends ProfileEvent {
  const ProfileToggleFollow({
    required this.followerId,
    required this.followingId,
  });
  final String followerId;
  final String followingId;
  @override
  List<Object?> get props => [followerId, followingId];
}
