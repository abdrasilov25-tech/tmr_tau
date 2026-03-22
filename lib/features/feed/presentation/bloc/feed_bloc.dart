import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:postgrest/postgrest.dart';
import '../../../../core/storage/local_reactions_storage.dart';
import '../../../../features/product/domain/entities/product_entity.dart';
import '../../../../features/product/data/models/product_model.dart';
import '../../domain/repositories/feed_repository.dart';

part 'feed_event.dart';
part 'feed_state.dart';

class FeedBloc extends Bloc<FeedEvent, FeedState> {
  FeedBloc(this._repository, this._localReactions) : super(FeedInitial()) {
    on<FeedLoaded>(_onLoaded);
    on<FeedLoadMore>(_onLoadMore);
    on<FeedToggleLike>(_onToggleLike);
    on<FeedToggleFollow>(_onToggleFollow);
    on<FeedToggleRepost>(_onToggleRepost);
    on<FeedProductRemoved>(_onProductRemoved);
  }

  final FeedRepository _repository;
  final LocalReactionsStorage _localReactions;
  static const int _pageSize = 20;

  Future<void> _onLoaded(FeedLoaded event, Emitter<FeedState> emit) async {
    emit(FeedLoading());
    try {
      var list = await _repository.getFeed(
        limit: _pageSize,
        offset: 0,
        currentUserId: event.currentUserId,
      );
      list = _mergeLocalReactions(list);
      if (!isClosed) {
        emit(FeedSuccess(list, hasMore: list.length >= _pageSize));
      }
    } catch (e, st) {
      if (e is PostgrestException) {
        debugPrint('FeedBloc Postgrest: ${e.message} (code: ${e.code})');
      } else {
        debugPrint('FeedBloc error: $e');
      }
      debugPrint('FeedBloc stack: $st');
      if (!isClosed) emit(FeedFailure(e.toString()));
    }
  }

  Future<void> _onLoadMore(FeedLoadMore event, Emitter<FeedState> emit) async {
    final current = state;
    if (current is! FeedSuccess || !current.hasMore || current.isLoadingMore) {
      return;
    }
    emit(current.copyWith(isLoadingMore: true));
    try {
      final offset = current.products.length;
      final list = await _repository.getFeed(
        limit: _pageSize,
        offset: offset,
        currentUserId: event.currentUserId,
      );
      var newList = [...current.products, ...list];
      newList = _mergeLocalReactions(newList);
      if (!isClosed) {
        emit(FeedSuccess(
          newList,
          hasMore: list.length >= _pageSize,
          isLoadingMore: false,
        ));
      }
    } catch (e) {
      if (!isClosed) emit(current.copyWith(isLoadingMore: false));
    }
  }

  void _onProductRemoved(
    FeedProductRemoved event,
    Emitter<FeedState> emit,
  ) {
    final current = state;
    if (current is! FeedSuccess) return;
    final filtered = current.products
        .where((p) => p.id != event.productId)
        .toList(growable: false);
    emit(current.copyWith(products: filtered));
  }

  List<ProductEntity> _mergeLocalReactions(List<ProductEntity> list) {
    final likedIds = _localReactions.getLikedIds();
    final repostedIds = _localReactions.getRepostedIds();
    if (likedIds.isEmpty && repostedIds.isEmpty) return list;
    return list.map((p) {
      final fromLocalLike = likedIds.contains(p.id);
      final fromLocalRepost = repostedIds.contains(p.id);
      if (!fromLocalLike && !fromLocalRepost) return p;
      return ProductModel.fromEntity(
        p,
        isLikedByMe: p.isLikedByMe || fromLocalLike,
        isRepostedByMe: p.isRepostedByMe || fromLocalRepost,
      );
    }).toList();
  }

  Future<void> _onToggleLike(
      FeedToggleLike event, Emitter<FeedState> emit) async {
    final current = state;
    if (current is! FeedSuccess) return;
    final p = current.products.firstWhere((e) => e.id == event.productId);
    final isNowLiked = !p.isLikedByMe;
    await _localReactions.setLiked(event.productId, isNowLiked);
    final updated = current.products.map((p) {
      if (p.id != event.productId) return p;
      return ProductModel.fromEntity(
        p,
        likesCount: p.isLikedByMe ? p.likesCount - 1 : p.likesCount + 1,
        isLikedByMe: isNowLiked,
      );
    }).toList();
    if (!isClosed) emit(current.copyWith(products: updated));
    try {
      await _repository.toggleProductLike(event.productId, event.userId);
    } catch (e, st) {
      if (e is PostgrestException) {
        debugPrint('FeedBloc toggleLike: ${e.message}');
      } else {
        debugPrint('FeedBloc toggleLike error: $e');
      }
      debugPrint('FeedBloc toggleLike stack: $st');
    }
  }

  Future<void> _onToggleFollow(
      FeedToggleFollow event, Emitter<FeedState> emit) async {
    final current = state;
    if (current is! FeedSuccess) return;
    // Оптимистично обновляем UI, запрос в БД выполняем "в фоне".
    final updated = current.products.map((p) {
      if (p.sellerId != event.followingId) return p;
      return ProductModel.fromEntity(
        p,
        isFollowingSeller: !p.isFollowingSeller,
      );
    }).toList();
    if (!isClosed) emit(current.copyWith(products: updated));

    // Запрос к репозиторию выполняем без ожидания, чтобы не блокировать UI.
    unawaited(_repository.toggleFollow(event.followerId, event.followingId));
  }

  Future<void> _onToggleRepost(
      FeedToggleRepost event, Emitter<FeedState> emit) async {
    final current = state;
    if (current is! FeedSuccess) return;
    final p = current.products.firstWhere((e) => e.id == event.productId);
    final isNowReposted = !p.isRepostedByMe;
    await _localReactions.setReposted(event.productId, isNowReposted);
    final updated = current.products.map((p) {
      if (p.id != event.productId) return p;
      final newCount = isNowReposted
          ? p.repostsCount + 1
          : (p.repostsCount > 0 ? p.repostsCount - 1 : 0);
      return ProductModel.fromEntity(
        p,
        repostsCount: newCount,
        isRepostedByMe: isNowReposted,
      );
    }).toList();
    if (!isClosed) emit(current.copyWith(products: updated));
    try {
      await _repository.toggleProductRepost(event.productId, event.userId);
    } catch (e) {
      if (e is PostgrestException) {
        debugPrint('FeedBloc toggleRepost: ${e.message}');
      } else {
        debugPrint('FeedBloc toggleRepost error: $e');
      }
    }
  }
}
