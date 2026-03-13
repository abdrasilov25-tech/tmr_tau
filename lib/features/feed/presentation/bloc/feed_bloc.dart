import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:postgrest/postgrest.dart';
import '../../../../features/product/domain/entities/product_entity.dart';
import '../../../../features/product/data/models/product_model.dart';
import '../../domain/repositories/feed_repository.dart';

part 'feed_event.dart';
part 'feed_state.dart';

class FeedBloc extends Bloc<FeedEvent, FeedState> {
  FeedBloc(this._repository) : super(FeedInitial()) {
    on<FeedLoaded>(_onLoaded);
    on<FeedLoadMore>(_onLoadMore);
    on<FeedToggleLike>(_onToggleLike);
    on<FeedToggleFollow>(_onToggleFollow);
    on<FeedToggleRepost>(_onToggleRepost);
  }

  final FeedRepository _repository;
  static const int _pageSize = 20;

  Future<void> _onLoaded(FeedLoaded event, Emitter<FeedState> emit) async {
    emit(FeedLoading());
    try {
      final list = await _repository.getFeed(
        limit: _pageSize,
        offset: 0,
        currentUserId: event.currentUserId,
      );
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
      final newList = [...current.products, ...list];
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

  Future<void> _onToggleLike(
      FeedToggleLike event, Emitter<FeedState> emit) async {
    final current = state;
    if (current is! FeedSuccess) return;
    try {
      await _repository.toggleProductLike(event.productId, event.userId);
      final updated = current.products.map((p) {
        if (p.id != event.productId) return p;
        return ProductModel(
          id: p.id,
          title: p.title,
          description: p.description,
          price: p.price,
          imageUrl: p.imageUrl,
          sellerId: p.sellerId,
          category: p.category,
          likesCount: p.isLikedByMe ? p.likesCount - 1 : p.likesCount + 1,
          commentsCount: p.commentsCount,
          repostsCount: p.repostsCount,
          sellerName: p.sellerName,
          sellerAvatarUrl: p.sellerAvatarUrl,
          createdAt: p.createdAt,
          isLikedByMe: !p.isLikedByMe,
          isFollowingSeller: p.isFollowingSeller,
          isRepostedByMe: p.isRepostedByMe,
          sellerIsVerified: p.sellerIsVerified,
        );
      }).toList();
      if (!isClosed) emit(current.copyWith(products: updated));
    } catch (_) {}
  }

  Future<void> _onToggleFollow(
      FeedToggleFollow event, Emitter<FeedState> emit) async {
    final current = state;
    if (current is! FeedSuccess) return;
    // Оптимистично обновляем UI, запрос в БД выполняем "в фоне".
    final updated = current.products.map((p) {
      if (p.sellerId != event.followingId) return p;
      return ProductModel(
        id: p.id,
        title: p.title,
        description: p.description,
        price: p.price,
        imageUrl: p.imageUrl,
        sellerId: p.sellerId,
        category: p.category,
        likesCount: p.likesCount,
        commentsCount: p.commentsCount,
        repostsCount: p.repostsCount,
        sellerName: p.sellerName,
        sellerAvatarUrl: p.sellerAvatarUrl,
        createdAt: p.createdAt,
        isLikedByMe: p.isLikedByMe,
        isFollowingSeller: !p.isFollowingSeller,
        isRepostedByMe: p.isRepostedByMe,
        sellerIsVerified: p.sellerIsVerified,
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
    try {
      await _repository.toggleProductRepost(event.productId, event.userId);
      final updated = current.products.map((p) {
        if (p.id != event.productId) return p;
        final isNowReposted = !p.isRepostedByMe;
        final newCount = isNowReposted
            ? p.repostsCount + 1
            : (p.repostsCount > 0 ? p.repostsCount - 1 : 0);
        return ProductModel(
          id: p.id,
          title: p.title,
          description: p.description,
          price: p.price,
          imageUrl: p.imageUrl,
          sellerId: p.sellerId,
          category: p.category,
          likesCount: p.likesCount,
          commentsCount: p.commentsCount,
          repostsCount: newCount,
          sellerName: p.sellerName,
          sellerAvatarUrl: p.sellerAvatarUrl,
          createdAt: p.createdAt,
          isLikedByMe: p.isLikedByMe,
          isFollowingSeller: p.isFollowingSeller,
          isRepostedByMe: isNowReposted,
          sellerIsVerified: p.sellerIsVerified,
        );
      }).toList();
      if (!isClosed) emit(current.copyWith(products: updated));
    } catch (_) {}
  }
}
