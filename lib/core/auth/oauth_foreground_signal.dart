import 'dart:async';

/// Событие: приложение снова на переднем плане после [AppLifecycleState.paused]
/// (закрыли Safari / ASWebAuthenticationSession после OAuth).
/// Используется в [AuthRepositoryImpl], чтобы не ждать полный timeout при отмене входа.
class OAuthForegroundSignal {
  OAuthForegroundSignal._();
  static final OAuthForegroundSignal instance = OAuthForegroundSignal._();

  final StreamController<void> _controller = StreamController<void>.broadcast();

  Stream<void> get stream => _controller.stream;

  void notifyForegroundAfterBackground() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }
}
