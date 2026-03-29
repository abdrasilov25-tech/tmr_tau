import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../../../../core/config/oauth_env_config.dart';
import '../../../../core/constants/supabase_constants.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._dataSource, this._client);
  final AuthRemoteDataSource _dataSource;
  final SupabaseClient _client;

  AppUser? _cachedUser;

  @override
  AppUser? get currentUser => _cachedUser;

  @override
  AppUser? userFromCurrentSession() {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      _cachedUser = null;
      return null;
    }
    final u = _fallbackAppUser(authUser);
    _cachedUser = u;
    return u;
  }

  @override
  Future<AppUser?> fetchUserProfileFromRemote(String uid) async {
    try {
      final profile = await _dataSource.fetchUserProfile(uid);
      if (profile != null) {
        _cachedUser = profile;
        return profile;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AppUser?> getCurrentUserOnce() async {
    final stub = userFromCurrentSession();
    if (stub == null) return null;
    final full = await fetchUserProfileFromRemote(stub.id);
    _cachedUser = full ?? stub;
    return _cachedUser;
  }

  /// Пока строка в `users` недоступна или сеть тормозит — не блокируем вход: данные из JWT/session.
  AppUser _fallbackAppUser(User authUser) {
    final meta = authUser.userMetadata;
    String? username;
    String? avatarUrl;
    if (meta != null) {
      final u = meta['username'];
      if (u is String) username = u;
      final a = meta['avatar_url'];
      if (a is String) avatarUrl = a;
    }
    return AppUser(
      id: authUser.id,
      email: authUser.email ?? '',
      name: _getName(authUser),
      username: username,
      avatarUrl: avatarUrl,
      followersCount: 0,
    );
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
    final queryParams = <String, String>{
      'prompt': 'select_account',
    };
    final webClientId = OAuthEnvConfig.googleWebClientId;
    if (webClientId.isNotEmpty) {
      queryParams['client_id'] = webClientId;
    }
    final launched = await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: OAuthEnvConfig.redirectTo,
      queryParams: queryParams,
    );
    if (!launched) return;
    final authUser = await _waitForOAuthUser();
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
    final launched = await _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: OAuthEnvConfig.redirectTo,
    );
    if (!launched) return;
    final authUser = await _waitForOAuthUser();
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
  Future<void> signInWithSmsOtp(String phone) async {
    await _client.auth.signInWithOtp(
      phone: phone,
      // По умолчанию это sms, но явно задаём чтобы не было сюрпризов.
      channel: OtpChannel.sms,
    );
  }

  @override
  Future<void> verifySmsOtp(String phone, String token) async {
    await _client.auth.verifyOTP(
      type: OtpType.sms,
      token: token,
      phone: phone,
    );

    final authUser = _client.auth.currentUser;
    final uid = authUser?.id;
    if (uid == null) return;

    _cachedUser = await _dataSource.fetchUserProfile(uid);
    if (_cachedUser == null) {
      try {
        await _ensureUserRow(uid, phone, _getName(authUser) ?? phone);
        _cachedUser = await _dataSource.fetchUserProfile(uid);
      } catch (_) {
        // Профиль в БД не создался — пускаем в приложение с данными из сессии
      }
      _cachedUser ??= AppUser(
        id: uid,
        email: authUser?.email ?? '',
        name: _getName(authUser) ?? phone,
        followersCount: 0,
      );
    }
  }

  @override
  Future<void> resetPasswordForEmail(String email) async {
    await _client.auth.resetPasswordForEmail(
      email,
      redirectTo: OAuthEnvConfig.redirectTo,
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

  Future<User?> _waitForOAuthUser({Duration timeout = const Duration(seconds: 20)}) async {
    final existing = _client.auth.currentUser;
    if (existing != null) return existing;

    final completer = Completer<User?>();
    late final StreamSubscription<AuthState> sub;
    sub = _client.auth.onAuthStateChange.listen((event) {
      final user = event.session?.user ?? _client.auth.currentUser;
      if (user != null && !completer.isCompleted) {
        completer.complete(user);
      }
    });
    try {
      return await completer.future.timeout(timeout, onTimeout: () => _client.auth.currentUser);
    } finally {
      await sub.cancel();
    }
  }
}
