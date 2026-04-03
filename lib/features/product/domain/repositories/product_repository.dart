import '../entities/product_entity.dart';
import '../entities/seller_listing_policy.dart';
import '../value_objects/product_price_insight.dart';
import '../../../../core/models/search_filters.dart';

abstract class ProductRepository {
  Future<List<ProductEntity>> getFeedProducts({
    int limit = 20,
    int offset = 0,
    String? currentUserId,
    Set<String> excludeSellerIds = const {},
  });
  Future<ProductEntity?> getProductById(String id, {String? currentUserId});
  Future<List<ProductEntity>> getProductsBySellerId(
    String sellerId, {
    String? currentUserId,
  });
  Future<List<ProductEntity>> searchProducts(
    String query, {
    int limit = 20,
    String? currentUserId,
    SearchFilters? filters,
    Set<String> excludeSellerIds = const {},
  });
  Future<List<ProductEntity>> searchProductsWithOffset(
    String query, {
    int limit = 20,
    int offset = 0,
    String? currentUserId,
    SearchFilters? filters,
    Set<String> excludeSellerIds = const {},
  });
  Future<List<ProductEntity>> getTrendingProducts({
    int limit = 10,
    String? currentUserId,
  });
  Future<void> addProduct({
    required String title,
    required String description,
    required double price,
    List<String> imageUrls = const [],
    String category = 'general',
    String? categoryId,
    String? city,
    String condition = 'any',
    bool isUrgent = false,
    bool isTop = false,
    bool isNegotiable = false,
    bool isGiveaway = false,
    double? latitude,
    double? longitude,
    String? contactPhone,
    required String sellerId,
  });
  Future<void> updateProduct({
    required String productId,
    required String title,
    required String description,
    required double price,
    required List<String> imageUrls,
    String category = 'general',
    String? categoryId,
    String? city,
    String condition = 'any',
    bool isUrgent = false,
    bool isTop = false,
    bool isNegotiable = false,
    bool isGiveaway = false,
    double? latitude,
    double? longitude,
    String? contactPhone,
  });
  Future<void> deleteProduct(String productId);
  Future<void> toggleProductLike(String productId, String userId);
  Future<void> toggleProductRepost(String productId, String userId);
  Future<List<ProductEntity>> getFavorites(String userId);
  Future<void> toggleFavorite(String productId, String userId);

  /// Счётчик просмотров (RPC `increment_product_view` в Supabase).
  Future<void> incrementProductView(String productId);

  /// Политика лимитов продавца на активные объявления.
  Future<SellerListingPolicy> getSellerListingPolicy(String sellerId);

  /// Подсказка по цене относительно других товаров в той же категории (лёгкий select).
  Future<ProductPriceInsight?> getCategoryPriceInsight({
    required String excludeProductId,
    required String categoryId,
    required double subjectPrice,
    required bool isGiveaway,
  });
}
