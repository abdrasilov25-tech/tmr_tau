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
  });
  final List<PostEntity> posts;
  final bool hasMore;
  final bool isLoadingMore;

  NewsSuccess copyWith({
    List<PostEntity>? posts,
    bool? hasMore,
    bool? isLoadingMore,
  }) =>
      NewsSuccess(
        posts ?? this.posts,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );

  @override
  List<Object?> get props => [posts, hasMore, isLoadingMore];
}

final class NewsFailure extends NewsState {
  const NewsFailure(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
