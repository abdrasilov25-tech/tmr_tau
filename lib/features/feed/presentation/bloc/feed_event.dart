part of 'feed_bloc.dart';

sealed class FeedEvent extends Equatable {
  const FeedEvent();
  @override
  List<Object?> get props => [];
}

final class FeedLoaded extends FeedEvent {
  const FeedLoaded({this.currentUserId});
  final String? currentUserId;
  @override
  List<Object?> get props => [currentUserId];
}

final class FeedLoadMore extends FeedEvent {
  const FeedLoadMore({this.currentUserId});
  final String? currentUserId;
  @override
  List<Object?> get props => [currentUserId];
}

final class FeedToggleLike extends FeedEvent {
  const FeedToggleLike({required this.productId, required this.userId});
  final String productId;
  final String userId;
  @override
  List<Object?> get props => [productId, userId];
}

final class FeedToggleRepost extends FeedEvent {
  const FeedToggleRepost({required this.productId, required this.userId});
  final String productId;
  final String userId;
  @override
  List<Object?> get props => [productId, userId];
}

final class FeedToggleFollow extends FeedEvent {
  const FeedToggleFollow({
    required this.followerId,
    required this.followingId,
  });
  final String followerId;
  final String followingId;
  @override
  List<Object?> get props => [followerId, followingId];
}

/// Товар удалён — убрать из кэша ленты (поиск/профиль обновляются отдельно).
final class FeedProductRemoved extends FeedEvent {
  const FeedProductRemoved({required this.productId});
  final String productId;
  @override
  List<Object?> get props => [productId];
}
