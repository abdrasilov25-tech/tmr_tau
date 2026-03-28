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

  static const Duration _firstPageTtl = Duration(minutes: 5);

  String? _cacheUserKey;
  int? _cachedLimit;
  DateTime? _cachedAt;
  List<ProductEntity>? _cachedFirstPage;

  String _feedCacheKey(String? userId) =>
      (userId == null || userId.isEmpty) ? '__anon__' : userId;

  @override
  void invalidateFeedCache() {
    _cachedFirstPage = null;
    _cachedAt = null;
    _cacheUserKey = null;
    _cachedLimit = null;
  }

  @override
  Future<List<ProductEntity>> getFeed({
    int limit = 20,
    int offset = 0,
    String? currentUserId,
    bool forceRefresh = false,
  }) async {
    final key = _feedCacheKey(currentUserId);
    if (offset == 0 &&
        !forceRefresh &&
        _cachedFirstPage != null &&
        _cachedAt != null &&
        _cacheUserKey == key &&
        _cachedLimit == limit &&
        DateTime.now().difference(_cachedAt!) <= _firstPageTtl) {
      return List<ProductEntity>.from(_cachedFirstPage!);
    }

    var exclude = const <String>{};
    if (currentUserId != null && currentUserId.isNotEmpty) {
      try {
        exclude = await loadAllBlockedUserIds(
          repository: _settingsRepository,
          blockerId: currentUserId,
        );
      } catch (_) {}
    }
    final list = await _productRepository.getFeedProducts(
      limit: limit,
      offset: offset,
      currentUserId: currentUserId,
      excludeSellerIds: exclude,
    );
    if (offset == 0) {
      _cachedFirstPage = List<ProductEntity>.from(list);
      _cachedAt = DateTime.now();
      _cacheUserKey = key;
      _cachedLimit = limit;
    }
    return list;
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
