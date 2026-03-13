import '../../../../features/product/domain/entities/product_entity.dart';
import '../../../../features/product/domain/repositories/product_repository.dart';
import '../../../../features/profile/domain/repositories/profile_repository.dart';
import '../../domain/repositories/feed_repository.dart';

class FeedRepositoryImpl implements FeedRepository {
  FeedRepositoryImpl(this._productRepository, this._profileRepository);
  final ProductRepository _productRepository;
  final ProfileRepository _profileRepository;

  @override
  Future<List<ProductEntity>> getFeed({
    int limit = 20,
    int offset = 0,
    String? currentUserId,
  }) =>
      _productRepository.getFeedProducts(
        limit: limit,
        offset: offset,
        currentUserId: currentUserId,
      );

  @override
  Future<void> toggleProductLike(String productId, String userId) =>
      _productRepository.toggleProductLike(productId, userId);

  @override
  Future<void> toggleFollow(String followerId, String followingId) =>
      _profileRepository.toggleFollow(followerId, followingId);

  @override
  Future<void> toggleProductRepost(String productId, String userId) =>
      _productRepository.toggleProductRepost(productId, userId);
}
