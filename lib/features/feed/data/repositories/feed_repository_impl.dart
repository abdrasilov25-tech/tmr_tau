import '../../../../features/product/domain/entities/product_entity.dart';
import '../../../../features/product/domain/repositories/product_repository.dart';
import '../../../../features/profile/domain/repositories/profile_repository.dart';
import '../../../../features/settings/domain/load_all_blocked_user_ids.dart';
import '../../../../features/settings/domain/repositories/settings_repository.dart';
import '../../domain/repositories/feed_repository.dart';

class FeedRepositoryImpl implements FeedRepository {
  FeedRepositoryImpl(
    this._productRepository,
    this._profileRepository,
    this._settingsRepository,
  );
  final ProductRepository _productRepository;
  final ProfileRepository _profileRepository;
  final SettingsRepository _settingsRepository;

  @override
  Future<List<ProductEntity>> getFeed({
    int limit = 20,
    int offset = 0,
    String? currentUserId,
  }) async {
    var exclude = const <String>{};
    if (currentUserId != null && currentUserId.isNotEmpty) {
      try {
        exclude = await loadAllBlockedUserIds(
          repository: _settingsRepository,
          blockerId: currentUserId,
        );
      } catch (_) {}
    }
    return _productRepository.getFeedProducts(
      limit: limit,
      offset: offset,
      currentUserId: currentUserId,
      excludeSellerIds: exclude,
    );
  }

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
