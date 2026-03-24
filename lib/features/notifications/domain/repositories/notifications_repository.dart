import '../entities/notification_entity.dart';
import '../entities/notification_unread_summary.dart';

abstract class NotificationsRepository {
  Future<List<NotificationEntity>> getNotifications(String userId,
      {int limit = 50, int offset = 0});
  Future<void> markAsRead(String notificationId, String userId);
  Future<void> markAsReadMany(List<String> notificationIds, String userId);
  Future<void> markAllAsRead(String userId);
  Future<int> getUnreadCount(String userId);
  /// Непрочитанные: счётчики по типам и превью аватаров (все непрочитанные из выборки).
  Future<NotificationUnreadSummary> getUnreadSummary(String userId);
}
