import '../../../../features/product/domain/entities/product_entity.dart';

abstract class FeedRepository {
  Future<List<ProductEntity>> getFeed({
    int limit = 20,
    int offset = 0,
    String? currentUserId,
    bool forceRefresh = false,
  });

  /// Сброс кэша первой страницы (выход из аккаунта).
  void invalidateFeedCache();

  Future<void> toggleProductLike(String productId, String userId);
  Future<void> toggleFollow(String followerId, String followingId);
  Future<void> toggleProductRepost(String productId, String userId);
}
