import 'package:equatable/equatable.dart';

/// Сводка непрочитанных in-app уведомлений для компактного UI (счётчики + превью).
class NotificationUnreadSummary extends Equatable {
  const NotificationUnreadSummary({
    required this.unreadLikes,
    required this.unreadComments,
    required this.unreadReposts,
    required this.totalUnread,
    required this.previewAvatarUrls,
  });

  final int unreadLikes;
  final int unreadComments;
  final int unreadReposts;
  /// Все непрочитанные (включая типы кроме лайк/коммент/репост).
  final int totalUnread;
  /// До нескольких уникальных URL аватаров авторов последних событий (новые первыми).
  final List<String> previewAvatarUrls;

  @override
  List<Object?> get props => [
        unreadLikes,
        unreadComments,
        unreadReposts,
        totalUnread,
        previewAvatarUrls,
      ];
}
