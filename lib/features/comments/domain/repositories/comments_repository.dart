import '../entities/product_comment_entity.dart';

abstract class CommentsRepository {
  Future<List<ProductCommentEntity>> getProductComments(String productId);
  Future<void> addComment({
    required String productId,
    required String userId,
    required String text,
  });
  Future<void> deleteComment(String commentId, String userId);
}
