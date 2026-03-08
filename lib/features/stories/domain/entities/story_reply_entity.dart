import 'package:equatable/equatable.dart';

class StoryReplyEntity extends Equatable {
  const StoryReplyEntity({
    required this.id,
    required this.storyId,
    required this.userId,
    required this.text,
    required this.createdAt,
    this.userName,
    this.userAvatarUrl,
  });

  final String id;
  final String storyId;
  final String userId;
  final String text;
  final DateTime createdAt;
  final String? userName;
  final String? userAvatarUrl;

  @override
  List<Object?> get props => [id, storyId, userId, text, createdAt];
}
