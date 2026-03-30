/// Коды исключений из триггера модерации городского чата (см. миграцию Supabase).
abstract final class CityChatModerationCodes {
  CityChatModerationCodes._();

  static const warning = 'CITY_CHAT_WARNING';
  static const ban3Days = 'CITY_CHAT_BAN_3D';
  static const ban7Days = 'CITY_CHAT_BAN_7D';
  static const banPermanent = 'CITY_CHAT_BAN_PERM';
  static const blocked = 'CITY_CHAT_BLOCKED';

  static bool isModerationCode(String raw) {
    final u = raw.toUpperCase();
    return u.contains(warning) ||
        u.contains(ban3Days) ||
        u.contains(ban7Days) ||
        u.contains(banPermanent) ||
        u.contains(blocked);
  }

  static String userMessageFor(String raw) {
    final u = raw.toUpperCase();
    if (u.contains(warning)) {
      return 'Сообщение не отправлено: обнаружены недопустимые выражения или темы. '
          'Это предупреждение. Пожалуйста, общайтесь уважительно.';
    }
    if (u.contains(ban3Days)) {
      return 'Повторное нарушение. Вам запрещено писать в городском чате на 3 суток.';
    }
    if (u.contains(ban7Days)) {
      return 'Очередное нарушение. Ограничение на 7 суток.';
    }
    if (u.contains(banPermanent)) {
      return 'Постоянная блокировка отправки сообщений в городском чате.';
    }
    if (u.contains(blocked)) {
      return 'Вам ограничена отправка сообщений в городском чате. '
          'Дождитесь окончания срока или обратитесь в поддержку.';
    }
    return '';
  }
}
