import 'story_entity.dart';

/// Группа сторис одного пользователя (как в ленте Instagram).
class StoryGroupEntity {
  const StoryGroupEntity({
    required this.userId,
    required this.stories,
    this.userName,
    this.userAvatarUrl,
  });

  final String userId;
  final List<StoryEntity> stories;
  final String? userName;
  final String? userAvatarUrl;

  StoryEntity get firstStory => stories.first;
}
