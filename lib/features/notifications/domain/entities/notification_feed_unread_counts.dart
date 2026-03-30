/// Непрочитанные уведомления для нижней панели: публикации/товары vs новости (kind поста).
class NotificationFeedUnreadCounts {
  const NotificationFeedUnreadCounts({
    required this.publications,
    required this.news,
  });

  final int publications;
  final int news;
}
