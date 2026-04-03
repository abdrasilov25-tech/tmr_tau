import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../../../../core/auth/oauth_foreground_signal.dart';
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
    // На iOS лишний/несовпадающий client_id в query ломает OAuth; для мобильных
    // достаточно настроек провайдера в Supabase Dashboard.
    final attachWebClientId =
        kIsWeb ||
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
    if (attachWebClientId && webClientId.isNotEmpty) {
      queryParams['client_id'] = webClientId;
    }
    final launched = await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: OAuthEnvConfig.redirectTo,
      queryParams: queryParams,
      // iOS: иначе часто открывается SFSafariViewController — приложение остаётся
      // в [resumed], не приходит paused → не срабатывает быстрый сброс при отмене.
      authScreenLaunchMode: (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.macOS))
          ? LaunchMode.externalApplication
          : LaunchMode.platformDefault,
    );
    if (!launched) {
      throw const AuthException('Не удалось открыть окно входа Google.');
    }
    final authUser = await _waitForOAuthUser();
    final uid = authUser.id;
    _cachedUser = await _dataSource.fetchUserProfile(uid);
    if (_cachedUser == null) {
      try {
        await _ensureUserRow(uid, authUser.email ?? '', _getName(authUser) ?? '');
        _cachedUser = await _dataSource.fetchUserProfile(uid);
      } catch (_) {
        // Профиль в БД не создался — пускаем в приложение с данными из сессии
      }
      _cachedUser ??= AppUser(
        id: uid,
        email: authUser.email ?? '',
        name: _getName(authUser),
        followersCount: 0,
      );
    }
  }

  @override
  Future<void> signInWithApple() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      await _signInWithAppleNative();
      return;
    }

    final launched = await _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: OAuthEnvConfig.redirectTo,
      authScreenLaunchMode: (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.macOS))
          ? LaunchMode.externalApplication
          : LaunchMode.platformDefault,
    );
    if (!launched) {
      throw const AuthException('Не удалось открыть окно входа Apple.');
    }
    final authUser = await _waitForOAuthUser();
    final uid = authUser.id;
    _cachedUser = await _dataSource.fetchUserProfile(uid);
    if (_cachedUser == null) {
      try {
        await _ensureUserRow(uid, authUser.email ?? '', _getName(authUser) ?? '');
        _cachedUser = await _dataSource.fetchUserProfile(uid);
      } catch (_) {
        // Профиль в БД не создался — пускаем в приложение с данными из сессии
      }
      _cachedUser ??= AppUser(
        id: uid,
        email: authUser.email ?? '',
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

  /// Ожидание сессии после [signInWithOAuth]. При возврате в приложение без сессии
  /// (закрыли Safari) — быстро завершаем, не дожидаясь [timeout].
  Future<User> _waitForOAuthUser({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final existing = _client.auth.currentUser;
    if (existing != null) return existing;

    final completer = Completer<User>();
    var resumeEpoch = 0;

    Future<void> afterForegroundReturn(int epoch) async {
      // Сразу проверяем сессию, затем короткий опрос (успешный deep link обычно < 1–2 с).
      for (var i = 0; i < 20; i++) {
        if (completer.isCompleted || epoch != resumeEpoch) return;
        if (i > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        final u = _client.auth.currentUser ?? _client.auth.currentSession?.user;
        if (u != null) {
          if (!completer.isCompleted) completer.complete(u);
          return;
        }
      }
      if (!completer.isCompleted && epoch == resumeEpoch) {
        completer.completeError(
          const AuthException('Sign-in canceled'),
        );
      }
    }

    late final StreamSubscription<AuthState> authSub;
    authSub = _client.auth.onAuthStateChange.listen((event) {
      final user = event.session?.user ?? _client.auth.currentUser;
      if (user != null && !completer.isCompleted) {
        completer.complete(user);
      }
    });

    late final StreamSubscription<void> resumeSub;
    resumeSub = OAuthForegroundSignal.instance.stream.listen((_) {
      resumeEpoch++;
      final epoch = resumeEpoch;
      unawaited(afterForegroundReturn(epoch));
    });

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw AuthException(_oauthWaitTimeoutMessage(timeout)),
      );
    } finally {
      await authSub.cancel();
      await resumeSub.cancel();
    }
  }

  String _oauthWaitTimeoutMessage(Duration timeout) {
    final googleHint = OAuthEnvConfig.supabaseAuthV1CallbackUrl;
    final buf = StringBuffer(
      'Вход не завершён за ${timeout.inSeconds} с. '
      'В Supabase добавьте ${OAuthEnvConfig.redirectTo} и проверьте схему tmrtau в iOS. ',
    );
    if (googleHint != null) {
      buf.write('Для Google redirect_uri (Web client): $googleHint');
    }
    return buf.toString();
  }

  String _generateRawNonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<void> _signInWithAppleNative() async {
    if (!await SignInWithApple.isAvailable()) {
      throw const AuthException('Sign in with Apple недоступен на этом устройстве.');
    }

    final rawNonce = _generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    // Таймаут: если iOS не вернёт результат (редко, но бывает на симуляторе),
    // иначе Future не завершится и кнопка Apple останется в loading.
    const appleCredentialTimeout = Duration(minutes: 3);

    late final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      ).timeout(
        appleCredentialTimeout,
        onTimeout: () => throw const AuthException('Sign-in canceled'),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AuthException('Sign-in canceled');
      }
      rethrow;
    }

    final idToken = credential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw const AuthException(
        'Apple не вернул токен. Проверьте capability Sign in with Apple в Xcode.',
      );
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      accessToken: credential.authorizationCode,
      nonce: rawNonce,
    );

    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      throw const AuthException('Сессия Apple не создана.');
    }
    final uid = authUser.id;

    final gn = credential.givenName ?? '';
    final fn = credential.familyName ?? '';
    final combinedName = [gn, fn].where((s) => s.isNotEmpty).join(' ').trim();
    final displayName = combinedName.isNotEmpty
        ? combinedName
        : _getName(authUser);

    // Сразу отдаём управление UI: не ждём updateUser и Supabase `users`.
    _cachedUser = AppUser(
      id: uid,
      email: authUser.email ?? '',
      name: displayName,
      followersCount: 0,
    );

    if (combinedName.isNotEmpty && (authUser.userMetadata?['name'] == null)) {
      unawaited(() async {
        try {
          await _client.auth.updateUser(
            UserAttributes(
              data: {'name': combinedName, 'full_name': combinedName},
            ),
          );
        } catch (_) {}
      }());
    }

    unawaited(_hydrateAppleUserInBackground(uid, authUser, combinedName));
  }

  /// Догружает строку в `users` и полный профиль без блокировки экрана входа.
  Future<void> _hydrateAppleUserInBackground(
    String uid,
    User authUser,
    String combinedName,
  ) async {
    try {
      var profile = await _dataSource.fetchUserProfile(uid);
      if (profile != null) {
        if (_client.auth.currentUser?.id == uid) {
          _cachedUser = profile;
        }
        return;
      }
      await _ensureUserRow(
        uid,
        authUser.email ?? '',
        combinedName.isNotEmpty ? combinedName : (_getName(authUser) ?? ''),
      );
      profile = await _dataSource.fetchUserProfile(uid);
      if (profile != null && _client.auth.currentUser?.id == uid) {
        _cachedUser = profile;
      }
    } catch (_) {
      // Остаётся сессионный stub из [_signInWithAppleNative].
    }
  }
}
