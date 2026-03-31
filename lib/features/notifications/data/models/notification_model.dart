import '../../domain/entities/notification_entity.dart';

class NotificationModel extends NotificationEntity {
  const NotificationModel({
    required super.id,
    required super.userId,
    required super.type,
    required super.createdAt,
    super.actorId,
    super.actorName,
    super.actorAvatarUrl,
    super.title,
    super.body,
    super.productId,
    super.postId,
    super.storyId,
    super.subjectImageUrl,
    super.subjectVideoUrl,
    super.relatedPostKind,
    super.commentId,
    super.readAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? actorMap;
    final actorRaw = json['actor'];
    if (actorRaw is Map) {
      actorMap = Map<String, dynamic>.from(actorRaw);
    }

    final subject = _subjectMediaFromJson(json);
    String? postKind;
    final postRaw0 = json['post'];
    if (postRaw0 is Map) {
      postKind = Map<String, dynamic>.from(postRaw0)['kind'] as String?;
    }

    return NotificationModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      actorId: json['actor_id'] as String?,
      actorName: actorMap?['name'] as String?,
      actorAvatarUrl: actorMap?['avatar'] as String?,
      type: json['type'] as String,
      title: json['title'] as String?,
      body: json['body'] as String?,
      productId: json['product_id'] as String?,
      postId: json['post_id'] as String?,
      storyId: json['story_id'] as String?,
      subjectImageUrl: subject.$1,
      subjectVideoUrl: subject.$2,
      relatedPostKind: postKind,
      commentId: json['comment_id'] as String?,
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// (imageUrl, videoUrl) для превью: приоритет обложки поста, иначе товар.
  static (String?, String?) _subjectMediaFromJson(Map<String, dynamic> json) {
    final postRaw = json['post'];
    if (postRaw is Map) {
      final post = Map<String, dynamic>.from(postRaw);
      final img = (post['image_url'] as String?)?.trim();
      final vid = (post['video_url'] as String?)?.trim();
      if (img != null && img.isNotEmpty) return (img, null);
      if (vid != null && vid.isNotEmpty) return (null, vid);
    }
    final prodRaw = json['product'];
    if (prodRaw is Map) {
      final img = (Map<String, dynamic>.from(prodRaw)['image_url'] as String?)
          ?.trim();
      if (img != null && img.isNotEmpty) return (img, null);
    }
    return (null, null);
  }
}
