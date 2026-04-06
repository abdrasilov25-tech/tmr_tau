import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/notification_entity.dart';
import '../../domain/repositories/notifications_repository.dart';

part 'notifications_event.dart';
part 'notifications_state.dart';

class NotificationsBloc extends Bloc<NotificationsEvent, NotificationsState> {
  NotificationsBloc(this._repository, this._userId)
      : super(NotificationsInitial()) {
    on<NotificationsRequested>(_onRequested);
    on<NotificationsMarkRead>(_onMarkRead);
    on<NotificationsMarkAllRead>(_onMarkAllRead);
  }

  final NotificationsRepository _repository;
  final String _userId;

  Future<void> _onRequested(
      NotificationsRequested event, Emitter<NotificationsState> emit) async {
    emit(NotificationsLoading());
    try {
      final list =
          await _repository.getNotifications(_userId, limit: 100, offset: 0);
      if (!isClosed) emit(NotificationsLoaded(list));
    } catch (e) {
      if (!isClosed) emit(NotificationsFailure(e.toString()));
    }
  }

  Future<void> _onMarkRead(
      NotificationsMarkRead event, Emitter<NotificationsState> emit) async {
    final current = state;
    if (current is! NotificationsLoaded) return;
    try {
      await _repository.markAsRead(event.id, _userId);
      final updated = current.notifications
          .map((n) => n.id == event.id
              ? NotificationEntity(
                  id: n.id,
                  userId: n.userId,
                  type: n.type,
                  createdAt: n.createdAt,
                  actorId: n.actorId,
                  actorName: n.actorName,
                  actorAvatarUrl: n.actorAvatarUrl,
                  title: n.title,
                  body: n.body,
                  productId: n.productId,
                  postId: n.postId,
                  subjectImageUrl: n.subjectImageUrl,
                  subjectVideoUrl: n.subjectVideoUrl,
                  relatedPostKind: n.relatedPostKind,
                  commentId: n.commentId,
                  readAt: DateTime.now(),
                )
              : n)
          .toList();
      if (!isClosed) emit(NotificationsLoaded(updated));
    } catch (e) { debugPrint('$e'); }
  }

  Future<void> _onMarkAllRead(
      NotificationsMarkAllRead event, Emitter<NotificationsState> emit) async {
    try {
      await _repository.markAllAsRead(_userId);
      add(NotificationsRequested());
    } catch (e) { debugPrint('$e'); }
  }
}
