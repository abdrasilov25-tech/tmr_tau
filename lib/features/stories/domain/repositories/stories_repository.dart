import '../entities/story_entity.dart';
import '../entities/story_group_entity.dart';

import '../entities/story_reply_entity.dart';
import '../entities/story_view_entity.dart';

abstract class StoriesRepository {
  Future<List<StoryEntity>> getActiveStories();
  Future<List<StoryGroupEntity>> getStoriesGroupedByUser();
  Future<Set<String>> getViewedStoryIds(String viewerId);
  Future<void> markStoryViewed({
    required String storyId,
    required String viewerId,
  });
  Future<List<StoryViewEntity>> getStoryViews(String storyId);
  Future<int> getStoryViewsCount(String storyId);
  Future<List<StoryEntity>> getStoriesByUser(String userId);
  Future<void> addStory({
    required String userId,
    required String imageUrl,
    String? videoUrl,
    String? caption,
    String? originalPostId,
    String? originalPostAuthorId,
    String? originalPostAuthorName,
    String? originalPostPreviewUrl,
    int videoDurationSeconds = 0,
    String? musicTitle,
    String? musicArtist,
    String? musicExternalUrl,
    String? overlaysJson,
  });
  Future<void> updateStory(String storyId, {String? caption});
  Future<void> deleteStory(String storyId, String userId);
  Future<void> deleteExpiredStories();
  Future<List<StoryReplyEntity>> getStoryReplies(String storyId);
  Future<void> addStoryReply({required String storyId, required String userId, required String text});
  Future<void> deleteStoryReply(String replyId, String userId);
}
