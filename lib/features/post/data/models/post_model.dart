import '../../domain/entities/post_entity.dart';

class PostModel extends PostEntity {
  const PostModel({
    required super.id,
    required super.userId,
    super.imageUrl = '',
    super.caption = '',
    super.videoUrl,
    super.videoDurationSeconds = 0,
    required super.createdAt,
    super.likesCount = 0,
    super.dislikesCount = 0,
    super.commentsCount = 0,
    super.repostsCount = 0,
    super.userName,
    super.userAvatarUrl,
    super.isLikedByMe = false,
    super.isDislikedByMe = false,
    super.isRepostedByMe = false,
  });

  factory PostModel.fromJson(Map<String, dynamic> json) {
    return PostModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      imageUrl: (json['image_url'] as String?) ?? '',
      caption: (json['caption'] as String?) ?? '',
      videoUrl: json['video_url'] as String?,
      videoDurationSeconds: (json['video_duration_seconds'] as int?) ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      likesCount: (json['likes_count'] as int?) ?? 0,
      dislikesCount: (json['dislikes_count'] as int?) ?? 0,
      commentsCount: (json['comments_count'] as int?) ?? 0,
      repostsCount: (json['reposts_count'] as int?) ?? 0,
      userName: json['user_name'] as String?,
      userAvatarUrl: json['user_avatar'] as String?,
      isLikedByMe: (json['is_liked_by_me'] as bool?) ?? false,
      isDislikedByMe: (json['is_disliked_by_me'] as bool?) ?? false,
      isRepostedByMe: (json['is_reposted_by_me'] as bool?) ?? false,
    );
  }
}
