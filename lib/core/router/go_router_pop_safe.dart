import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

extension GoRouterPopSafeX on BuildContext {
  /// Безопасный выход: [pop] только если есть куда; иначе [go] на главную ленту.
  ///
  /// Иначе [pop] при открытии через [go] (без записи в стеке) даёт
  /// `GoError: There is nothing to pop`.
  void popOrGoHomeFeed([Object? result]) {
    if (!mounted) return;
    if (canPop()) {
      pop(result);
    } else {
      go('/home/feed');
    }
  }
}
