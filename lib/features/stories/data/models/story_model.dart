import '../../domain/entities/story_entity.dart';

class StoryModel extends StoryEntity {
  const StoryModel({
    required super.id,
    required super.userId,
    required super.imageUrl,
    required super.createdAt,
    required super.expiresAt,
    super.videoUrl,
    super.caption,
    super.userName,
    super.userAvatarUrl,
    super.originalPostId,
    super.originalPostAuthorId,
    super.originalPostAuthorName,
    super.originalPostPreviewUrl,
    super.videoDurationSeconds = 0,
    super.musicTitle,
    super.musicArtist,
    super.musicExternalUrl,
    super.overlaysJson,
  });

  factory StoryModel.fromJson(Map<String, dynamic> json) {
    return StoryModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      imageUrl: json['image_url'] as String? ?? '',
      videoUrl: json['video_url'] as String?,
      caption: json['caption'] as String?,
      createdAt: _parseDateTime(json['created_at']),
      expiresAt: _parseDateTime(json['expires_at']),
      userName: json['user_name'] as String?,
      userAvatarUrl: json['user_avatar'] as String?,
      originalPostId: json['original_post_id'] as String?,
      originalPostAuthorId: json['original_post_author_id'] as String?,
      originalPostAuthorName: json['original_post_author_name'] as String?,
      originalPostPreviewUrl: json['original_post_preview_url'] as String?,
      videoDurationSeconds: (json['video_duration_seconds'] as num?)?.toInt() ?? 0,
      musicTitle: json['music_title'] as String?,
      musicArtist: json['music_artist'] as String?,
      musicExternalUrl: json['music_external_url'] as String?,
      overlaysJson: json['overlays_json'] as String?,
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.parse(value);
    throw FormatException('Invalid datetime value: $value');
  }
}
