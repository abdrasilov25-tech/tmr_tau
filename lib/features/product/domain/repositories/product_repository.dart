import '../entities/product_entity.dart';
import '../../../../core/models/search_filters.dart';

abstract class ProductRepository {
  Future<List<ProductEntity>> getFeedProducts({
    int limit = 20,
    int offset = 0,
    String? currentUserId,
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
  });
  Future<List<ProductEntity>> searchProductsWithOffset(
    String query, {
    int limit = 20,
    int offset = 0,
    String? currentUserId,
    SearchFilters? filters,
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
    double? latitude,
    double? longitude,
    String? contactPhone,
  });
  Future<void> deleteProduct(String productId);
  Future<void> toggleProductLike(String productId, String userId);
  Future<void> toggleProductRepost(String productId, String userId);
  Future<List<ProductEntity>> getFavorites(String userId);
  Future<void> toggleFavorite(String productId, String userId);
}
