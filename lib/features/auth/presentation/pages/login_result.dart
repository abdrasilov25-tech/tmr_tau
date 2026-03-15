/// Результат входа при добавлении аккаунта (возврат с экрана логина в профиль).
class LoginResult {
  const LoginResult({
    required this.userId,
    required this.email,
    this.name,
    this.avatarUrl,
    this.password,
  });

  final String userId;
  final String email;
  final String? name;
  final String? avatarUrl;
  /// Пароль только для email-входа; для переключения аккаунта по одному нажатию.
  final String? password;
}
