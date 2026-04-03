import 'dart:math' as math;

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
    on<NewsVotePoll>(_onVotePoll);
    on<NewsToggleLike>(_onToggleLike);
    on<NewsToggleRepost>(_onToggleRepost);
    on<NewsRefresh>(_onRefresh);
    on<NewsCleared>(_onCleared);
  }

  final PostRepository _repository;
  static const int _pageSize = 20;

  void _onCleared(NewsCleared event, Emitter<NewsState> emit) {
    emit(NewsInitial());
  }

  Future<void> _onLoaded(NewsLoaded event, Emitter<NewsState> emit) async {
    await _fetchFirstPage(
      emit,
      currentUserId: event.currentUserId,
      silent: event.silent,
      cityFilter: event.cityFilter,
    );
  }

  Future<void> _fetchFirstPage(
    Emitter<NewsState> emit, {
    required String? currentUserId,
    required bool silent,
    String? cityFilter,
  }) async {
    final previous = state;
    if (!silent || previous is! NewsSuccess) {
      emit(NewsLoading());
    }
    try {
      final list = await _repository.getNewsPosts(
        limit: _pageSize,
        offset: 0,
        currentUserId: currentUserId,
        cityFilter: cityFilter,
      );
      final newsOnly = list
          .where((p) => p.kind.trim().toLowerCase() == 'news')
          .toList(growable: false);
      if (!isClosed) {
        emit(NewsSuccess(
          newsOnly,
          hasMore: list.length >= _pageSize,
          selectedCity: cityFilter,
        ));
      }
    } catch (e) {
      if (!isClosed) {
        if (silent && previous is NewsSuccess) {
          return;
        }
        emit(NewsFailure(e.toString()));
      }
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
        currentUserId: event.currentUserId,
        cityFilter: current.selectedCity,
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
          selectedCity: current.selectedCity,
        ));
      }
    } catch (_) {
      if (!isClosed) emit(current.copyWith(isLoadingMore: false));
    }
  }

  Future<void> _onVotePoll(NewsVotePoll event, Emitter<NewsState> emit) async {
    final current = state;
    if (current is! NewsSuccess) return;
    final idx =
        current.posts.indexWhere((p) => p.id == event.postId);
    if (idx < 0) return;
    final post = current.posts[idx];
    if (!post.hasPoll) return;
    final n = post.pollOptions.length;
    if (event.optionIndex < 0 || event.optionIndex >= n) return;

    final newCounts = List<int>.from(
      post.pollVoteCounts.length == n
          ? post.pollVoteCounts
          : List<int>.filled(n, 0),
    );
    final oldIdx = post.myPollVoteIndex;
    if (oldIdx != null && oldIdx >= 0 && oldIdx < n) {
      newCounts[oldIdx] = math.max(0, newCounts[oldIdx] - 1);
    }
    newCounts[event.optionIndex] += 1;

    final optimistic = current.posts
        .map(
          (p) => p.id == event.postId
              ? p.copyWith(
                  pollVoteCounts: newCounts,
                  myPollVoteIndex: event.optionIndex,
                )
              : p,
        )
        .toList(growable: false);
    final previous = current;
    emit(current.copyWith(posts: optimistic));
    try {
      await _repository.voteNewsPoll(
        postId: event.postId,
        userId: event.userId,
        optionIndex: event.optionIndex,
      );
    } catch (_) {
      if (!isClosed) emit(previous);
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
    final currentCity = event.cityFilter ??
        (state is NewsSuccess ? (state as NewsSuccess).selectedCity : null);
    await _fetchFirstPage(
      emit,
      currentUserId: event.currentUserId,
      silent: true,
      cityFilter: currentCity,
    );
  }
}
