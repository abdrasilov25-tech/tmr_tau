import 'package:equatable/equatable.dart';

class PostCommentEntity extends Equatable {
  const PostCommentEntity({
    required this.id,
    required this.postId,
    required this.userId,
    required this.text,
    required this.createdAt,
    this.parentId,
    this.replyToUserName,
    this.userName,
    this.userAvatarUrl,
  });

  final String id;
  final String postId;
  final String userId;
  final String text;
  final DateTime createdAt;
  /// Id комментария, на который отвечают (ответ в обсуждении).
  final String? parentId;
  /// Имя пользователя, которому отвечают (для отображения "Ответ на Имя").
  final String? replyToUserName;
  final String? userName;
  final String? userAvatarUrl;

  PostCommentEntity copyWith({
    String? id,
    String? postId,
    String? userId,
    String? text,
    DateTime? createdAt,
    String? parentId,
    String? replyToUserName,
    String? userName,
    String? userAvatarUrl,
  }) {
    return PostCommentEntity(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      userId: userId ?? this.userId,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      parentId: parentId ?? this.parentId,
      replyToUserName: replyToUserName ?? this.replyToUserName,
      userName: userName ?? this.userName,
      userAvatarUrl: userAvatarUrl ?? this.userAvatarUrl,
    );
  }

  @override
  List<Object?> get props => [id, postId, userId, text, createdAt, parentId, replyToUserName, userName, userAvatarUrl];
}
