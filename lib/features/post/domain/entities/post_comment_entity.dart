import 'package:equatable/equatable.dart';

class PostCommentEntity extends Equatable {
  const PostCommentEntity({
    required this.id,
    required this.postId,
    required this.userId,
    required this.text,
    required this.createdAt,
    this.userName,
    this.userAvatarUrl,
  });

  final String id;
  final String postId;
  final String userId;
  final String text;
  final DateTime createdAt;
  final String? userName;
  final String? userAvatarUrl;

  @override
  List<Object?> get props => [id, postId, userId, text, createdAt, userName, userAvatarUrl];
}
