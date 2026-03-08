import 'package:equatable/equatable.dart';

class StoryEntity extends Equatable {
  const StoryEntity({
    required this.id,
    required this.userId,
    required this.imageUrl,
    required this.createdAt,
    required this.expiresAt,
    this.videoUrl,
    this.caption,
    this.userName,
    this.userAvatarUrl,
  });

  final String id;
  final String userId;
  final String imageUrl;
  final String? videoUrl;
  final String? caption;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? userName;
  final String? userAvatarUrl;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  @override
  List<Object?> get props =>
      [id, userId, imageUrl, videoUrl, caption, createdAt, expiresAt];
}
