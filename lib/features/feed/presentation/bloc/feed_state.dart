part of 'feed_bloc.dart';

sealed class FeedState extends Equatable {
  const FeedState();
  @override
  List<Object?> get props => [];
}

final class FeedInitial extends FeedState {}

final class FeedLoading extends FeedState {}

final class FeedSuccess extends FeedState {
  const FeedSuccess(
    this.products, {
    this.hasMore = false,
    this.isLoadingMore = false,
  });
  final List<ProductEntity> products;
  final bool hasMore;
  final bool isLoadingMore;

  FeedSuccess copyWith({
    List<ProductEntity>? products,
    bool? hasMore,
    bool? isLoadingMore,
  }) =>
      FeedSuccess(
        products ?? this.products,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );

  @override
  List<Object?> get props => [products, hasMore, isLoadingMore];
}

final class FeedFailure extends FeedState {
  const FeedFailure(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
