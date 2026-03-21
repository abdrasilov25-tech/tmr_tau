import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../domain/entities/story_entity.dart';
import '../../domain/entities/story_group_entity.dart';
import '../../domain/entities/story_reply_entity.dart';
import '../../domain/entities/story_view_entity.dart';
import '../../domain/repositories/stories_repository.dart';
import '../models/story_model.dart';
import '../models/story_reply_model.dart';

class StoriesRepositoryImpl implements StoriesRepository {
  StoriesRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<List<StoryEntity>> getActiveStories() async {
    try {
      final res = await _client
          .from(SupabaseConstants.storiesTable)
          .select('*, users!user_id(name, avatar)')
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false);
      return (res as List).map((e) => _mapStory(e as Map<String, dynamic>)).toList();
    } catch (_) {
      final res = await _client
          .from(SupabaseConstants.storiesTable)
          .select()
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false);
      return (res as List).map((e) => _mapStory(e as Map<String, dynamic>)).toList();
    }
  }

  @override
  Future<List<StoryGroupEntity>> getStoriesGroupedByUser() async {
    final list = await getActiveStories();
    final map = <String, List<StoryEntity>>{};
    for (final s in list) {
      map.putIfAbsent(s.userId, () => []).add(s);
    }
    return map.entries.map((e) {
      final first = e.value.first;
      return StoryGroupEntity(
        userId: e.key,
        stories: e.value,
        userName: first.userName,
        userAvatarUrl: first.userAvatarUrl,
      );
    }).toList();
  }

  @override
  Future<Set<String>> getViewedStoryIds(String viewerId) async {
    final res = await _client
        .from(SupabaseConstants.storyViewsTable)
        .select('story_id')
        .eq('viewer_id', viewerId);
    return (res as List)
        .map((e) => (e as Map<String, dynamic>)['story_id'] as String?)
        .whereType<String>()
        .toSet();
  }

  @override
  Future<void> markStoryViewed({
    required String storyId,
    required String viewerId,
  }) async {
    await _client.from(SupabaseConstants.storyViewsTable).upsert({
      'story_id': storyId,
      'viewer_id': viewerId,
      'viewed_at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<List<StoryViewEntity>> getStoryViews(String storyId) async {
    final res = await _client
        .from(SupabaseConstants.storyViewsTable)
        .select('story_id, viewer_id, viewed_at, users!viewer_id(name, avatar)')
        .eq('story_id', storyId)
        .order('viewed_at', ascending: false);
    return (res as List).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final users = map['users'];
      final userMap = users is Map ? Map<String, dynamic>.from(users) : null;
      return StoryViewEntity(
        storyId: map['story_id'] as String,
        viewerId: map['viewer_id'] as String,
        viewedAt: DateTime.parse(map['viewed_at'] as String),
        viewerName: userMap?['name'] as String?,
        viewerAvatarUrl: userMap?['avatar'] as String?,
      );
    }).toList(growable: false);
  }

  @override
  Future<int> getStoryViewsCount(String storyId) async {
    final res = await _client
        .from(SupabaseConstants.storyViewsTable)
        .select('story_id')
        .eq('story_id', storyId);
    return (res as List).length;
  }

  @override
  Future<List<StoryEntity>> getStoriesByUser(String userId) async {
    try {
      final res = await _client
          .from(SupabaseConstants.storiesTable)
          .select('*, users!user_id(name, avatar)')
          .eq('user_id', userId)
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: true);
      return (res as List).map((e) => _mapStory(e as Map<String, dynamic>)).toList();
    } catch (_) {
      final res = await _client
          .from(SupabaseConstants.storiesTable)
          .select()
          .eq('user_id', userId)
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: true);
      return (res as List).map((e) => _mapStory(e as Map<String, dynamic>)).toList();
    }
  }

  @override
  Future<void> addStory({
    required String userId,
    required String imageUrl,
    String? videoUrl,
    String? caption,
  }) async {
    await _client.from(SupabaseConstants.storiesTable).insert({
      'user_id': userId,
      'image_url': imageUrl,
      'video_url': videoUrl,
      'caption': caption,
      'expires_at': DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
    });
  }

  @override
  Future<void> updateStory(String storyId, {String? caption}) async {
    await _client.from(SupabaseConstants.storiesTable).update({'caption': caption ?? ''}).eq('id', storyId);
  }

  @override
  Future<void> deleteStory(String storyId, String userId) async {
    await _client.from(SupabaseConstants.storiesTable).delete().eq('id', storyId).eq('user_id', userId);
  }

  @override
  Future<List<StoryReplyEntity>> getStoryReplies(String storyId) async {
    try {
      final res = await _client
          .from(SupabaseConstants.storyRepliesTable)
          .select('*, users!user_id(name, avatar)')
          .eq('story_id', storyId)
          .order('created_at', ascending: true);
      return (res as List).map((e) => _mapReply(e as Map<String, dynamic>)).toList();
    } catch (_) {
      final res = await _client
          .from(SupabaseConstants.storyRepliesTable)
          .select()
          .eq('story_id', storyId)
          .order('created_at', ascending: true);
      return (res as List).map((e) => _mapReply(e as Map<String, dynamic>)).toList();
    }
  }

  @override
  Future<void> addStoryReply({required String storyId, required String userId, required String text}) async {
    await _client.from(SupabaseConstants.storyRepliesTable).insert({
      'story_id': storyId,
      'user_id': userId,
      'text': text,
    });
  }

  @override
  Future<void> deleteStoryReply(String replyId, String userId) async {
    await _client.from(SupabaseConstants.storyRepliesTable).delete().eq('id', replyId).eq('user_id', userId);
  }

  @override
  Future<void> deleteExpiredStories() async {
    await _client
        .from(SupabaseConstants.storiesTable)
        .delete()
        .lt('expires_at', DateTime.now().toIso8601String());
  }

  StoryEntity _mapStory(Map<String, dynamic> json) {
    final users = json['users'];
    Map<String, dynamic>? u;
    if (users is Map) u = Map<String, dynamic>.from(users);
    final row = Map<String, dynamic>.from(json)
      ..remove('users')
      ..['user_name'] = u?['name']
      ..['user_avatar'] = u?['avatar'];
    return StoryModel.fromJson(row);
  }

  StoryReplyEntity _mapReply(Map<String, dynamic> json) {
    final users = json['users'];
    Map<String, dynamic>? u;
    if (users is Map) u = Map<String, dynamic>.from(users);
    final row = Map<String, dynamic>.from(json)
      ..remove('users')
      ..['user_name'] = u?['name']
      ..['user_avatar'] = u?['avatar'];
    return StoryReplyModel.fromJson(row);
  }
}
