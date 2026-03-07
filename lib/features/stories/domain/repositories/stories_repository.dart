import '../entities/story_entity.dart';

abstract class StoriesRepository {
  Future<List<StoryEntity>> getActiveStories();
  Future<List<StoryEntity>> getStoriesByUser(String userId);
  Future<StoryEntity> addStory({
    required String userId,
    required String imageUrl,
    String? videoUrl,
  });
  Future<void> deleteExpiredStories();
}
