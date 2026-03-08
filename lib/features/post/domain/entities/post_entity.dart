import 'package:equatable/equatable.dart';

class PostEntity extends Equatable {
  const PostEntity({
    required this.id,
    required this.userId,
    this.imageUrl = '',
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
  });

  final String id;
  final String userId;
  final String imageUrl;
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

  PostEntity copyWith({
    String? id,
    String? userId,
    String? imageUrl,
    String? caption,
    String? videoUrl,
    int? videoDurationSeconds,
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
  }) {
    return PostEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      imageUrl: imageUrl ?? this.imageUrl,
      caption: caption ?? this.caption,
      videoUrl: videoUrl ?? this.videoUrl,
      videoDurationSeconds: videoDurationSeconds ?? this.videoDurationSeconds,
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
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        imageUrl,
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
      ];
}
