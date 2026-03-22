import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/data/kazakhstan_regions.dart';
import '../../../../core/models/search_filters.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/product_repository.dart';
import '../models/product_model.dart';

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl(this._client);
  final SupabaseClient _client;
  static const String _productSelect =
      'id, title, description, price, image_url, category, category_id, seller_id, created_at, city, condition, is_urgent, is_top, latitude, longitude, users!seller_id(name, avatar), categories!category_id(name)';

  @override
  Future<List<ProductEntity>> getFeedProducts({
    int limit = 20,
    int offset = 0,
    String? currentUserId,
  }) async {
    final safeLimit = limit.clamp(1, 100);
    final res = await _client
        .from(SupabaseConstants.productsTable)
        .select(_productSelect)
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
        .select(_productSelect)
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
        .select(_productSelect)
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
    return searchProductsWithOffset(
      query,
      limit: limit,
      offset: 0,
      currentUserId: currentUserId,
      filters: filters,
    );
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

    final safeLimit = limit.clamp(1, 100);
    final safeOffset = offset < 0 ? 0 : offset;

    // Экранируем одинарную кавычку, чтобы не сломать фильтр Postgrest.
    final safe = q.replaceAll(r"'", r"''");
    try {
      dynamic queryBuilder = _client
          .from(SupabaseConstants.productsTable)
          .select(_productSelect);

      if (q.isNotEmpty) {
        queryBuilder = queryBuilder.or(
          'title.ilike.%$safe%,description.ilike.%$safe%',
        );
      }
      if (filters?.categoryId != null && filters!.categoryId!.isNotEmpty) {
        queryBuilder = queryBuilder.eq('category_id', filters.categoryId);
      }
      if (filters?.minPrice != null) {
        queryBuilder = queryBuilder.gte('price', filters!.minPrice);
      }
      if (filters?.maxPrice != null) {
        queryBuilder = queryBuilder.lte('price', filters!.maxPrice);
      }
      final hasKz = filters?.kzRegionId != null &&
          filters!.kzRegionId!.trim().isNotEmpty;
      if (hasKz) {
        final region = KazakhstanRegions.byId(filters.kzRegionId);
        if (region != null) {
          final loc = filters.kzLocalityName?.trim();
          if (loc != null && loc.isNotEmpty) {
            final t = loc.replaceAll(r"'", r"''");
            queryBuilder = queryBuilder.ilike('city', '%$t%');
          } else {
            final orParts = region.settlements
                .map((s) {
                  final e = s.replaceAll(r"'", r"''");
                  return 'city.ilike.%$e%';
                })
                .join(',');
            if (orParts.isNotEmpty) {
              queryBuilder = queryBuilder.or(orParts);
            }
          }
        }
      } else if (filters?.city != null && filters!.city!.trim().isNotEmpty) {
        final city = filters.city!.trim().replaceAll(r"'", r"''");
        queryBuilder = queryBuilder.ilike('city', '%$city%');
      }
      if (filters?.condition == ProductCondition.newOnly) {
        queryBuilder = queryBuilder.eq('condition', 'new');
      } else if (filters?.condition == ProductCondition.used) {
        queryBuilder = queryBuilder.eq('condition', 'used');
      }
      final nearbyRadiusKm = filters?.radiusKm;
      final nearbyCenterLat = filters?.centerLatitude;
      final nearbyCenterLng = filters?.centerLongitude;
      final hasNearbyFilter =
          nearbyRadiusKm != null &&
          nearbyCenterLat != null &&
          nearbyCenterLng != null;
      if (hasNearbyFilter) {
        final radiusKm = nearbyRadiusKm;
        final lat = nearbyCenterLat;
        final lng = nearbyCenterLng;
        final latDelta = radiusKm / 111.0;
        final lngDelta = radiusKm / _kmPerLongitudeDegree(lat);
        queryBuilder = queryBuilder
            .not('latitude', 'is', null)
            .not('longitude', 'is', null)
            .gte('latitude', lat - latDelta)
            .lte('latitude', lat + latDelta)
            .gte('longitude', lng - lngDelta)
            .lte('longitude', lng + lngDelta);
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
      final filteredList = hasNearbyFilter
          ? _filterByRadius(
              list,
              radiusKm: nearbyRadiusKm,
              centerLatitude: nearbyCenterLat,
              centerLongitude: nearbyCenterLng,
            )
          : list;
      final sortedList = hasNearbyFilter
          ? _sortByDistance(
              filteredList,
              centerLatitude: nearbyCenterLat,
              centerLongitude: nearbyCenterLng,
            )
          : filteredList;
      return await _enrichWithUserState(sortedList, currentUserId);
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
        .select(_productSelect)
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
    String? city,
    String condition = 'any',
    bool isUrgent = false,
    bool isTop = false,
    double? latitude,
    double? longitude,
    required String sellerId,
  }) async {
    final data = <String, dynamic>{
      'title': title,
      'description': description,
      'price': price,
      'image_url': imageUrl,
      'category': category,
      'seller_id': sellerId,
      'city': city,
      'condition': condition,
      'is_urgent': isUrgent,
      'is_top': isTop,
      'latitude': latitude,
      'longitude': longitude,
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
    String? city,
    String condition = 'any',
    bool isUrgent = false,
    bool isTop = false,
    double? latitude,
    double? longitude,
  }) async {
    final data = <String, dynamic>{
      'title': title,
      'description': description,
      'price': price,
      'image_url': imageUrl,
      'category': category,
      // Явно передаём null, чтобы сбросить FK при очистке подкатегории.
      'category_id': categoryId,
      'city': city,
      'condition': condition,
      'is_urgent': isUrgent,
      'is_top': isTop,
      'latitude': latitude,
      'longitude': longitude,
    };
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
        .select(_productSelect)
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
            city: p.city,
            condition: p.condition,
            isUrgent: p.isUrgent,
            isTop: p.isTop,
            latitude: p.latitude,
            longitude: p.longitude,
          ),
        )
        .toList();
  }

  double _kmPerLongitudeDegree(double latitude) {
    final value = 111.320 * math.cos(latitude * math.pi / 180);
    return value.abs() < 0.0001 ? 0.0001 : value.abs();
  }

  List<ProductEntity> _filterByRadius(
    List<ProductEntity> source, {
    required double radiusKm,
    required double centerLatitude,
    required double centerLongitude,
  }) {
    return source.where((product) {
      final lat = product.latitude;
      final lng = product.longitude;
      if (lat == null || lng == null) return false;
      return _distanceKm(centerLatitude, centerLongitude, lat, lng) <= radiusKm;
    }).toList(growable: false);
  }

  List<ProductEntity> _sortByDistance(
    List<ProductEntity> source, {
    required double centerLatitude,
    required double centerLongitude,
  }) {
    final sorted = List<ProductEntity>.from(source);
    sorted.sort((a, b) {
      final aLat = a.latitude;
      final aLng = a.longitude;
      final bLat = b.latitude;
      final bLng = b.longitude;
      if (aLat == null || aLng == null) return 1;
      if (bLat == null || bLng == null) return -1;
      final da = _distanceKm(centerLatitude, centerLongitude, aLat, aLng);
      final db = _distanceKm(centerLatitude, centerLongitude, bLat, bLng);
      return da.compareTo(db);
    });
    return sorted;
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) => degrees * math.pi / 180;
}
