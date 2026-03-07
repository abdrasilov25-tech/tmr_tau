import '../entities/notification_entity.dart';

abstract class NotificationsRepository {
  Future<List<NotificationEntity>> getNotifications(String userId,
      {int limit = 50, int offset = 0});
  Future<void> markAsRead(String notificationId, String userId);
  Future<void> markAllAsRead(String userId);
  Future<int> getUnreadCount(String userId);
}
