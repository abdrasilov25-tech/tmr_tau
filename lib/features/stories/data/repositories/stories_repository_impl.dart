import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../domain/entities/story_entity.dart';
import '../../domain/repositories/stories_repository.dart';
import '../models/story_model.dart';

class StoriesRepositoryImpl implements StoriesRepository {
  StoriesRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<List<StoryEntity>> getActiveStories() async {
    final res = await _client
        .from(SupabaseConstants.storiesTable)
        .select('*, users!user_id(name, avatar)')
        .gt('expires_at', DateTime.now().toIso8601String())
        .order('created_at', ascending: false);
    return (res as List).map((e) => _mapStory(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<StoryEntity>> getStoriesByUser(String userId) async {
    final res = await _client
        .from(SupabaseConstants.storiesTable)
        .select('*, users!user_id(name, avatar)')
        .eq('user_id', userId)
        .gt('expires_at', DateTime.now().toIso8601String())
        .order('created_at', ascending: true);
    return (res as List).map((e) => _mapStory(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<StoryEntity> addStory({
    required String userId,
    required String imageUrl,
    String? videoUrl,
  }) async {
    final res = await _client
        .from(SupabaseConstants.storiesTable)
        .insert({
          'user_id': userId,
          'image_url': imageUrl,
          'video_url': videoUrl,
          'expires_at': DateTime.now()
              .add(const Duration(hours: 24))
              .toIso8601String(),
        })
        .select('*, users!user_id(name, avatar)')
        .single();
    return _mapStory(Map<String, dynamic>.from(res as Map));
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
}
