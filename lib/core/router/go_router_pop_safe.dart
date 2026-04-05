import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

extension GoRouterPopSafeX on BuildContext {
  /// [pop] только если в стеке GoRouter есть куда вернуться; иначе [go] на [fallbackLocation].
  ///
  /// Иначе голый [pop] при открытии экрана через [go] даёт
  /// `GoError: There is nothing to pop`.
  void popOrGo(String fallbackLocation, [Object? result]) {
    if (!mounted) return;
    if (canPop()) {
      pop(result);
    } else {
      go(fallbackLocation);
    }
  }

  /// Безопасный выход на ленту (типичный fallback для модалок и сторис).
  void popOrGoHomeFeed([Object? result]) {
    popOrGo('/home/feed', result);
  }

  /// Вкладка «Чаты» в shell (DM / группы / канал открыты как top-level routes).
  void popOrGoHomeChats([Object? result]) {
    popOrGo('/home/chats', result);
  }
}
