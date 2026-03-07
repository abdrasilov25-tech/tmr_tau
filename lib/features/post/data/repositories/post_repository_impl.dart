import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../domain/entities/post_comment_entity.dart';
import '../../domain/entities/post_entity.dart';
import '../../domain/repositories/post_repository.dart';
import '../models/post_comment_model.dart';
import '../models/post_model.dart';

class PostRepositoryImpl implements PostRepository {
  PostRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<List<PostEntity>> getFeedPosts({
    int limit = 20,
    int offset = 0,
    String? currentUserId,
  }) async {
    final res = await _client
        .from(SupabaseConstants.postsTable)
        .select('*, users!user_id(name, avatar)')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    final list = (res as List).map((e) => _mapPost(e as Map<String, dynamic>)).toList();
    if (currentUserId != null && list.isNotEmpty) {
      final ids = list.map((e) => e.id).toList();
      final likes = await _client
          .from(SupabaseConstants.postLikesTable)
          .select('post_id')
          .eq('user_id', currentUserId)
          .inFilter('post_id', ids);
      final reposts = await _client
          .from(SupabaseConstants.repostsTable)
          .select('post_id')
          .eq('user_id', currentUserId)
          .inFilter('post_id', ids);
      final likedIds = (likes as List).map((e) => (e as Map)['post_id'] as String).toSet();
      final repostedIds = (reposts as List).map((e) => (e as Map)['post_id'] as String).toSet();
      return list
          .map((p) => PostModel(
                id: p.id,
                userId: p.userId,
                imageUrl: p.imageUrl,
                caption: p.caption,
                createdAt: p.createdAt,
                likesCount: p.likesCount,
                dislikesCount: p.dislikesCount,
                commentsCount: p.commentsCount,
                repostsCount: p.repostsCount,
                userName: p.userName,
                userAvatarUrl: p.userAvatarUrl,
                isLikedByMe: likedIds.contains(p.id),
                isDislikedByMe: p.isDislikedByMe,
                isRepostedByMe: repostedIds.contains(p.id),
              ))
          .toList();
    }
    return list;
  }

  @override
  Future<List<PostEntity>> getPopularPosts({String? userId}) async {
    return getFeedPosts(limit: 50, offset: 0, currentUserId: userId);
  }

  @override
  Future<List<PostEntity>> getPostsByUser(String userId, {String? currentUserId}) async {
    final res = await _client
        .from(SupabaseConstants.postsTable)
        .select('*, users!user_id(name, avatar)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    final list = (res as List).map((e) => _mapPost(e as Map<String, dynamic>)).toList();
    if (currentUserId != null && list.isNotEmpty) {
      final ids = list.map((e) => e.id).toList();
      final likes = await _client
          .from(SupabaseConstants.postLikesTable)
          .select('post_id')
          .eq('user_id', currentUserId)
          .inFilter('post_id', ids);
      final likedIds = (likes as List).map((e) => (e as Map)['post_id'] as String).toSet();
      return list
          .map((p) => PostModel(
                id: p.id,
                userId: p.userId,
                imageUrl: p.imageUrl,
                caption: p.caption,
                createdAt: p.createdAt,
                likesCount: p.likesCount,
                dislikesCount: p.dislikesCount,
                commentsCount: p.commentsCount,
                repostsCount: p.repostsCount,
                userName: p.userName,
                userAvatarUrl: p.userAvatarUrl,
                isLikedByMe: likedIds.contains(p.id),
                isDislikedByMe: p.isDislikedByMe,
                isRepostedByMe: p.isRepostedByMe,
              ))
          .toList();
    }
    return list;
  }

  PostEntity _mapPost(Map<String, dynamic> json) {
    final users = json['users'];
    Map<String, dynamic>? userMap;
    if (users is Map) {
      userMap = Map<String, dynamic>.from(users);
    }
    final row = Map<String, dynamic>.from(json)
      ..remove('users')
      ..['user_name'] = userMap?['name']
      ..['user_avatar'] = userMap?['avatar'];
    return PostModel.fromJson(row);
  }

  @override
  Future<PostEntity> createPost({
    required String userId,
    required String imageUrl,
    String caption = '',
  }) async {
    final res = await _client
        .from(SupabaseConstants.postsTable)
        .insert({
          'user_id': userId,
          'image_url': imageUrl,
          'caption': caption,
        })
        .select('*, users!user_id(name, avatar)')
        .single();
    return _mapPost(Map<String, dynamic>.from(res as Map));
  }

  @override
  Future<void> toggleLike(String postId, String userId) async {
    final existing = await _client
        .from(SupabaseConstants.postLikesTable)
        .select('post_id')
        .eq('post_id', postId)
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) {
      await _client
          .from(SupabaseConstants.postLikesTable)
          .delete()
          .eq('post_id', postId)
          .eq('user_id', userId);
    } else {
      await _client.from(SupabaseConstants.postLikesTable).insert({
        'post_id': postId,
        'user_id': userId,
      });
    }
  }

  @override
  Future<void> toggleDislike(String postId, String userId) async {
    final existing = await _client
        .from(SupabaseConstants.postDislikesTable)
        .select('post_id')
        .eq('post_id', postId)
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) {
      await _client
          .from(SupabaseConstants.postDislikesTable)
          .delete()
          .eq('post_id', postId)
          .eq('user_id', userId);
    } else {
      await _client.from(SupabaseConstants.postDislikesTable).insert({
        'post_id': postId,
        'user_id': userId,
      });
    }
  }

  @override
  Future<void> toggleRepost(String postId, String userId) async {
    final existing = await _client
        .from(SupabaseConstants.repostsTable)
        .select('post_id')
        .eq('post_id', postId)
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) {
      await _client
          .from(SupabaseConstants.repostsTable)
          .delete()
          .eq('post_id', postId)
          .eq('user_id', userId);
    } else {
      await _client.from(SupabaseConstants.repostsTable).insert({
        'post_id': postId,
        'user_id': userId,
      });
    }
  }

  @override
  Future<List<PostCommentEntity>> getComments(String postId) async {
    final res = await _client
        .from(SupabaseConstants.postCommentsTable)
        .select('*, users!user_id(name, avatar)')
        .eq('post_id', postId)
        .order('created_at', ascending: true);
    return (res as List)
        .map((e) {
          final m = e as Map<String, dynamic>;
          final users = m['users'];
          Map<String, dynamic>? u;
          if (users is Map) u = Map<String, dynamic>.from(users);
          final row = Map<String, dynamic>.from(m)
            ..remove('users')
            ..['user_name'] = u?['name']
            ..['user_avatar'] = u?['avatar'];
          return PostCommentModel.fromJson(row);
        })
        .toList();
  }

  @override
  Future<PostCommentEntity> addComment({
    required String postId,
    required String userId,
    required String text,
  }) async {
    final res = await _client
        .from(SupabaseConstants.postCommentsTable)
        .insert({'post_id': postId, 'user_id': userId, 'text': text})
        .select('*, users!user_id(name, avatar)')
        .single();
    final m = Map<String, dynamic>.from(res as Map);
    final users = m['users'];
    Map<String, dynamic>? u;
    if (users is Map) u = Map<String, dynamic>.from(users);
    final row = Map<String, dynamic>.from(m)
      ..remove('users')
      ..['user_name'] = u?['name']
      ..['user_avatar'] = u?['avatar'];
    return PostCommentModel.fromJson(row);
  }

  @override
  Future<PostEntity?> getPostById(String postId, {String? currentUserId}) async {
    final res = await _client
        .from(SupabaseConstants.postsTable)
        .select('*, users!user_id(name, avatar)')
        .eq('id', postId)
        .maybeSingle();
    if (res == null) return null;
    final post = _mapPost(Map<String, dynamic>.from(res as Map));
    if (currentUserId != null) {
      final like = await _client
          .from(SupabaseConstants.postLikesTable)
          .select('post_id')
          .eq('post_id', postId)
          .eq('user_id', currentUserId)
          .maybeSingle();
      final repost = await _client
          .from(SupabaseConstants.repostsTable)
          .select('post_id')
          .eq('post_id', postId)
          .eq('user_id', currentUserId)
          .maybeSingle();
      return PostModel(
        id: post.id,
        userId: post.userId,
        imageUrl: post.imageUrl,
        caption: post.caption,
        createdAt: post.createdAt,
        likesCount: post.likesCount,
        dislikesCount: post.dislikesCount,
        commentsCount: post.commentsCount,
        repostsCount: post.repostsCount,
        userName: post.userName,
        userAvatarUrl: post.userAvatarUrl,
        isLikedByMe: like != null,
        isDislikedByMe: post.isDislikedByMe,
        isRepostedByMe: repost != null,
      );
    }
    return post;
  }
}
