import 'package:flutter/foundation.dart';

/// Событие выбора вкладки «Публикации» в shell — чтобы показать краткую сводку уведомлений в AppBar ленты.
final class NotificationActivityPeekBus {
  final ValueNotifier<int> publicationsTabPulse = ValueNotifier<int>(0);

  /// Увеличить после изменения прочитанности уведомлений — обновить бейджи в ленте и т.п.
  final ValueNotifier<int> unreadInvalidateTick = ValueNotifier<int>(0);

  void pulsePublicationsTab() {
    publicationsTabPulse.value++;
  }

  void notifyUnreadMayHaveChanged() {
    unreadInvalidateTick.value++;
  }

  void dispose() {
    publicationsTabPulse.dispose();
    unreadInvalidateTick.dispose();
  }
}
