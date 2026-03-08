import '../../domain/entities/story_reply_entity.dart';

class StoryReplyModel extends StoryReplyEntity {
  const StoryReplyModel({
    required super.id,
    required super.storyId,
    required super.userId,
    required super.text,
    required super.createdAt,
    super.userName,
    super.userAvatarUrl,
  });

  factory StoryReplyModel.fromJson(Map<String, dynamic> json) {
    return StoryReplyModel(
      id: json['id'] as String,
      storyId: json['story_id'] as String,
      userId: json['user_id'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      userName: json['user_name'] as String?,
      userAvatarUrl: json['user_avatar'] as String?,
    );
  }
}
