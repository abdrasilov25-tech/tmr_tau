import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';

part 'news_event.dart';
part 'news_state.dart';

class NewsBloc extends Bloc<NewsEvent, NewsState> {
  NewsBloc(this._repository) : super(NewsInitial()) {
    on<NewsLoaded>(_onLoaded);
    on<NewsLoadMore>(_onLoadMore);
    on<NewsToggleLike>(_onToggleLike);
    on<NewsRefresh>(_onRefresh);
  }

  final PostRepository _repository;
  static const int _pageSize = 20;

  Future<void> _onLoaded(NewsLoaded event, Emitter<NewsState> emit) async {
    emit(NewsLoading());
    try {
      final list = await _repository.getFeedPosts(
        limit: _pageSize,
        offset: 0,
        currentUserId: event.currentUserId,
      );
      if (!isClosed) {
        emit(NewsSuccess(list, hasMore: list.length >= _pageSize));
      }
    } catch (e) {
      if (!isClosed) emit(NewsFailure(e.toString()));
    }
  }

  Future<void> _onLoadMore(NewsLoadMore event, Emitter<NewsState> emit) async {
    final current = state;
    if (current is! NewsSuccess || !current.hasMore || current.isLoadingMore) {
      return;
    }
    emit(current.copyWith(isLoadingMore: true));
    try {
      final offset = current.posts.length;
      final list = await _repository.getFeedPosts(
        limit: _pageSize,
        offset: offset,
        currentUserId: null,
      );
      final newList = [...current.posts, ...list];
      if (!isClosed) {
        emit(NewsSuccess(
          newList,
          hasMore: list.length >= _pageSize,
          isLoadingMore: false,
        ));
      }
    } catch (_) {
      if (!isClosed) emit(current.copyWith(isLoadingMore: false));
    }
  }

  Future<void> _onToggleLike(NewsToggleLike event, Emitter<NewsState> emit) async {
    final current = state;
    if (current is! NewsSuccess) return;
    try {
      await _repository.toggleLike(event.postId, event.userId);
      final updated = current.posts.map((p) {
        if (p.id != event.postId) return p;
        return PostEntity(
          id: p.id,
          userId: p.userId,
          imageUrl: p.imageUrl,
          caption: p.caption,
          videoUrl: p.videoUrl,
          videoDurationSeconds: p.videoDurationSeconds,
          createdAt: p.createdAt,
          likesCount: p.isLikedByMe ? p.likesCount - 1 : p.likesCount + 1,
          dislikesCount: p.dislikesCount,
          commentsCount: p.commentsCount,
          repostsCount: p.repostsCount,
          userName: p.userName,
          userAvatarUrl: p.userAvatarUrl,
          isLikedByMe: !p.isLikedByMe,
          isDislikedByMe: p.isDislikedByMe,
          isRepostedByMe: p.isRepostedByMe,
        );
      }).toList();
      if (!isClosed) emit(current.copyWith(posts: updated));
    } catch (_) {}
  }

  Future<void> _onRefresh(NewsRefresh event, Emitter<NewsState> emit) async {
    add(NewsLoaded(currentUserId: event.currentUserId));
  }
}
