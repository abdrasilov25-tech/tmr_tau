import 'package:flutter_test/flutter_test.dart';
import 'package:tmr_tau/core/utils/notification_badge_format.dart';

void main() {
  group('formatNotificationBadgeCount', () {
    test('отрицательное и ноль', () {
      expect(formatNotificationBadgeCount(-3), '0');
      expect(formatNotificationBadgeCount(0), '0');
    });

    test('обычные значения', () {
      expect(formatNotificationBadgeCount(1), '1');
      expect(formatNotificationBadgeCount(99), '99');
    });

    test('больше 99 -> 99+', () {
      expect(formatNotificationBadgeCount(100), '99+');
      expect(formatNotificationBadgeCount(1000), '99+');
    });
  });
}
