part of 'notifications_bloc.dart';

sealed class NotificationsEvent extends Equatable {
  const NotificationsEvent();
  @override
  List<Object?> get props => [];
}

final class NotificationsRequested extends NotificationsEvent {}

final class NotificationsMarkRead extends NotificationsEvent {
  const NotificationsMarkRead(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

final class NotificationsMarkAllRead extends NotificationsEvent {}
