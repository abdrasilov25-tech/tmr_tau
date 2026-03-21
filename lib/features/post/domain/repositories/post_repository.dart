import '../entities/post_comment_entity.dart';
import '../entities/post_entity.dart';

abstract class PostRepository {
  Future<List<PostEntity>> getFeedPosts({
    int limit = 20,
    int offset = 0,
    String? currentUserId,
  });
  Future<List<PostEntity>> getPopularPosts({String? userId});
  Future<List<PostEntity>> getNewsPosts({
    int limit = 20,
    int offset = 0,
    String? currentUserId,
  });
  Future<List<PostEntity>> getPostsByUser(String userId, {String? currentUserId});
  Future<PostEntity> createPost({
    required String userId,
    String imageUrl = '',
    String caption = '',
    String? videoUrl,
    int videoDurationSeconds = 0,
    String kind = 'news',
  });
  Future<void> toggleLike(String postId, String userId);
  Future<void> toggleDislike(String postId, String userId);
  Future<void> toggleRepost(String postId, String userId);
  Future<void> toggleSave(String postId, String userId);
  Future<List<PostEntity>> getSavedPublications(
    String userId, {
    int limit = 50,
    int offset = 0,
  });
  Future<List<PostCommentEntity>> getComments(String postId);
  Future<void> addComment({
    required String postId,
    required String userId,
    required String text,
    String? parentCommentId,
  });
  Future<List<PostEntity>> searchPostsByCursor({
    required String query,
    int limit = 10,
    DateTime? lastCreatedAt,
    String? currentUserId,
  });
  Future<List<PostEntity>> searchPublicationsByCursor({
    required String query,
    int limit = 10,
    DateTime? lastCreatedAt,
    String? currentUserId,
  });
  Future<PostEntity?> getPostById(String postId, {String? currentUserId});
  Future<void> updatePost({
    required String postId,
    String? caption,
    String? imageUrl,
    String? videoUrl,
    int? videoDurationSeconds,
    bool clearImage = false,
    bool clearVideo = false,
  });
  Future<void> deletePost(String postId, String userId);
  Future<void> deletePostComment(String commentId, String userId);
}
