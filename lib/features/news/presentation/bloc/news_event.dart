part of 'news_bloc.dart';

sealed class NewsEvent extends Equatable {
  const NewsEvent();
  @override
  List<Object?> get props => [];
}

final class NewsLoaded extends NewsEvent {
  const NewsLoaded({this.currentUserId, this.silent = false, this.cityFilter});

  final String? currentUserId;
  final String? cityFilter;

  /// Без полноэкранного [NewsLoading] — для pull-to-refresh и фоновой подгрузки.
  final bool silent;

  @override
  List<Object?> get props => [currentUserId, silent, cityFilter];
}

final class NewsLoadMore extends NewsEvent {
  const NewsLoadMore({this.currentUserId});
  final String? currentUserId;
  @override
  List<Object?> get props => [currentUserId];
}

final class NewsVotePoll extends NewsEvent {
  const NewsVotePoll({
    required this.postId,
    required this.userId,
    required this.optionIndex,
  });
  final String postId;
  final String userId;
  final int optionIndex;
  @override
  List<Object?> get props => [postId, userId, optionIndex];
}

final class NewsToggleLike extends NewsEvent {
  const NewsToggleLike({required this.postId, required this.userId});
  final String postId;
  final String userId;
}

final class NewsToggleRepost extends NewsEvent {
  const NewsToggleRepost({required this.postId, required this.userId});
  final String postId;
  final String userId;
}

final class NewsToggleFollow extends NewsEvent {
  const NewsToggleFollow({
    required this.followerId,
    required this.followingId,
  });
  final String followerId;
  final String followingId;
  @override
  List<Object?> get props => [followerId, followingId];
}

final class NewsRefresh extends NewsEvent {
  const NewsRefresh({this.currentUserId, this.cityFilter});
  final String? currentUserId;
  final String? cityFilter;
}

final class NewsCleared extends NewsEvent {
  const NewsCleared();
}

final class NewsRemovePost extends NewsEvent {
  const NewsRemovePost({required this.postId});
  final String postId;
  @override
  List<Object?> get props => [postId];
}
