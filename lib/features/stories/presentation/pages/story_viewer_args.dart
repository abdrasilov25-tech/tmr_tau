import '../../domain/entities/story_group_entity.dart';

/// Аргументы для открытия экрана просмотра сторис.
class StoryViewerArgs {
  const StoryViewerArgs({
    required this.groups,
    this.initialGroupIndex = 0,
  });

  final List<StoryGroupEntity> groups;
  final int initialGroupIndex;
}
