import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/entities/blocked_user_entity.dart';
import '../domain/repositories/settings_repository.dart';

sealed class BlockedUsersState {
  const BlockedUsersState();
}

class BlockedUsersInitial extends BlockedUsersState {
  const BlockedUsersInitial();
}

class BlockedUsersLoading extends BlockedUsersState {
  const BlockedUsersLoading();
}

class BlockedUsersFailure extends BlockedUsersState {
  const BlockedUsersFailure(this.message);
  final String message;
}

class BlockedUsersSuccess extends BlockedUsersState {
  const BlockedUsersSuccess({
    required this.items,
    required this.hasMore,
    required this.lastBlockedAt,
    required this.isLoadingMore,
    this.unblockingUserId,
  });

  final List<BlockedUserEntity> items;
  final bool hasMore;
  final DateTime? lastBlockedAt;
  final bool isLoadingMore;
  final String? unblockingUserId;

  BlockedUsersSuccess copyWith({
    List<BlockedUserEntity>? items,
    bool? hasMore,
    Object? lastBlockedAt = _unset,
    bool? isLoadingMore,
    Object? unblockingUserId = _unset,
  }) {
    return BlockedUsersSuccess(
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      lastBlockedAt: identical(lastBlockedAt, _unset)
          ? this.lastBlockedAt
          : lastBlockedAt as DateTime?,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      unblockingUserId: identical(unblockingUserId, _unset)
          ? this.unblockingUserId
          : unblockingUserId as String?,
    );
  }
}

const _unset = Object();

class BlockedUsersCubit extends Cubit<BlockedUsersState> {
  BlockedUsersCubit(
    this._repository, {
    required String blockerId,
    int pageSize = 20,
  })  : _blockerId = blockerId,
        _pageSize = pageSize,
        super(const BlockedUsersInitial());

  final SettingsRepository _repository;
  final String _blockerId;
  final int _pageSize;

  int _requestVersion = 0;

  Future<void> loadInitial() async {
    _requestVersion++;
    final localVersion = _requestVersion;

    emit(const BlockedUsersLoading());
    try {
      final list = await _repository.getBlockedUsersCursor(
        blockerId: _blockerId,
        limit: _pageSize,
        lastBlockedAt: null,
      );

      if (localVersion != _requestVersion) return;
      final last = list.isNotEmpty ? list.last.blockedAt : null;

      emit(
        BlockedUsersSuccess(
          items: list,
          hasMore: list.length == _pageSize,
          lastBlockedAt: last,
          isLoadingMore: false,
          unblockingUserId: null,
        ),
      );
    } catch (e) {
      if (localVersion != _requestVersion) return;
      emit(BlockedUsersFailure(e.toString()));
    }
  }

  Future<void> loadMore() async {
    final current = state;
    if (current is! BlockedUsersSuccess) return;
    if (current.isLoadingMore || !current.hasMore) return;

    _requestVersion++;
    final localVersion = _requestVersion;
    emit(current.copyWith(isLoadingMore: true));

    try {
      final list = await _repository.getBlockedUsersCursor(
        blockerId: _blockerId,
        limit: _pageSize,
        lastBlockedAt: current.lastBlockedAt,
      );

      if (localVersion != _requestVersion) return;
      final merged = [...current.items, ...list];
      final last = merged.isNotEmpty ? merged.last.blockedAt : null;

      emit(
        current.copyWith(
          items: merged,
          hasMore: list.length == _pageSize,
          lastBlockedAt: last,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      if (localVersion != _requestVersion) return;
      emit(current.copyWith(isLoadingMore: false));
    }
  }

  Future<void> unblock(String blockedUserId) async {
    final current = state;
    if (current is! BlockedUsersSuccess) return;
    if (current.unblockingUserId != null) return;

    emit(current.copyWith(unblockingUserId: blockedUserId));
    try {
      await _repository.unblockUser(
        blockerId: _blockerId,
        blockedUserId: blockedUserId,
      );
      await loadInitial();
    } catch (e) {
      emit(current.copyWith(unblockingUserId: null));
      emit(BlockedUsersFailure(e.toString()));
    }
  }
}

