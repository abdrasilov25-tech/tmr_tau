part of 'news_bloc.dart';

sealed class NewsEvent extends Equatable {
  const NewsEvent();
  @override
  List<Object?> get props => [];
}

final class NewsLoaded extends NewsEvent {
  const NewsLoaded({this.currentUserId});
  final String? currentUserId;
}

final class NewsLoadMore extends NewsEvent {}

final class NewsToggleLike extends NewsEvent {
  const NewsToggleLike({required this.postId, required this.userId});
  final String postId;
  final String userId;
}

final class NewsRefresh extends NewsEvent {
  const NewsRefresh({this.currentUserId});
  final String? currentUserId;
}
