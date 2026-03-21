import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/models/search_filters.dart';
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
    final safeLimit = limit.clamp(1, 100);
    final res = await _client
        .from(SupabaseConstants.productsTable)
        .select(
          'id, title, description, price, image_url, category, category_id, seller_id, created_at, users!seller_id(name, avatar), categories!category_id(name)',
        )
        .order('created_at', ascending: false)
        .range(offset, offset + safeLimit - 1);
    final list = _mapProducts(res as List);
    return await _enrichWithUserState(list, currentUserId);
  }

  @override
  Future<ProductEntity?> getProductById(
    String id, {
    String? currentUserId,
  }) async {
    final res = await _client
        .from(SupabaseConstants.productsTable)
        .select(
          'id, title, description, price, image_url, category, category_id, seller_id, created_at, users!seller_id(name, avatar), categories!category_id(name)',
        )
        .eq('id', id)
        .maybeSingle();
    if (res == null) return null;
    final list = _mapProducts([res]);
    final enriched = await _enrichWithUserState(list, currentUserId);
    return enriched.isNotEmpty ? enriched.first : null;
  }

  @override
  Future<List<ProductEntity>> getProductsBySellerId(
    String sellerId, {
    String? currentUserId,
  }) async {
    final res = await _client
        .from(SupabaseConstants.productsTable)
        .select(
          'id, title, description, price, image_url, category, category_id, seller_id, created_at, users!seller_id(name, avatar), categories!category_id(name)',
        )
        .eq('seller_id', sellerId)
        .order('created_at', ascending: false);
    final list = _mapProducts(res as List);
    return await _enrichWithUserState(list, currentUserId);
  }

  @override
  Future<List<ProductEntity>> searchProducts(
    String query, {
    int limit = 20,
    String? currentUserId,
    SearchFilters? filters,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return getFeedProducts(limit: limit, currentUserId: currentUserId);
    }
    // Экранируем одинарную кавычку, чтобы не сломать фильтр Postgrest
    final safe = q.replaceAll(r"'", r"''");
    try {
      final res = await _client
          .from(SupabaseConstants.productsTable)
          .select(
            'id, title, description, price, image_url, category, category_id, seller_id, created_at, users!seller_id(name, avatar), categories!category_id(name)',
          )
          .or('title.ilike.%$safe%,description.ilike.%$safe%')
          .gte('price', filters?.minPrice ?? 0)
          .order('created_at', ascending: false)
          .limit(limit);
      final list = _mapProducts(res as List);
      return await _enrichWithUserState(list, currentUserId);
    } catch (_) {
      // При ошибке (например неверный символ) возвращаем ленту как "похожие"
      return getFeedProducts(limit: limit, currentUserId: currentUserId);
    }
  }

  @override
  Future<List<ProductEntity>> searchProductsWithOffset(
    String query, {
    int limit = 20,
    int offset = 0,
    String? currentUserId,
    SearchFilters? filters,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return getFeedProducts(
        limit: limit,
        offset: offset,
        currentUserId: currentUserId,
      );
    }

    final safeLimit = limit.clamp(1, 100);
    final safeOffset = offset < 0 ? 0 : offset;

    // Экранируем одинарную кавычку, чтобы не сломать фильтр Postgrest.
    final safe = q.replaceAll(r"'", r"''");
    try {
      dynamic queryBuilder = _client
          .from(SupabaseConstants.productsTable)
          .select(
            'id, title, description, price, image_url, category, category_id, seller_id, created_at, users!seller_id(name, avatar), categories!category_id(name)',
          );

      queryBuilder = queryBuilder.or(
        'title.ilike.%$safe%,description.ilike.%$safe%',
      );
      if (filters?.categoryId != null && filters!.categoryId!.isNotEmpty) {
        queryBuilder = queryBuilder.eq('category_id', filters.categoryId);
      }
      if (filters?.minPrice != null) {
        queryBuilder = queryBuilder.gte('price', filters!.minPrice);
      }
      if (filters?.maxPrice != null) {
        queryBuilder = queryBuilder.lte('price', filters!.maxPrice);
      }
      if (filters?.city != null && filters!.city!.trim().isNotEmpty) {
        final city = filters.city!.trim().replaceAll(r"'", r"''");
        queryBuilder = queryBuilder.or(
          'title.ilike.%$safe%,description.ilike.%$safe%,title.ilike.%$city%,description.ilike.%$city%',
        );
      }
      if (filters?.condition == ProductCondition.newOnly) {
        queryBuilder = queryBuilder.or(
          'title.ilike.%нов%,description.ilike.%нов%',
        );
      } else if (filters?.condition == ProductCondition.used) {
        queryBuilder = queryBuilder.or(
          'title.ilike.%б/у%,description.ilike.%б/у%,title.ilike.%бу%,description.ilike.%бу%,title.ilike.%used%,description.ilike.%used%',
        );
      }
      switch (filters?.sort ?? SearchSort.newest) {
        case SearchSort.newest:
          queryBuilder = queryBuilder.order('created_at', ascending: false);
          break;
        case SearchSort.priceAsc:
          queryBuilder = queryBuilder.order('price', ascending: true);
          break;
        case SearchSort.priceDesc:
          queryBuilder = queryBuilder.order('price', ascending: false);
          break;
      }
      final res = await queryBuilder.range(
        safeOffset,
        safeOffset + safeLimit - 1,
      );

      final list = _mapProducts(res as List);
      return await _enrichWithUserState(list, currentUserId);
    } catch (_) {
      // При ошибке возвращаем ленту как "похожие".
      return getFeedProducts(
        limit: safeLimit,
        offset: safeOffset,
        currentUserId: currentUserId,
      );
    }
  }

  @override
  Future<List<ProductEntity>> getTrendingProducts({
    int limit = 10,
    String? currentUserId,
  }) async {
    final safeLimit = limit.clamp(1, 100);
    final res = await _client
        .from(SupabaseConstants.productsTable)
        .select(
          'id, title, description, price, image_url, category, category_id, seller_id, created_at, users!seller_id(name, avatar), categories!category_id(name)',
        )
        .order('created_at', ascending: false)
        .limit(safeLimit);
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
    String? categoryId,
    required String sellerId,
  }) async {
    final data = <String, dynamic>{
      'title': title,
      'description': description,
      'price': price,
      'image_url': imageUrl,
      'category': category,
      'seller_id': sellerId,
    };
    if (categoryId != null) data['category_id'] = categoryId;
    await _client.from(SupabaseConstants.productsTable).insert(data);
  }

  @override
  Future<void> updateProduct({
    required String productId,
    required String title,
    required String description,
    required double price,
    required String imageUrl,
    String category = 'general',
    String? categoryId,
  }) async {
    final data = <String, dynamic>{
      'title': title,
      'description': description,
      'price': price,
      'image_url': imageUrl,
      'category': category,
    };
    if (categoryId != null) data['category_id'] = categoryId;
    await _client
        .from(SupabaseConstants.productsTable)
        .update(data)
        .eq('id', productId);
  }

  @override
  Future<void> deleteProduct(String productId) async {
    await _client
        .from(SupabaseConstants.productsTable)
        .delete()
        .eq('id', productId);
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

  @override
  Future<void> toggleProductRepost(String productId, String userId) async {
    final existing = await _client
        .from(SupabaseConstants.productRepostsTable)
        .select('product_id')
        .eq('product_id', productId)
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) {
      await _client
          .from(SupabaseConstants.productRepostsTable)
          .delete()
          .eq('product_id', productId)
          .eq('user_id', userId);
    } else {
      await _client.from(SupabaseConstants.productRepostsTable).insert({
        'product_id': productId,
        'user_id': userId,
      });
    }
  }

  @override
  Future<List<ProductEntity>> getFavorites(String userId) async {
    final favRes = await _client
        .from(SupabaseConstants.favoritesTable)
        .select('product_id')
        .eq('user_id', userId);
    final ids = (favRes as List)
        .map((e) => (e as Map<String, dynamic>)['product_id'] as String)
        .toList();
    if (ids.isEmpty) return [];
    final res = await _client
        .from(SupabaseConstants.productsTable)
        .select(
          'id, title, description, price, image_url, category, category_id, seller_id, created_at, users!seller_id(name, avatar), categories!category_id(name)',
        )
        .inFilter('id', ids)
        .order('created_at', ascending: false);
    final list = _mapProducts(res as List);
    return await _enrichWithUserState(list, userId);
  }

  @override
  Future<void> toggleFavorite(String productId, String userId) async {
    final existing = await _client
        .from(SupabaseConstants.favoritesTable)
        .select('product_id')
        .eq('product_id', productId)
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) {
      await _client
          .from(SupabaseConstants.favoritesTable)
          .delete()
          .eq('product_id', productId)
          .eq('user_id', userId);
    } else {
      await _client.from(SupabaseConstants.favoritesTable).insert({
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
    final categories = json['categories'];
    final categoryName =
        json['category'] ?? (categories is Map ? categories['name'] : null);
    final row = Map<String, dynamic>.from(json)
      ..remove('users')
      ..remove('categories')
      ..['seller_name'] = userMap?['name']
      ..['seller_avatar'] = userMap?['avatar']
      ..['seller_is_verified'] = userMap?['is_verified'] ?? false
      ..['likes_count'] = json['likes_count'] ?? 0
      ..['comments_count'] = json['comments_count'] ?? 0
      ..['category'] = categoryName ?? 'general'
      ..['category_id'] = json['category_id'];
    return ProductModel.fromJson(row);
  }

  Future<List<ProductEntity>> _enrichWithUserState(
    List<ProductEntity> list,
    String? currentUserId,
  ) async {
    if (currentUserId == null || list.isEmpty) return list;
    final ids = list.map((e) => e.id).toList();
    if (ids.isEmpty) return list;
    final sellerIds = list.map((e) => e.sellerId).toSet().toList();
    Set<String> likedIds = {};
    Set<String> followingIds = {};
    Set<String> repostedIds = {};
    final Map<String, int> repostCounts = {};
    try {
      final likes = await _client
          .from(SupabaseConstants.productLikesTable)
          .select('product_id')
          .eq('user_id', currentUserId)
          .inFilter('product_id', ids);
      likedIds = (likes as List)
          .map((e) => (e as Map)['product_id'] as String)
          .toSet();
    } catch (_) {}
    try {
      final follows = await _client
          .from(SupabaseConstants.followersTable)
          .select('following_id')
          .eq('follower_id', currentUserId)
          .inFilter('following_id', sellerIds);
      followingIds = (follows as List)
          .map((e) => (e as Map)['following_id'] as String)
          .toSet();
    } catch (_) {}
    try {
      final repostsByMe = await _client
          .from(SupabaseConstants.productRepostsTable)
          .select('product_id')
          .eq('user_id', currentUserId)
          .inFilter('product_id', ids);
      repostedIds = (repostsByMe as List)
          .map((e) => (e as Map)['product_id'] as String)
          .toSet();
    } catch (_) {}
    try {
      final reposts = await _client
          .from(SupabaseConstants.productRepostsTable)
          .select('product_id')
          .inFilter('product_id', ids);
      for (final row in reposts as List) {
        final map = row as Map<String, dynamic>;
        final productId = map['product_id'] as String;
        repostCounts[productId] = (repostCounts[productId] ?? 0) + 1;
      }
    } catch (_) {}
    return list
        .map(
          (p) => ProductModel(
            id: p.id,
            title: p.title,
            description: p.description,
            price: p.price,
            imageUrl: p.imageUrl,
            sellerId: p.sellerId,
            category: p.category,
            categoryId: p.categoryId,
            likesCount: p.likesCount,
            commentsCount: p.commentsCount,
            repostsCount: repostCounts[p.id] ?? 0,
            sellerName: p.sellerName,
            sellerAvatarUrl: p.sellerAvatarUrl,
            createdAt: p.createdAt,
            isLikedByMe: likedIds.contains(p.id),
            isRepostedByMe: repostedIds.contains(p.id),
            isFollowingSeller: followingIds.contains(p.sellerId),
            sellerIsVerified: p.sellerIsVerified,
          ),
        )
        .toList();
  }
}
