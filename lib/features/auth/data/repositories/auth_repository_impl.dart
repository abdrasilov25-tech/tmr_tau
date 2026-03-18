import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../../../../core/constants/supabase_constants.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._dataSource, this._client);
  final AuthRemoteDataSource _dataSource;
  final SupabaseClient _client;

  AppUser? _cachedUser;

  @override
  AppUser? get currentUser => _cachedUser;

  @override
  Future<AppUser?> getCurrentUserOnce() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        _cachedUser = null;
        return null;
      }
      _cachedUser = await _dataSource.fetchUserProfile(uid);
      return _cachedUser;
    } catch (_) {
      _cachedUser = null;
      return null;
    }
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    await _dataSource.signInWithEmail(email, password);
    final authUser = _client.auth.currentUser;
    final uid = authUser?.id;
    if (uid == null) return;
    _cachedUser = await _dataSource.fetchUserProfile(uid);
    if (_cachedUser == null) {
      try {
        await _ensureUserRow(uid, email, _getName(authUser) ?? email);
        _cachedUser = await _dataSource.fetchUserProfile(uid);
      } catch (_) {
        // Профиль в БД не создался — пускаем в приложение с данными из сессии
      }
      _cachedUser ??= AppUser(
        id: uid,
        email: authUser?.email ?? email,
        name: _getName(authUser),
        followersCount: 0,
      );
    }
  }

  @override
  Future<void> signUpWithEmail(String email, String password, String name) async {
    await _dataSource.signUpWithEmail(email, password, name);
    final uid = _client.auth.currentUser?.id;
    if (uid != null) {
      await _ensureUserRow(uid, email, name);
      _cachedUser = await _dataSource.fetchUserProfile(uid);
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'tmrtau://auth/callback', // Замените на ваш app scheme
    );
    final authUser = _client.auth.currentUser;
    final uid = authUser?.id;
    if (uid == null) return;
    _cachedUser = await _dataSource.fetchUserProfile(uid);
    if (_cachedUser == null) {
      try {
        await _ensureUserRow(uid, authUser?.email ?? '', _getName(authUser) ?? '');
        _cachedUser = await _dataSource.fetchUserProfile(uid);
      } catch (_) {
        // Профиль в БД не создался — пускаем в приложение с данными из сессии
      }
      _cachedUser ??= AppUser(
        id: uid,
        email: authUser?.email ?? '',
        name: _getName(authUser),
        followersCount: 0,
      );
    }
  }

  @override
  Future<void> signInWithApple() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: 'tmrtau://auth/callback',
    );
    final authUser = _client.auth.currentUser;
    final uid = authUser?.id;
    if (uid == null) return;
    _cachedUser = await _dataSource.fetchUserProfile(uid);
    if (_cachedUser == null) {
      try {
        await _ensureUserRow(uid, authUser?.email ?? '', _getName(authUser) ?? '');
        _cachedUser = await _dataSource.fetchUserProfile(uid);
      } catch (_) {
        // Профиль в БД не создался — пускаем в приложение с данными из сессии
      }
      _cachedUser ??= AppUser(
        id: uid,
        email: authUser?.email ?? '',
        name: _getName(authUser),
        followersCount: 0,
      );
    }
  }

  @override
  Future<void> resetPasswordForEmail(String email) async {
    await _client.auth.resetPasswordForEmail(
      email,
      redirectTo: 'tmrtau://auth/callback',
    );
  }

  String? _getName(User? user) {
    if (user == null) return null;
    final meta = user.userMetadata;
    if (meta == null) return null;
    final name = meta['name'];
    return name is String ? name : null;
  }

  Future<void> _ensureUserRow(String uid, String email, String name) async {
    await _client.from(SupabaseConstants.usersTable).upsert({
      'id': uid,
      'name': name.isNotEmpty ? name : email,
      'followers_count': 0,
    });
  }

  @override
  Future<void> signOut() async {
    _cachedUser = null;
    await _dataSource.signOut();
  }
}
