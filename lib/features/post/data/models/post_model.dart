import '../../domain/entities/post_entity.dart';

class PostModel extends PostEntity {
  const PostModel({
    required super.id,
    required super.userId,
    super.kind = 'news',
    super.imageUrl = '',
    super.imageUrls = const [],
    super.caption = '',
    super.videoUrl,
    super.videoDurationSeconds = 0,
    required super.createdAt,
    super.likesCount = 0,
    super.dislikesCount = 0,
    super.commentsCount = 0,
    super.viewsCount = 0,
    super.repostsCount = 0,
    super.userName,
    super.userAvatarUrl,
    super.isLikedByMe = false,
    super.isDislikedByMe = false,
    super.isRepostedByMe = false,
    super.isSavedByMe = false,
  });

  factory PostModel.fromJson(Map<String, dynamic> json) {
    final rawKind = (json['kind'] as String?)?.trim().toLowerCase() ?? '';
    final safeKind = rawKind == 'news'
        ? 'news'
        : 'publication';
    List<String> urls = const [];
    final rawUrls = json['image_urls'];
    if (rawUrls is List) {
      urls = rawUrls
          .map((e) => e == null ? '' : e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return PostModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      kind: safeKind,
      imageUrl: (json['image_url'] as String?) ?? '',
      imageUrls: urls,
      caption: (json['caption'] as String?) ?? '',
      videoUrl: json['video_url'] as String?,
      videoDurationSeconds: (json['video_duration_seconds'] as int?) ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      likesCount: (json['likes_count'] as int?) ?? 0,
      dislikesCount: (json['dislikes_count'] as int?) ?? 0,
      commentsCount: (json['comments_count'] as int?) ?? 0,
      viewsCount: (json['views_count'] as int?) ?? 0,
      repostsCount: (json['reposts_count'] as int?) ?? 0,
      userName: json['user_name'] as String?,
      userAvatarUrl: json['user_avatar'] as String?,
      isLikedByMe: (json['is_liked_by_me'] as bool?) ?? false,
      isDislikedByMe: (json['is_disliked_by_me'] as bool?) ?? false,
      isRepostedByMe: (json['is_reposted_by_me'] as bool?) ?? false,
      isSavedByMe: (json['is_saved_by_me'] as bool?) ?? false,
    );
  }
}
