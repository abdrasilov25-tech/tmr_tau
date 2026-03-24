import 'package:equatable/equatable.dart';

class PostEntity extends Equatable {
  const PostEntity({
    required this.id,
    required this.userId,
    this.kind = 'news',
    this.imageUrl = '',
    this.imageUrls = const [],
    this.caption = '',
    this.videoUrl,
    this.videoDurationSeconds = 0,
    required this.createdAt,
    this.likesCount = 0,
    this.dislikesCount = 0,
    this.commentsCount = 0,
    this.repostsCount = 0,
    this.userName,
    this.userAvatarUrl,
    this.isLikedByMe = false,
    this.isDislikedByMe = false,
    this.isRepostedByMe = false,
    this.isSavedByMe = false,
  });

  final String id;
  final String userId;
  final String kind;
  final String imageUrl;
  /// Несколько фото (новости). Пусто = только [imageUrl].
  final List<String> imageUrls;
  final String caption;
  final String? videoUrl;
  final int videoDurationSeconds;
  final DateTime createdAt;
  final int likesCount;
  final int dislikesCount;
  final int commentsCount;
  final int repostsCount;
  final String? userName;
  final String? userAvatarUrl;
  final bool isLikedByMe;
  final bool isDislikedByMe;
  final bool isRepostedByMe;
  final bool isSavedByMe;

  /// Все URL фото для карусели (мульти или одно из legacy `image_url`).
  List<String> get displayImageUrls {
    if (imageUrls.isNotEmpty) return List.unmodifiable(imageUrls);
    if (imageUrl.isNotEmpty) return [imageUrl];
    return const [];
  }

  PostEntity copyWith({
    String? id,
    String? userId,
    String? kind,
    String? imageUrl,
    List<String>? imageUrls,
    String? caption,
    String? videoUrl,
    int? videoDurationSeconds,
    bool clearImage = false,
    bool clearVideo = false,
    DateTime? createdAt,
    int? likesCount,
    int? dislikesCount,
    int? commentsCount,
    int? repostsCount,
    String? userName,
    String? userAvatarUrl,
    bool? isLikedByMe,
    bool? isDislikedByMe,
    bool? isRepostedByMe,
    bool? isSavedByMe,
  }) {
    return PostEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      kind: kind ?? this.kind,
      imageUrl: clearImage ? '' : (imageUrl ?? this.imageUrl),
      imageUrls: clearImage ? const [] : (imageUrls ?? this.imageUrls),
      caption: caption ?? this.caption,
      videoUrl: clearVideo ? null : (videoUrl ?? this.videoUrl),
      videoDurationSeconds: clearVideo ? 0 : (videoDurationSeconds ?? this.videoDurationSeconds),
      createdAt: createdAt ?? this.createdAt,
      likesCount: likesCount ?? this.likesCount,
      dislikesCount: dislikesCount ?? this.dislikesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      repostsCount: repostsCount ?? this.repostsCount,
      userName: userName ?? this.userName,
      userAvatarUrl: userAvatarUrl ?? this.userAvatarUrl,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      isDislikedByMe: isDislikedByMe ?? this.isDislikedByMe,
      isRepostedByMe: isRepostedByMe ?? this.isRepostedByMe,
      isSavedByMe: isSavedByMe ?? this.isSavedByMe,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        kind,
        imageUrl,
        imageUrls,
        caption,
        videoUrl,
        videoDurationSeconds,
        createdAt,
        likesCount,
        dislikesCount,
        commentsCount,
        repostsCount,
        userName,
        userAvatarUrl,
        isLikedByMe,
        isDislikedByMe,
        isRepostedByMe,
        isSavedByMe,
      ];
}
