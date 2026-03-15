import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._authRepository) : super(AuthInitial()) {
    on<AuthCheckRequested>(_onCheckRequested);
    on<AuthSignInRequested>(_onSignInRequested);
    on<AuthSignInWithGoogleRequested>(_onSignInWithGoogleRequested);
    on<AuthSignUpRequested>(_onSignUpRequested);
    on<AuthSignOutRequested>(_onSignOutRequested);
    on<AuthSwitchToAccountRequested>(_onSwitchToAccountRequested);
  }

  final AuthRepository _authRepository;

  void _onCheckRequested(AuthCheckRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await _authRepository.getCurrentUserOnce();
      if (!isClosed) emit(user != null ? AuthAuthenticated(user) : AuthUnauthenticated());
    } catch (_) {
      if (!isClosed) emit(AuthUnauthenticated());
    }
  }

  Future<void> _onSignInRequested(AuthSignInRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await _authRepository.signInWithEmail(event.email, event.password);
      final user = _authRepository.currentUser;
      if (!isClosed) emit(user != null ? AuthAuthenticated(user) : AuthUnauthenticated());
    } catch (e) {
      if (!isClosed) emit(AuthError(_authErrorMessage(e)));
    }
  }

  Future<void> _onSignInWithGoogleRequested(AuthSignInWithGoogleRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await _authRepository.signInWithGoogle();
      final user = _authRepository.currentUser;
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
      if (!isClosed) emit(user != null ? AuthAuthenticated(user) : AuthUnauthenticated());
    } catch (e) {
      if (!isClosed) emit(AuthError(_authErrorMessage(e)));
    }
  }

  static String _authErrorMessage(Object e) {
    final s = e.toString().toLowerCase();
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

  Future<void> _onSignOutRequested(AuthSignOutRequested event, Emitter<AuthState> emit) async {
    await _authRepository.signOut();
    if (!isClosed) emit(AuthUnauthenticated());
  }

  Future<void> _onSwitchToAccountRequested(AuthSwitchToAccountRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await _authRepository.signOut();
      await Future.delayed(const Duration(milliseconds: 300));
      await _authRepository.signInWithEmail(event.email, event.password);
      final user = _authRepository.currentUser;
      if (!isClosed) emit(user != null ? AuthAuthenticated(user) : AuthUnauthenticated());
    } catch (e) {
      if (!isClosed) emit(AuthError(_authErrorMessage(e)));
    }
  }
}
