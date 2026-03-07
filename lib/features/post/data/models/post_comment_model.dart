import '../../domain/entities/post_comment_entity.dart';

class PostCommentModel extends PostCommentEntity {
  const PostCommentModel({
    required super.id,
    required super.postId,
    required super.userId,
    required super.text,
    required super.createdAt,
    super.userName,
    super.userAvatarUrl,
  });

  factory PostCommentModel.fromJson(Map<String, dynamic> json) {
    return PostCommentModel(
      id: json['id'] as String,
      postId: json['post_id'] as String,
      userId: json['user_id'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      userName: json['user_name'] as String?,
      userAvatarUrl: json['user_avatar'] as String?,
    );
  }
}
