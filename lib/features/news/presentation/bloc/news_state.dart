part of 'news_bloc.dart';

sealed class NewsState extends Equatable {
  const NewsState();
  @override
  List<Object?> get props => [];
}

final class NewsInitial extends NewsState {}

final class NewsLoading extends NewsState {}

final class NewsSuccess extends NewsState {
  const NewsSuccess(
    this.posts, {
    this.hasMore = false,
    this.isLoadingMore = false,
    this.currentUserId,
  });
  final List<PostEntity> posts;
  final bool hasMore;
  final bool isLoadingMore;
  final String? currentUserId;

  NewsSuccess copyWith({
    List<PostEntity>? posts,
    bool? hasMore,
    bool? isLoadingMore,
    String? currentUserId,
  }) =>
      NewsSuccess(
        posts ?? this.posts,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        currentUserId: currentUserId ?? this.currentUserId,
      );

  @override
  List<Object?> get props => [posts, hasMore, isLoadingMore, currentUserId];
}

final class NewsFailure extends NewsState {
  const NewsFailure(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
