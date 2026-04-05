import 'dart:async';

/// Событие «список подписок изменился» из любого места (лента, профиль, пост).
/// Слушатели обновляют локальный UI без полного перезапуска приложения.
class FollowingChangeBus {
  FollowingChangeBus._();
  static final FollowingChangeBus instance = FollowingChangeBus._();

  final StreamController<void> _controller = StreamController<void>.broadcast();

  Stream<void> get stream => _controller.stream;

  void notify() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }
}
