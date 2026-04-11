import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/email_sign_up_result.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../../../../core/auth/oauth_foreground_signal.dart';
import '../../../../core/config/oauth_env_config.dart';
import '../../../../core/constants/supabase_constants.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(
    this._dataSource,
    this._client, {
    Future<void> Function()? beforeRemoteSignOut,
  }) : _beforeRemoteSignOut = beforeRemoteSignOut;

  final AuthRemoteDataSource _dataSource;
  final SupabaseClient _client;
  final Future<void> Function()? _beforeRemoteSignOut;

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
      final merged = await _fetchUserProfileMerged(uid);
      if (merged != null) {
        _cachedUser = merged;
        return merged;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Профиль из `public.users` + email из JWT (в таблице часто нет колонки `email`).
  Future<AppUser?> _fetchUserProfileMerged(String uid) async {
    final raw = await _dataSource.fetchUserProfile(uid);
    if (raw == null) return null;
    return _mergeSessionEmail(raw);
  }

  AppUser _mergeSessionEmail(AppUser profile) {
    if (profile.email.isNotEmpty) return profile;
    final authEmail = _client.auth.currentUser?.email ?? '';
    if (authEmail.isEmpty) return profile;
    return AppUser(
      id: profile.id,
      email: authEmail,
      name: profile.name,
      username: profile.username,
      avatarUrl: profile.avatarUrl,
      bio: profile.bio,
      residentNumber: profile.residentNumber,
      followersCount: profile.followersCount,
      followingCount: profile.followingCount,
    );
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
    String? residentNumber;
    if (meta != null) {
      final u = meta['username'];
      if (u is String) username = u;
      final a = meta['avatar_url'];
      if (a is String) avatarUrl = a;
      final rn = meta['resident_number'];
      if (rn is String) residentNumber = rn;
    }
    return AppUser(
      id: authUser.id,
      email: authUser.email ?? '',
      name: _getName(authUser),
      username: username,
      avatarUrl: avatarUrl,
      residentNumber: residentNumber,
      followersCount: 0,
    );
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    await _dataSource.signInWithEmail(email, password);
    final authUser = _client.auth.currentUser;
    final uid = authUser?.id;
    if (uid == null) return;
    _cachedUser = await _fetchUserProfileMerged(uid);
    if (_cachedUser == null) {
      try {
        await _ensureUserRow(uid, email, _getName(authUser) ?? email);
        _cachedUser = await _fetchUserProfileMerged(uid);
      } catch (e) {
        // Профиль в БД не создался — пускаем в приложение с данными из сессии
      }
      _cachedUser ??= AppUser(
        id: uid,
        email: authUser?.email ?? email,
        name: _getName(authUser),
        residentNumber: null,
        followersCount: 0,
      );
    }
  }

  @override
  Future<EmailSignUpResult> signUpWithEmail(
    String email,
    String password,
    String name, {
    String? residentNumber,
  }) async {
    // Старая сессия в клиенте даёт неверный currentUser после signUp без сессии
    // и повторная отправка формы приводит к user_already_exists.
    if (_client.auth.currentSession != null) {
      await _dataSource.signOut();
    }

    final response = await _dataSource.signUpWithEmail(
      email,
      password,
      name,
      emailRedirectTo: OAuthEnvConfig.redirectTo,
      residentNumber: residentNumber,
    );

    if (response.session != null && response.user != null) {
      final uid = response.user!.id;
      try {
        await _ensureUserRow(uid, email, name, residentNumber: residentNumber);
      } catch (_) {
        // RLS/сеть: не блокируем вход — профиль подтянется позже или из метаданных.
      }
      _cachedUser = await _fetchUserProfileMerged(uid);
      _cachedUser ??= AppUser(
        id: uid,
        email: response.user!.email ?? email,
        name: name.isNotEmpty ? name : (response.user!.email ?? email),
        residentNumber: residentNumber?.trim().isNotEmpty == true
            ? residentNumber!.trim()
            : null,
        followersCount: 0,
      );
      return EmailSignUpResult.signedIn(_cachedUser!);
    }

    // Подтверждение email в Supabase: пользователь создан, JWT ещё не выдан.
    _cachedUser = null;
    return EmailSignUpResult.pendingEmailConfirmation();
  }

  @override
  Future<void> signInWithGoogle() async {
    final queryParams = <String, String>{
      'prompt': 'select_account',
    };
    final webClientId = OAuthEnvConfig.googleWebClientId;
    // Web Client ID в query (в т.ч. iOS): иначе Google может выдать id_token с aud = iOS client,
    // а Supabase проверяет по Web Client ID → AuthApiException «Unacceptable audience».
    final attachWebClientId = kIsWeb ||
        (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS));
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
    await _hydrateCachedUserAfterOAuth(authUser);
  }

  /// После OAuth (Google / Apple web): профиль в `users` + fallback из JWT.
  Future<void> _hydrateCachedUserAfterOAuth(User authUser) async {
    final uid = authUser.id;
    _cachedUser = await _fetchUserProfileMerged(uid);
    if (_cachedUser == null) {
      try {
        await _ensureUserRow(uid, authUser.email ?? '', _getName(authUser) ?? '');
        _cachedUser = await _fetchUserProfileMerged(uid);
      } catch (e) {
        // Профиль в БД не создался — пускаем в приложение с данными из сессии
      }
      _cachedUser ??= AppUser(
        id: uid,
        email: authUser.email ?? '',
        name: _getName(authUser),
        residentNumber: null,
        followersCount: 0,
      );
    }
  }

  @override
  Future<void> signInWithApple() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      try {
        await _signInWithAppleNative();
        return;
      } catch (e, st) {
        debugPrint('Apple native sign-in failed: $e\n$st');
        // Нативный id_token: aud = Bundle ID (напр. com.tmrtau.app). В Supabase в Apple
        // иногда указан только Services ID — сервер отклоняет токен. OAuth в Safari
        // выдаёт токен под веб/Services ID из Dashboard.
        if (_isAppleNativeTokenRejectedBySupabase(e)) {
          await _signInWithAppleOAuth();
          return;
        }
        rethrow;
      }
    }

    await _signInWithAppleOAuth();
  }

  bool _isAppleNativeTokenRejectedBySupabase(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('cancel')) return false;
    return s.contains('unacceptable audience') ||
        (s.contains('audience') && s.contains('id_token')) ||
        s.contains('authapiexception') && s.contains('audience') ||
        s.contains('invalid issuer') ||
        (s.contains('issuer') && s.contains('apple'));
  }

  Future<void> _signInWithAppleOAuth() async {
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
    await _hydrateCachedUserAfterOAuth(authUser);
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

    _cachedUser = await _fetchUserProfileMerged(uid);
    if (_cachedUser == null) {
      try {
        await _ensureUserRow(uid, phone, _getName(authUser) ?? phone);
        _cachedUser = await _fetchUserProfileMerged(uid);
      } catch (e) {
        // Профиль в БД не создался — пускаем в приложение с данными из сессии
      }
      _cachedUser ??= AppUser(
        id: uid,
        email: authUser?.email ?? '',
        name: _getName(authUser) ?? phone,
        residentNumber: null,
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

  Future<void> _ensureUserRow(
    String uid,
    String email,
    String name, {
    String? residentNumber,
  }) async {
    final row = <String, dynamic>{
      'id': uid,
      'name': name.isNotEmpty ? name : email,
      'followers_count': 0,
    };
    final rn = residentNumber?.trim();
    if (rn != null && rn.isNotEmpty) {
      row['resident_number'] = rn;
    }
    await _client.from(SupabaseConstants.usersTable).upsert(row);
  }

  @override
  Future<void> signOut() async {
    try {
      await _beforeRemoteSignOut?.call();
    } catch (_) {}
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

    try {
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw const AuthException(
          'Apple Sign In: нет ответа от сервера. '
          'Убедитесь что в Supabase Dashboard → Authentication → Providers → Apple '
          'настроены Team ID, Key ID и Private Key.',
        ),
      );
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(
        'Apple Sign In: ошибка авторизации — ${e.toString()}. '
        'Проверьте настройки Apple Provider в Supabase Dashboard.',
      );
    }

    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      throw const AuthException(
        'Apple Sign In: сессия не создана. '
        'Проверьте настройки Apple Provider в Supabase Dashboard.',
      );
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
      residentNumber: null,
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
        } catch (e) { debugPrint('$e'); }
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
      var profile = await _fetchUserProfileMerged(uid);
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
      profile = await _fetchUserProfileMerged(uid);
      if (profile != null && _client.auth.currentUser?.id == uid) {
        _cachedUser = profile;
      }
    } catch (e) {
      // Остаётся сессионный stub из [_signInWithAppleNative].
    }
  }
}
