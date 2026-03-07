import '../../domain/entities/story_entity.dart';

class StoryModel extends StoryEntity {
  const StoryModel({
    required super.id,
    required super.userId,
    required super.imageUrl,
    required super.createdAt,
    required super.expiresAt,
    super.videoUrl,
    super.userName,
    super.userAvatarUrl,
  });

  factory StoryModel.fromJson(Map<String, dynamic> json) {
    return StoryModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      imageUrl: json['image_url'] as String? ?? '',
      videoUrl: json['video_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      userName: json['user_name'] as String?,
      userAvatarUrl: json['user_avatar'] as String?,
    );
  }
}
