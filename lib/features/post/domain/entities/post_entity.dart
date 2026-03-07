import 'package:equatable/equatable.dart';

class PostEntity extends Equatable {
  const PostEntity({
    required this.id,
    required this.userId,
    required this.imageUrl,
    this.caption = '',
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

  @override
  List<Object?> get props => [
        id,
        userId,
        imageUrl,
        caption,
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
