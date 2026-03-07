part of 'notifications_bloc.dart';

sealed class NotificationsState extends Equatable {
  const NotificationsState();
  @override
  List<Object?> get props => [];
}

final class NotificationsInitial extends NotificationsState {}

final class NotificationsLoading extends NotificationsState {}

final class NotificationsLoaded extends NotificationsState {
  const NotificationsLoaded(this.notifications);
  final List<NotificationEntity> notifications;
  @override
  List<Object?> get props => [notifications];
}

final class NotificationsFailure extends NotificationsState {
  const NotificationsFailure(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
