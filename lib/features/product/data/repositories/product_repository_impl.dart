import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/product_repository.dart';
import '../models/product_model.dart';

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<List<ProductEntity>> getFeedProducts({
    int limit = 20,
    int offset = 0,
    String? currentUserId,
  }) async {
    final res = await _client
        .from(SupabaseConstants.productsTable)
        .select('id, title, description, price, image_url, seller_id, category, created_at, users!seller_id(name, avatar)')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    final list = _mapProducts(res as List);
    return await _enrichWithUserState(list, currentUserId);
  }

  @override
  Future<ProductEntity?> getProductById(String id,
      {String? currentUserId}) async {
    final res = await _client
        .from(SupabaseConstants.productsTable)
        .select('id, title, description, price, image_url, seller_id, category, created_at, users!seller_id(name, avatar)')
        .eq('id', id)
        .maybeSingle();
    if (res == null) return null;
    final list = _mapProducts([res]);
    final enriched = await _enrichWithUserState(list, currentUserId);
    return enriched.isNotEmpty ? enriched.first : null;
  }

  @override
  Future<List<ProductEntity>> getProductsBySellerId(String sellerId,
      {String? currentUserId}) async {
    final res = await _client
        .from(SupabaseConstants.productsTable)
        .select('id, title, description, price, image_url, seller_id, category, created_at, users!seller_id(name, avatar)')
        .eq('seller_id', sellerId)
        .order('created_at', ascending: false);
    final list = _mapProducts(res as List);
    return await _enrichWithUserState(list, currentUserId);
  }

  @override
  Future<List<ProductEntity>> searchProducts(String query,
      {int limit = 20, String? currentUserId}) async {
    if (query.trim().isEmpty) {
      return getFeedProducts(limit: limit, currentUserId: currentUserId);
    }
    final res = await _client
        .from(SupabaseConstants.productsTable)
        .select('id, title, description, price, image_url, seller_id, category, created_at, users!seller_id(name, avatar)')
        .or('title.ilike.%$query%,description.ilike.%$query%')
        .order('created_at', ascending: false)
        .limit(limit);
    final list = _mapProducts(res as List);
    return await _enrichWithUserState(list, currentUserId);
  }

  @override
  Future<List<ProductEntity>> getTrendingProducts({
    int limit = 10,
    String? currentUserId,
  }) async {
    final res = await _client
        .from(SupabaseConstants.productsTable)
        .select('id, title, description, price, image_url, seller_id, category, created_at, users!seller_id(name, avatar)')
        .order('created_at', ascending: false)
        .limit(limit);
    final list = _mapProducts(res as List);
    return await _enrichWithUserState(list, currentUserId);
  }

  @override
  Future<void> addProduct({
    required String title,
    required String description,
    required double price,
    String imageUrl = '',
    String category = 'general',
    required String sellerId,
  }) async {
    await _client.from(SupabaseConstants.productsTable).insert({
      'title': title,
      'description': description,
      'price': price,
      'image_url': imageUrl,
      'category': category,
      'seller_id': sellerId,
    });
  }

  @override
  Future<void> toggleProductLike(String productId, String userId) async {
    final existing = await _client
        .from(SupabaseConstants.productLikesTable)
        .select('product_id')
        .eq('product_id', productId)
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) {
      await _client
          .from(SupabaseConstants.productLikesTable)
          .delete()
          .eq('product_id', productId)
          .eq('user_id', userId);
    } else {
      await _client.from(SupabaseConstants.productLikesTable).insert({
        'product_id': productId,
        'user_id': userId,
      });
    }
  }

  List<ProductEntity> _mapProducts(List<dynamic> list) {
    return list.map((e) => _mapProduct(e as Map<String, dynamic>)).toList();
  }

  ProductEntity _mapProduct(Map<String, dynamic> json) {
    final users = json['users'];
    Map<String, dynamic>? userMap;
    if (users is Map) {
      userMap = Map<String, dynamic>.from(users);
    }
    final row = Map<String, dynamic>.from(json)
      ..remove('users')
      ..['seller_name'] = userMap?['name']
      ..['seller_avatar'] = userMap?['avatar']
      ..['seller_is_verified'] = userMap?['is_verified'] ?? false
      ..['likes_count'] = json['likes_count'] ?? 0
      ..['comments_count'] = json['comments_count'] ?? 0;
    return ProductModel.fromJson(row);
  }

  Future<List<ProductEntity>> _enrichWithUserState(
    List<ProductEntity> list,
    String? currentUserId,
  ) async {
    if (currentUserId == null || list.isEmpty) return list;
    final ids = list.map((e) => e.id).toList();
    final sellerIds = list.map((e) => e.sellerId).toSet().toList();
    final likes = await _client
        .from(SupabaseConstants.productLikesTable)
        .select('product_id')
        .eq('user_id', currentUserId)
        .inFilter('product_id', ids);
    final follows = await _client
        .from(SupabaseConstants.followersTable)
        .select('following_id')
        .eq('follower_id', currentUserId)
        .inFilter('following_id', sellerIds);
    final likedIds =
        (likes as List).map((e) => (e as Map)['product_id'] as String).toSet();
    final followingIds =
        (follows as List).map((e) => (e as Map)['following_id'] as String).toSet();
    return list
        .map((p) => ProductModel(
              id: p.id,
              title: p.title,
              description: p.description,
              price: p.price,
              imageUrl: p.imageUrl,
              sellerId: p.sellerId,
              category: p.category,
              likesCount: p.likesCount,
              commentsCount: p.commentsCount,
              sellerName: p.sellerName,
              sellerAvatarUrl: p.sellerAvatarUrl,
              createdAt: p.createdAt,
              isLikedByMe: likedIds.contains(p.id),
              isFollowingSeller: followingIds.contains(p.sellerId),
              sellerIsVerified: p.sellerIsVerified,
            ))
        .toList();
  }
}
