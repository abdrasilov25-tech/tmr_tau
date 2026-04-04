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
    return _client.auth.signUp(
      password: password,
      email: email,
      emailRedirectTo: emailRedirectTo,
      data: {'name': name},
    );
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  @override
  Future<AppUser?> fetchUserProfile(String uid) async {
    final res = await _client
        .from(SupabaseConstants.usersTable)
        .select(
          'id,email,name,username,avatar,bio,followers_count',
        )
        .eq('id', uid)
        .maybeSingle();
    if (res == null) return null;
    return UserModel.fromJson(Map<String, dynamic>.from(res as Map<dynamic, dynamic>));
  }
}
