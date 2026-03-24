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
    on<NewsToggleRepost>(_onToggleRepost);
    on<NewsRefresh>(_onRefresh);
  }

  final PostRepository _repository;
  static const int _pageSize = 20;

  Future<void> _onLoaded(NewsLoaded event, Emitter<NewsState> emit) async {
    emit(NewsLoading());
    try {
      final list = await _repository.getNewsPosts(
        limit: _pageSize,
        offset: 0,
        currentUserId: event.currentUserId,
      );
      final newsOnly = list
          .where((p) => p.kind.trim().toLowerCase() == 'news')
          .toList(growable: false);
      if (!isClosed) {
        emit(NewsSuccess(newsOnly, hasMore: list.length >= _pageSize));
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
      final list = await _repository.getNewsPosts(
        limit: _pageSize,
        offset: offset,
        currentUserId: null,
      );
      final newsOnly = list
          .where((p) => p.kind.trim().toLowerCase() == 'news')
          .toList(growable: false);
      final newList = [...current.posts, ...newsOnly];
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
    final updated = current.posts.map((p) {
      if (p.id != event.postId) return p;
      return p.copyWith(
        likesCount: p.isLikedByMe ? p.likesCount - 1 : p.likesCount + 1,
        isLikedByMe: !p.isLikedByMe,
      );
    }).toList();
    if (!isClosed) emit(current.copyWith(posts: updated));
    try {
      await _repository.toggleLike(event.postId, event.userId);
    } catch (_) {
      if (!isClosed) emit(current);
    }
  }

  Future<void> _onToggleRepost(NewsToggleRepost event, Emitter<NewsState> emit) async {
    final current = state;
    if (current is! NewsSuccess) return;
    try {
      await _repository.toggleRepost(event.postId, event.userId);
      final updated = current.posts.map((p) {
        if (p.id != event.postId) return p;
        final isNowReposted = !p.isRepostedByMe;
        return p.copyWith(
          repostsCount:
              isNowReposted ? p.repostsCount + 1 : (p.repostsCount > 0 ? p.repostsCount - 1 : 0),
          isRepostedByMe: isNowReposted,
        );
      }).toList();
      if (!isClosed) emit(current.copyWith(posts: updated));
    } catch (_) {}
  }

  Future<void> _onRefresh(NewsRefresh event, Emitter<NewsState> emit) async {
    add(NewsLoaded(currentUserId: event.currentUserId));
  }
}
