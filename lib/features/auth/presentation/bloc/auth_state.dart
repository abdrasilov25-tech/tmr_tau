part of 'auth_bloc.dart';

sealed class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

final class AuthInitial extends AuthState {}

final class AuthLoading extends AuthState {}

final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user, {this.fromSessionOnly = false});
  final AppUser user;

  /// `true` — только данные из сессии; позже может прийти обновление с сервера.
  final bool fromSessionOnly;

  @override
  List<Object?> get props => [user, fromSessionOnly];
}

final class AuthUnauthenticated extends AuthState {}

final class AuthPasswordResetSent extends AuthState {
  const AuthPasswordResetSent();
}

final class AuthSmsOtpSent extends AuthState {
  const AuthSmsOtpSent({required this.phone});
  final String phone;

  @override
  List<Object?> get props => [phone];
}

final class AuthError extends AuthState {
  const AuthError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
