part of 'auth_bloc.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

final class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}

/// Сохранить флаг гостя и открыть приложение без Supabase-сессии.
final class AuthContinueAsGuestRequested extends AuthEvent {
  const AuthContinueAsGuestRequested();
}

final class AuthSignInRequested extends AuthEvent {
  const AuthSignInRequested({required this.email, required this.password});
  final String email;
  final String password;
  @override
  List<Object?> get props => [email, password];
}

final class AuthSignInWithGoogleRequested extends AuthEvent {
  const AuthSignInWithGoogleRequested();
}

final class AuthSignInWithAppleRequested extends AuthEvent {
  const AuthSignInWithAppleRequested();
}

/// Догрузка профиля из БД после быстрого входа Apple (не блокирует кнопку).
final class AuthProfileHydrateAfterApple extends AuthEvent {
  const AuthProfileHydrateAfterApple({required this.uid});
  final String uid;
  @override
  List<Object?> get props => [uid];
}

final class AuthSignInWithSmsOtpRequested extends AuthEvent {
  const AuthSignInWithSmsOtpRequested({required this.phone});
  final String phone;
  @override
  List<Object?> get props => [phone];
}

final class AuthVerifySmsOtpRequested extends AuthEvent {
  const AuthVerifySmsOtpRequested({required this.phone, required this.token});
  final String phone;
  final String token;
  @override
  List<Object?> get props => [phone, token];
}

final class AuthSignUpRequested extends AuthEvent {
  const AuthSignUpRequested({
    required this.email,
    required this.password,
    required this.name,
    this.residentNumber,
  });
  final String email;
  final String password;
  final String name;
  /// Номер жителя города (опционально), сохраняется в `public.users.resident_number`.
  final String? residentNumber;
  @override
  List<Object?> get props => [email, password, name, residentNumber];
}

final class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}

final class AuthSwitchToAccountRequested extends AuthEvent {
  const AuthSwitchToAccountRequested({required this.email, required this.password});
  final String email;
  final String password;
  @override
  List<Object?> get props => [email, password];
}

final class AuthResetPasswordRequested extends AuthEvent {
  const AuthResetPasswordRequested({required this.email});
  final String email;
  @override
  List<Object?> get props => [email];
}
