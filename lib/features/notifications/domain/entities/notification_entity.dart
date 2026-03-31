import 'package:equatable/equatable.dart';

class NotificationEntity extends Equatable {
  const NotificationEntity({
    required this.id,
    required this.userId,
    required this.type,
    required this.createdAt,
    this.actorId,
    this.actorName,
    this.actorAvatarUrl,
    this.title,
    this.body,
    this.productId,
    this.postId,
    this.storyId,
    this.subjectImageUrl,
    this.subjectVideoUrl,
    this.relatedPostKind,
    this.commentId,
    this.readAt,
  });

  final String id;
  final String userId;
  final String? actorId;
  /// Подтягиваются join-ом с `users` по `actor_id` (если политика/схема позволяют).
  final String? actorName;
  final String? actorAvatarUrl;
  final String type;
  final String? title;
  final String? body;
  final String? productId;
  /// Пост (публикация / новость), к которому относится событие.
  final String? postId;
  /// Сторис, к которой относится событие.
  final String? storyId;
  /// Превью медиа поста или фото товара ( из join ).
  final String? subjectImageUrl;
  final String? subjectVideoUrl;
  /// `news` | `publication` из связанного поста (если есть).
  final String? relatedPostKind;
  final String? commentId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  @override
  List<Object?> get props => [
        id,
        userId,
        actorId,
        actorName,
        actorAvatarUrl,
        type,
        title,
        body,
        productId,
        postId,
        storyId,
        subjectImageUrl,
        subjectVideoUrl,
        relatedPostKind,
        commentId,
        readAt,
        createdAt,
      ];
}
