import '../entities/app_user.dart';

abstract class AuthRepository {
  AppUser? get currentUser;
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
