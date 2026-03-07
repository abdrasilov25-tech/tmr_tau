import '../entities/app_user.dart';

abstract class AuthRepository {
  AppUser? get currentUser;
  Future<AppUser?> getCurrentUserOnce();
  Future<void> signInWithEmail(String email, String password);
  Future<void> signUpWithEmail(String email, String password, String name);
  Future<void> signOut();
}
