import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/entities/post_report_entity.dart';
import '../domain/repositories/post_reports_repository.dart';

sealed class MyReportsState {
  const MyReportsState();
}

class MyReportsInitial extends MyReportsState {
  const MyReportsInitial();
}

class MyReportsLoading extends MyReportsState {
  const MyReportsLoading();
}

class MyReportsFailure extends MyReportsState {
  const MyReportsFailure(this.message);
  final String message;
}

class MyReportsSuccess extends MyReportsState {
  const MyReportsSuccess({
    required this.items,
    required this.hasMore,
    required this.lastCreatedAt,
    required this.isLoadingMore,
  });

  final List<PostReportEntity> items;
  final bool hasMore;
  final DateTime? lastCreatedAt;
  final bool isLoadingMore;

  MyReportsSuccess copyWith({
    List<PostReportEntity>? items,
    bool? hasMore,
    Object? lastCreatedAt = _unset,
    bool? isLoadingMore,
  }) {
    return MyReportsSuccess(
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      lastCreatedAt:
          identical(lastCreatedAt, _unset) ? this.lastCreatedAt : lastCreatedAt as DateTime?,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

const _unset = Object();

class MyReportsCubit extends Cubit<MyReportsState> {
  MyReportsCubit(
    this._repository, {
    required String reporterId,
    int pageSize = 10,
  })  : _reporterId = reporterId,
        _pageSize = pageSize,
        super(const MyReportsInitial());

  final PostReportsRepository _repository;
  final String _reporterId;
  final int _pageSize;

  int _requestVersion = 0;

  Future<void> loadInitial() async {
    _requestVersion++;
    final localVersion = _requestVersion;
    emit(const MyReportsLoading());

    try {
      final list = await _repository.getMyReportsCursor(
        reporterId: _reporterId,
        limit: _pageSize,
        lastCreatedAt: null,
      );

      if (localVersion != _requestVersion) return;
      final last = list.isNotEmpty ? list.last.createdAt : null;
      emit(
        MyReportsSuccess(
          items: list,
          hasMore: list.length == _pageSize,
          lastCreatedAt: last,
          isLoadingMore: false,
        ),
      );
    } catch (e) {
      if (localVersion != _requestVersion) return;
      emit(MyReportsFailure(e.toString()));
    }
  }

  Future<void> loadMore() async {
    final current = state;
    if (current is! MyReportsSuccess) return;
    if (current.isLoadingMore || !current.hasMore) return;

    _requestVersion++;
    final localVersion = _requestVersion;
    emit(current.copyWith(isLoadingMore: true));

    try {
      final list = await _repository.getMyReportsCursor(
        reporterId: _reporterId,
        limit: _pageSize,
        lastCreatedAt: current.lastCreatedAt,
      );

      if (localVersion != _requestVersion) return;
      final merged = [...current.items, ...list];
      final last = merged.isNotEmpty ? merged.last.createdAt : null;

      emit(
        current.copyWith(
          items: merged,
          hasMore: list.length == _pageSize,
          lastCreatedAt: last,
          isLoadingMore: false,
        ),
      );
    } catch (e) {
      if (localVersion != _requestVersion) return;
      emit(current.copyWith(isLoadingMore: false));
    }
  }
}

