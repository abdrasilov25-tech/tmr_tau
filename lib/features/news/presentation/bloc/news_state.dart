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
    this.selectedCity,
  });
  final List<PostEntity> posts;
  final bool hasMore;
  final bool isLoadingMore;
  final String? selectedCity;

  NewsSuccess copyWith({
    List<PostEntity>? posts,
    bool? hasMore,
    bool? isLoadingMore,
    String? selectedCity,
    bool clearCity = false,
  }) =>
      NewsSuccess(
        posts ?? this.posts,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        selectedCity: clearCity ? null : (selectedCity ?? this.selectedCity),
      );

  @override
  List<Object?> get props => [posts, hasMore, isLoadingMore, selectedCity];
}

final class NewsFailure extends NewsState {
  const NewsFailure(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
