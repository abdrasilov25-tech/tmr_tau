import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/config/oauth_env_config.dart';
import '../../../../core/storage/multi_account_storage.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._authRepository, this._multiAccountStorage) : super(AuthInitial()) {
    on<AuthCheckRequested>(_onCheckRequested);
    on<AuthSignInRequested>(_onSignInRequested);
    on<AuthSignInWithGoogleRequested>(_onSignInWithGoogleRequested);
    on<AuthSignInWithAppleRequested>(_onSignInWithAppleRequested);
    on<AuthSignInWithSmsOtpRequested>(_onSignInWithSmsOtpRequested);
    on<AuthVerifySmsOtpRequested>(_onVerifySmsOtpRequested);
    on<AuthSignUpRequested>(_onSignUpRequested);
    on<AuthSignOutRequested>(_onSignOutRequested);
    on<AuthSwitchToAccountRequested>(_onSwitchToAccountRequested);
    on<AuthResetPasswordRequested>(_onResetPasswordRequested);
  }

  final AuthRepository _authRepository;
  final MultiAccountStorage _multiAccountStorage;

  static int _oauthDismissNonce = 0;

  void _onCheckRequested(AuthCheckRequested event, Emitter<AuthState> emit) async {
    final stub = _authRepository.userFromCurrentSession();
    if (stub == null) {
      if (!isClosed) emit(AuthUnauthenticated());
      return;
    }
    try {
      await _multiAccountStorage.setLastActiveAccountId(stub.id);
    } catch (_) {}
    if (!isClosed) {
      emit(AuthAuthenticated(stub, fromSessionOnly: true));
    }
    try {
      final full = await _authRepository.fetchUserProfileFromRemote(stub.id);
      if (full != null && !isClosed) {
        final still = _authRepository.userFromCurrentSession();
        if (still?.id == stub.id) {
          emit(AuthAuthenticated(full, fromSessionOnly: false));
        }
      }
    } catch (_) {}
  }

  Future<void> _onSignInRequested(AuthSignInRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await _authRepository.signInWithEmail(event.email, event.password);
      final user = _authRepository.currentUser;
      if (user != null) {
        await _multiAccountStorage.setLastActiveAccountId(user.id);
        await _multiAccountStorage.addAccount(
          SavedAccount(
            id: user.id,
            email: user.email,
            name: user.name,
            avatarUrl: user.avatarUrl,
          ),
        );
      }
      if (!isClosed) emit(user != null ? AuthAuthenticated(user) : AuthUnauthenticated());
    } catch (e) {
      if (!isClosed) emit(AuthError(_authErrorMessage(e)));
    }
  }

  Future<void> _onSignInWithGoogleRequested(AuthSignInWithGoogleRequested event, Emitter<AuthState> emit) async {
    // Не используем AuthLoading: иначе на экране входа крутятся и «Войти», и кнопка Google.
    try {
      await _authRepository.signInWithGoogle();
      final user = _authRepository.currentUser;
      if (user != null) {
        await _multiAccountStorage.setLastActiveAccountId(user.id);
        await _multiAccountStorage.addAccount(
          SavedAccount(
            id: user.id,
            email: user.email,
            name: user.name,
            avatarUrl: user.avatarUrl,
          ),
        );
        if (!isClosed) emit(AuthAuthenticated(user));
        return;
      }
      if (!isClosed) {
        emit(
          const AuthError(
            'Не удалось войти через Google: сессия не получена. Добавьте в Supabase '
            '(Authentication → URL Configuration) тот же redirect, что в приложении '
            '(по умолчанию tmrtau://auth/callback), и проверьте ключи GOOGLE_WEB_CLIENT_ID / '
            'GOOGLE_IOS_CLIENT_ID в .env.',
          ),
        );
      }
    } catch (e) {
      if (_isOAuthCancelled(e)) {
        if (!isClosed) {
          emit(AuthOAuthDismissed(++_oauthDismissNonce));
          emit(_stateAfterOAuthCancel());
        }
        return;
      }
      if (!isClosed) emit(AuthError(_authErrorMessage(e)));
    }
  }

  Future<void> _onSignInWithAppleRequested(
    AuthSignInWithAppleRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await _authRepository.signInWithApple();
      final user = _authRepository.currentUser;
      if (user != null) {
        await _multiAccountStorage.setLastActiveAccountId(user.id);
        await _multiAccountStorage.addAccount(
          SavedAccount(
            id: user.id,
            email: user.email,
            name: user.name,
            avatarUrl: user.avatarUrl,
          ),
        );
        if (!isClosed) emit(AuthAuthenticated(user));
        return;
      }
      if (!isClosed) {
        emit(
          const AuthError(
            'Не удалось войти через Apple: сессия не получена. Убедитесь, что Bundle ID '
            'приложения совпадает с App ID в Apple Developer и что поставщик Apple в Supabase настроен.',
          ),
        );
      }
    } catch (e) {
      if (_isOAuthCancelled(e)) {
        if (!isClosed) {
          emit(AuthOAuthDismissed(++_oauthDismissNonce));
          emit(_stateAfterOAuthCancel());
        }
        return;
      }
      if (!isClosed) emit(AuthError(_authErrorMessage(e)));
    }
  }

  /// После отмены OAuth сессия часто остаётся прежней (например с экрана привязки аккаунта).
  AuthState _stateAfterOAuthCancel() {
    final user = _authRepository.userFromCurrentSession();
    if (user != null) {
      return AuthAuthenticated(user, fromSessionOnly: true);
    }
    return AuthUnauthenticated();
  }

  Future<void> _onSignInWithSmsOtpRequested(
    AuthSignInWithSmsOtpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await _authRepository.signInWithSmsOtp(event.phone);
      if (!isClosed) emit(AuthSmsOtpSent(phone: event.phone));
    } catch (e) {
      if (!isClosed) emit(AuthError(_authErrorMessage(e)));
    }
  }

  Future<void> _onVerifySmsOtpRequested(
    AuthVerifySmsOtpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await _authRepository.verifySmsOtp(event.phone, event.token);
      final user = _authRepository.currentUser;
      if (user != null) {
        await _multiAccountStorage.setLastActiveAccountId(user.id);
        await _multiAccountStorage.addAccount(
          SavedAccount(
            id: user.id,
            email: user.email,
            name: user.name,
            avatarUrl: user.avatarUrl,
          ),
        );
      }
      if (!isClosed) emit(user != null ? AuthAuthenticated(user) : AuthUnauthenticated());
    } catch (e) {
      if (!isClosed) emit(AuthError(_authErrorMessage(e)));
    }
  }

  Future<void> _onSignUpRequested(AuthSignUpRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await _authRepository.signUpWithEmail(event.email, event.password, event.name);
      final user = _authRepository.currentUser;
      if (user != null) {
        await _multiAccountStorage.setLastActiveAccountId(user.id);
        await _multiAccountStorage.addAccount(
          SavedAccount(
            id: user.id,
            email: user.email,
            name: user.name,
            avatarUrl: user.avatarUrl,
          ),
        );
      }
      if (!isClosed) emit(user != null ? AuthAuthenticated(user) : AuthUnauthenticated());
    } catch (e) {
      if (!isClosed) emit(AuthError(_authErrorMessage(e)));
    }
  }

  static String _authErrorMessage(Object e) {
    final raw = e.toString();
    final s = raw.toLowerCase();
    if (s.contains('redirect_uri_mismatch')) {
      final callback = OAuthEnvConfig.supabaseAuthV1CallbackUrl;
      final tail = callback != null
          ? 'Добавьте в Authorized redirect URIs: $callback'
          : 'Добавьте в Authorized redirect URIs URL вида '
              'https://<project-ref>.supabase.co/auth/v1/callback';
      return 'Google: неверный redirect_uri ($tail). Web Client ID в Google Cloud '
          'должен совпадать с Client ID в Supabase → Authentication → Google.';
    }
    if (s.contains('signup not allowed') ||
        s.contains('sign up not allowed') ||
        s.contains('signup_disabled') ||
        s.contains('registration not') ||
        raw.contains('регистрация')) {
      return 'Вход отклонён сервером: проверьте, что в Supabase включён провайдер '
          '(Google / Apple) и разрешена регистрация новых пользователей.';
    }
    if (s.contains('email not confirmed') || s.contains('confirm your email')) {
      return 'Подтвердите email: проверьте почту и перейдите по ссылке из письма.';
    }
    if (s.contains('invalid') && (s.contains('credential') || s.contains('password') || s.contains('login'))) {
      return 'Неверный email или пароль.';
    }
    if (s.contains('user not found') || s.contains('invalid login')) {
      return 'Нет аккаунта с таким email. Зарегистрируйтесь.';
    }
    return e.toString();
  }

  static bool _isOAuthCancelled(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('cancel') ||
        s.contains('canceled') ||
        s.contains('cancelled') ||
        s.contains('aborted') ||
        s.contains('access_denied');
  }

  Future<void> _onSignOutRequested(AuthSignOutRequested event, Emitter<AuthState> emit) async {
    // Если выходим явно, удаляем текущий аккаунт из быстрого входа
    // и сбрасываем lastActiveAccountId, чтобы он не появлялся в списке.
    final current = _authRepository.currentUser;
    if (current != null) {
      await _multiAccountStorage.removeAccount(current.id);
      await _multiAccountStorage.setLastActiveAccountId(null);
    }
    await _authRepository.signOut();
    if (!isClosed) emit(AuthUnauthenticated());
  }

  Future<void> _onSwitchToAccountRequested(AuthSwitchToAccountRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await _authRepository.signOut().timeout(const Duration(seconds: 8));
      await Future.delayed(const Duration(milliseconds: 150));
      await _authRepository
          .signInWithEmail(event.email, event.password)
          .timeout(const Duration(seconds: 12));
      final user = _authRepository.currentUser;
      if (user != null) {
        await _multiAccountStorage.setLastActiveAccountId(user.id);
        await _multiAccountStorage.addAccount(
          SavedAccount(
            id: user.id,
            email: user.email,
            name: user.name,
            avatarUrl: user.avatarUrl,
          ),
        );
      }
      if (!isClosed) emit(user != null ? AuthAuthenticated(user) : AuthUnauthenticated());
    } on TimeoutException {
      if (!isClosed) {
        emit(const AuthError('Переключение аккаунта заняло слишком много времени. Попробуйте снова.'));
      }
    } catch (e) {
      if (!isClosed) emit(AuthError(_authErrorMessage(e)));
    }
  }

  Future<void> _onResetPasswordRequested(
    AuthResetPasswordRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await _authRepository.resetPasswordForEmail(event.email);
      if (!isClosed) emit(const AuthPasswordResetSent());
    } catch (e) {
      if (!isClosed) emit(AuthError(_authErrorMessage(e)));
    }
  }
}
