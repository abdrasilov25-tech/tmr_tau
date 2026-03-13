import '../entities/product_entity.dart';

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
  Future<List<ProductEntity>> searchProducts(String query,
      {int limit = 20, String? currentUserId});
  Future<List<ProductEntity>> getTrendingProducts({
    int limit = 10,
    String? currentUserId,
  });
  Future<void> addProduct({
    required String title,
    required String description,
    required double price,
    String imageUrl = '',
    String category = 'general',
    String? categoryId,
    required String sellerId,
  });
  Future<void> updateProduct({
    required String productId,
    required String title,
    required String description,
    required double price,
    required String imageUrl,
    String category = 'general',
    String? categoryId,
  });
  Future<void> deleteProduct(String productId);
  Future<void> toggleProductLike(String productId, String userId);
  Future<void> toggleProductRepost(String productId, String userId);
}
