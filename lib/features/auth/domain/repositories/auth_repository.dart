import '../entities/app_user.dart';

abstract class AuthRepository {
  AppUser? get currentUser;

  /// Быстрый снимок пользователя из локальной сессии (JWT), без сети.
  AppUser? userFromCurrentSession();

  /// Полный профиль из БД; при ошибке или отсутствии строки — `null`.
  Future<AppUser?> fetchUserProfileFromRemote(String uid);

  /// Сессия + одна попытка загрузить профиль (для обратной совместимости).
  Future<AppUser?> getCurrentUserOnce();
  Future<void> signInWithEmail(String email, String password);
  Future<void> signUpWithEmail(String email, String password, String name);
  Future<void> signInWithGoogle();
  Future<void> signInWithApple();
  Future<void> signInWithSmsOtp(String phone);
  Future<void> verifySmsOtp(String phone, String token);
  Future<void> resetPasswordForEmail(String email);
  Future<void> signOut();
}
