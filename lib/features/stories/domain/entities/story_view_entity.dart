import 'package:equatable/equatable.dart';

class StoryViewEntity extends Equatable {
  const StoryViewEntity({
    required this.storyId,
    required this.viewerId,
    required this.viewedAt,
    this.viewerName,
    this.viewerAvatarUrl,
  });

  final String storyId;
  final String viewerId;
  final DateTime viewedAt;
  final String? viewerName;
  final String? viewerAvatarUrl;

  @override
  List<Object?> get props => [storyId, viewerId, viewedAt];
}
