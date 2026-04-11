import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/app_user.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<void> signInWithEmail(String email, String password);
  Future<AuthResponse> signUpWithEmail(
    String email,
    String password,
    String name, {
    String? emailRedirectTo,
  });
  Future<void> signOut();
  Future<AppUser?> fetchUserProfile(String uid);
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  AuthRemoteDataSourceImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<void> signInWithEmail(String email, String password) async {
    await _client.auth.signInWithPassword(password: password, email: email);
  }

  @override
  Future<AuthResponse> signUpWithEmail(
    String email,
    String password,
    String name, {
    String? emailRedirectTo,
  }) async {
    Future<AuthResponse> call(String? redirect) {
      return _client.auth.signUp(
        password: password,
        email: email,
        emailRedirectTo: redirect,
        data: {'name': name},
      );
    }

    try {
      return await call(emailRedirectTo);
    } catch (e) {
      // Если `emailRedirectTo` не добавлен в Supabase → URL Configuration → Redirect URLs,
      // API отклоняет всю регистрацию. Повтор без redirect: письмо уйдёт с Site URL из Dashboard.
      final redirect = emailRedirectTo;
      if (redirect != null &&
          redirect.isNotEmpty &&
          _isLikelyRedirectAllowlistError(e)) {
        return await call(null);
      }
      rethrow;
    }
  }

  /// Ошибки валидации redirect_to / redirect_uri на стороне GoTrue.
  static bool _isLikelyRedirectAllowlistError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('redirect') &&
        (s.contains('not allowed') ||
            s.contains('invalid') ||
            s.contains('must'))) {
      return true;
    }
    if (s.contains('redirect_uri') || s.contains('redirect_to')) {
      return true;
    }
    if (s.contains('validation_failed') && s.contains('redirect')) {
      return true;
    }
    return false;
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  @override
  Future<AppUser?> fetchUserProfile(String uid) async {
    // Колонка `email` в public.users может отсутствовать (email живёт в auth.users).
    final res = await _client
        .from(SupabaseConstants.usersTable)
        .select(
          'id,name,username,avatar,bio,followers_count',
        )
        .eq('id', uid)
        .maybeSingle();
    if (res == null) return null;
    return UserModel.fromJson(Map<String, dynamic>.from(res as Map<dynamic, dynamic>));
  }
}
