import 'app_user.dart';

/// Результат регистрации по email и паролю (ответ Supabase Auth).
final class EmailSignUpResult {
  const EmailSignUpResult._({
    this.user,
    this.pendingEmailConfirmation = false,
  });

  /// Немедленный вход (есть сессия).
  final AppUser? user;

  /// Аккаунт создан, но вход только после подтверждения email (сессии нет).
  final bool pendingEmailConfirmation;

  factory EmailSignUpResult.signedIn(AppUser user) {
    return EmailSignUpResult._(user: user, pendingEmailConfirmation: false);
  }

  factory EmailSignUpResult.pendingEmailConfirmation() {
    return EmailSignUpResult._(pendingEmailConfirmation: true);
  }
}
