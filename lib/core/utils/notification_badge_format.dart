/// Отображение счётчика как в Instagram: после 99 показываем «99+».
String formatNotificationBadgeCount(int count) {
  if (count < 0) return '0';
  if (count > 99) return '99+';
  return '$count';
}
