import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/data/kazakhstan_regions.dart';
import '../../../../core/models/search_filters.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/entities/seller_listing_policy.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/value_objects/product_price_insight.dart';
import '../models/product_model.dart';

class ProductRepositoryImpl implements ProductRepository {
  @override
  Future<SellerListingPolicy> getSellerListingPolicy(String sellerId) async {
    final userRow = await _client
        .from('users')
        .select('seller_plan, official_page_active')
        .eq('id', sellerId)
        .maybeSingle();

    final activeRows = await _client
        .from(SupabaseConstants.productsTable)
        .select('id')
        .eq('seller_id', sellerId);

    final rawPlan = (userRow?['seller_plan'] as String?)?.trim().toLowerCase();
    final officialActive = userRow?['official_page_active'] as bool? ?? false;

    // Backward compatibility: old paid sellers without seller_plan stay on Standard.
    final SellerPlanType plan = switch (rawPlan) {
      'pro' => SellerPlanType.pro,
      'standard' => SellerPlanType.standard,
      'free' => SellerPlanType.free,
      _ => officialActive ? SellerPlanType.standard : SellerPlanType.free,
    };

    final int? maxActiveProducts = switch (plan) {
      SellerPlanType.free => 3,
      SellerPlanType.standard => 20,
      SellerPlanType.pro => null,
    };

    return SellerListingPolicy(
      plan: plan,
      maxActiveProducts: maxActiveProducts,
      activeProducts: (activeRows as List).length,
    );
  }

  @override
  Future<ProductPriceInsight?> getCategoryPriceInsight({
    required String excludeProductId,
    required String categoryId,
    required double subjectPrice,
    required bool isGiveaway,
  }) async {
    if (isGiveaway || subjectPrice <= 0 || categoryId.trim().isEmpty) {
      return null;
    }
    try {
      final res = await _client
          .from(SupabaseConstants.productsTable)
          .select('price,is_giveaway')
          .eq('category_id', categoryId.trim())
          .neq('id', excludeProductId)
          .limit(120);
      final prices = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((m) => m['is_giveaway'] != true)
          .map((m) => (m['price'] as num?)?.toDouble() ?? 0)
          .where((p) => p > 0)
          .toList();
      return ProductPriceInsight.fromComparablePrices(
        subjectPrice: subjectPrice,
        peerPrices: prices,
      );
    } catch (_) {
      return null;
    }
  }

  ProductRepositoryImpl(this._client);
  final SupabaseClient _client;

  static const String _productSelect =
      'id, title, description, price, image_url, image_urls, category, category_id, seller_id, created_at, city, condition, is_urgent, is_top, is_negotiable, is_giveaway, latitude, longitude, contact_phone, promo_top_until, promo_urgent_until, promo_highlight_until, stats_access_until, view_count, users!seller_id(name, avatar, seller_verified_store, is_verified), categories!category_id(name)';

  dynamic _excludeSellerIds(dynamic queryBuilder, Set<String> excludeSellerIds) {
    if (excludeSellerIds.isEmpty) return queryBuilder;
    final inList = excludeSellerIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join(',');
    if (inList.isEmpty) return queryBuilder;
    return queryBuilder.not('seller_id', 'in', '($inList)');
  }

  @override
  Future<List<ProductEntity>> getFeedProducts({
    int limit = 20,
    int offset = 0,
    String? currentUserId,
    Set<String> excludeSellerIds = const {},
  }) async {
    final safeLimit = limit.clamp(1, 100);
    final fetchWindow = math.max(safeLimit * 3, 30);
    final fetchFrom = math.max(offset * 3, 0);
    final fetchTo = fetchFrom + fetchWindow - 1;
    dynamic queryBuilder = _client
        .from(SupabaseConstants.productsTable)
        .select(_productSelect);
    queryBuilder = _excludeSellerIds(queryBuilder, excludeSellerIds);
    final res = await queryBuilder
        .order('created_at', ascending: false)
        .range(fetchFrom, fetchTo);
    final rawList = _mapProducts(res as List);
    final ranked = await _rankFeedProducts(
      source: rawList,
      currentUserId: currentUserId,
      limit: safeLimit,
    );
    return await _enrichWithUserState(ranked, currentUserId);
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
    Set<String> excludeSellerIds = const {},
  }) async {
    return searchProductsWithOffset(
      query,
      limit: limit,
      offset: 0,
      currentUserId: currentUserId,
      filters: filters,
      excludeSellerIds: excludeSellerIds,
    );
  }

  @override
  Future<List<ProductEntity>> searchProductsWithOffset(
    String query, {
    int limit = 20,
    int offset = 0,
    String? currentUserId,
    SearchFilters? filters,
    Set<String> excludeSellerIds = const {},
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
      queryBuilder = _excludeSellerIds(queryBuilder, excludeSellerIds);

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
      final shouldSmartRank = q.isEmpty && (filters?.sort ?? SearchSort.newest) == SearchSort.newest;
      final ranked = shouldSmartRank
          ? await _rankFeedProducts(
              source: sortedList,
              currentUserId: currentUserId,
              limit: safeLimit,
            )
          : sortedList;
      return await _enrichWithUserState(ranked, currentUserId);
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
        .limit(math.max(safeLimit * 3, 30));
    final list = _mapProducts(res as List);
    final ranked = await _rankFeedProducts(
      source: list,
      currentUserId: currentUserId,
      limit: safeLimit,
    );
    return await _enrichWithUserState(ranked, currentUserId);
  }

  @override
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
  }) async {
    final policy = await getSellerListingPolicy(sellerId);
    if (!policy.canCreateProduct) {
      throw Exception(
        'Достигнут лимит объявлений (${policy.activeProducts}/${policy.maxActiveProducts}) '
        'для плана ${policy.planLabel}. Подключите подписку выше.',
      );
    }

    final phoneDb = contactPhone?.trim();
    final urls = imageUrls.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final data = <String, dynamic>{
      'title': title,
      'description': description,
      'price': price,
      'image_url': urls.isNotEmpty ? urls.first : '',
      'image_urls': urls,
      'category': category,
      'seller_id': sellerId,
      'city': city,
      'condition': condition,
      'is_urgent': isUrgent,
      'is_top': isTop,
      'is_negotiable': isNegotiable,
      'is_giveaway': isGiveaway,
      'latitude': latitude,
      'longitude': longitude,
      'contact_phone': (phoneDb == null || phoneDb.isEmpty) ? null : phoneDb,
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
  }) async {
    final phoneDb = contactPhone?.trim();
    final urls = imageUrls.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final data = <String, dynamic>{
      'title': title,
      'description': description,
      'price': price,
      'image_url': urls.isNotEmpty ? urls.first : '',
      'image_urls': urls,
      'category': category,
      // Явно передаём null, чтобы сбросить FK при очистке подкатегории.
      'category_id': categoryId,
      'city': city,
      'condition': condition,
      'is_urgent': isUrgent,
      'is_top': isTop,
      'is_negotiable': isNegotiable,
      'is_giveaway': isGiveaway,
      'latitude': latitude,
      'longitude': longitude,
      'contact_phone': (phoneDb == null || phoneDb.isEmpty) ? null : phoneDb,
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
      await _insertProductNotification(
        productId: productId,
        actorId: userId,
        type: 'product_like',
        title: 'Лайк объявления',
        body: 'Лайкнули ваше объявление',
      );
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
      await _insertProductNotification(
        productId: productId,
        actorId: userId,
        type: 'product_repost',
        title: 'Репост объявления',
        body: 'Поделились вашим объявлением',
      );
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
      await _insertProductNotification(
        productId: productId,
        actorId: userId,
        type: 'product_favorite',
        title: 'Избранное',
        body: 'Добавили объявление в избранное',
      );
    }
  }

  @override
  Future<void> incrementProductView(String productId) async {
    await _client.rpc<void>(
      'increment_product_view',
      params: <String, dynamic>{'p_product_id': productId},
    );
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
      ..['seller_is_verified'] =
          (userMap?['is_verified'] ?? false) ||
          (userMap?['seller_verified_store'] ?? false)
      ..['likes_count'] = json['likes_count'] ?? 0
      ..['comments_count'] = json['comments_count'] ?? 0
      ..['category'] = categoryName ?? 'general'
      ..['category_id'] = json['category_id'];
    return ProductModel.fromJson(row);
  }

  /// Четыре независимых запроса — раньше шли последовательно (до ~4× RTT); параллельно быстрее для поиска и ленты товаров.
  Future<Set<String>> _likedProductIdsForUser(
    String userId,
    List<String> productIds,
  ) async {
    if (productIds.isEmpty) return {};
    try {
      final likes = await _client
          .from(SupabaseConstants.productLikesTable)
          .select('product_id')
          .eq('user_id', userId)
          .inFilter('product_id', productIds);
      return (likes as List)
          .map((e) => (e as Map)['product_id'] as String)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  Future<Set<String>> _followingSellerIdsForUser(
    String userId,
    List<String> sellerIds,
  ) async {
    if (sellerIds.isEmpty) return {};
    try {
      final follows = await _client
          .from(SupabaseConstants.followersTable)
          .select('following_id')
          .eq('follower_id', userId)
          .inFilter('following_id', sellerIds);
      return (follows as List)
          .map((e) => (e as Map)['following_id'] as String)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  Future<Set<String>> _repostedProductIdsForUser(
    String userId,
    List<String> productIds,
  ) async {
    if (productIds.isEmpty) return {};
    try {
      final repostsByMe = await _client
          .from(SupabaseConstants.productRepostsTable)
          .select('product_id')
          .eq('user_id', userId)
          .inFilter('product_id', productIds);
      return (repostsByMe as List)
          .map((e) => (e as Map)['product_id'] as String)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, int>> _repostCountsByProductId(
    List<String> productIds,
  ) async {
    if (productIds.isEmpty) return {};
    try {
      final reposts = await _client
          .from(SupabaseConstants.productRepostsTable)
          .select('product_id')
          .inFilter('product_id', productIds);
      final repostCounts = <String, int>{};
      for (final row in reposts as List) {
        final map = row as Map<String, dynamic>;
        final productId = map['product_id'] as String;
        repostCounts[productId] = (repostCounts[productId] ?? 0) + 1;
      }
      return repostCounts;
    } catch (_) {
      return {};
    }
  }

  Future<List<ProductEntity>> _enrichWithUserState(
    List<ProductEntity> list,
    String? currentUserId,
  ) async {
    if (currentUserId == null || list.isEmpty) return list;
    final ids = list.map((e) => e.id).toList();
    if (ids.isEmpty) return list;
    final sellerIds = list.map((e) => e.sellerId).toSet().toList();

    final results = await Future.wait<Object>([
      _likedProductIdsForUser(currentUserId, ids),
      _followingSellerIdsForUser(currentUserId, sellerIds),
      _repostedProductIdsForUser(currentUserId, ids),
      _repostCountsByProductId(ids),
    ]);

    final likedIds = results[0] as Set<String>;
    final followingIds = results[1] as Set<String>;
    final repostedIds = results[2] as Set<String>;
    final repostCounts = results[3] as Map<String, int>;

    return list
        .map(
          (p) => ProductModel.fromEntity(
            p,
            likesCount: p.likesCount,
            commentsCount: p.commentsCount,
            repostsCount: repostCounts[p.id] ?? p.repostsCount,
            isLikedByMe: likedIds.contains(p.id),
            isRepostedByMe: repostedIds.contains(p.id),
            isFollowingSeller: followingIds.contains(p.sellerId),
          ),
        )
        .toList();
  }

  Future<String?> _productSellerId(String productId) async {
    final row = await _client
        .from(SupabaseConstants.productsTable)
        .select('seller_id')
        .eq('id', productId)
        .maybeSingle();
    if (row == null) return null;
    return row['seller_id'] as String?;
  }

  Future<void> _insertProductNotification({
    required String productId,
    required String actorId,
    required String type,
    required String title,
    required String body,
  }) async {
    final sellerId = await _productSellerId(productId);
    if (sellerId == null || sellerId == actorId) return;
    await _client.from(SupabaseConstants.notificationsTable).insert({
      'user_id': sellerId,
      'actor_id': actorId,
      'type': type,
      'title': title,
      'body': body,
      'product_id': productId,
    });
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

  Future<List<ProductEntity>> _rankFeedProducts({
    required List<ProductEntity> source,
    required String? currentUserId,
    required int limit,
  }) async {
    if (source.length < 2) return source.take(limit).toList(growable: false);
    final now = DateTime.now();
    final sellerAffinity = currentUserId == null
        ? const <String, double>{}
        : await _loadSellerAffinity(
            currentUserId: currentUserId,
            candidateSellerIds: source.map((p) => p.sellerId).toSet(),
          );
    final ranked = List<ProductEntity>.from(source);
    ranked.sort((a, b) {
      final aScore = _scoreProductForFeed(a, now, sellerAffinity[a.sellerId] ?? 0.0);
      final bScore = _scoreProductForFeed(b, now, sellerAffinity[b.sellerId] ?? 0.0);
      return bScore.compareTo(aScore);
    });
    return _applyProductDiversityBySeller(
      products: ranked,
      limit: limit,
    );
  }

  double _scoreProductForFeed(ProductEntity product, DateTime now, double affinity) {
    final createdAt = product.createdAt ?? now;
    final ageHours = now.difference(createdAt).inMinutes / 60.0;
    final freshness = math.exp(-ageHours / 28.0);
    final engagement = math.log(
      1 +
          product.viewCount * 0.08 +
          product.likesCount * 1.2 +
          product.commentsCount * 1.6 +
          product.repostsCount * 2.0,
    );
    final promoBoost = (product.isTop ? 0.08 : 0.0) + (product.isUrgent ? 0.05 : 0.0);
    final mediaBoost = product.imageUrls.isNotEmpty ? 0.05 : 0.0;
    return freshness * 0.52 + engagement * 0.27 + affinity * 0.16 + promoBoost + mediaBoost;
  }

  Future<Map<String, double>> _loadSellerAffinity({
    required String currentUserId,
    required Set<String> candidateSellerIds,
  }) async {
    if (candidateSellerIds.isEmpty) return const <String, double>{};
    final scores = <String, double>{};

    Future<void> addSignal({
      required String table,
      required double weight,
    }) async {
      final rows = await _client
          .from(table)
          .select('product_id')
          .eq('user_id', currentUserId)
          .limit(400);
      final productIds = (rows as List<dynamic>)
          .map((e) => (e as Map<String, dynamic>)['product_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList(growable: false);
      if (productIds.isEmpty) return;
      for (var i = 0; i < productIds.length; i += 120) {
        final end = math.min(i + 120, productIds.length);
        final chunk = productIds.sublist(i, end);
        final productRows = await _client
            .from(SupabaseConstants.productsTable)
            .select('id,seller_id')
            .inFilter('id', chunk);
        for (final row in (productRows as List<dynamic>)) {
          final sellerId = ((row as Map<String, dynamic>)['seller_id'] ?? '').toString();
          if (sellerId.isEmpty || !candidateSellerIds.contains(sellerId)) continue;
          scores[sellerId] = (scores[sellerId] ?? 0) + weight;
        }
      }
    }

    await addSignal(table: SupabaseConstants.productLikesTable, weight: 1.0);
    await addSignal(table: SupabaseConstants.productRepostsTable, weight: 1.8);
    await addSignal(table: SupabaseConstants.favoritesTable, weight: 1.5);

    if (scores.isEmpty) return scores;
    final maxScore = scores.values.reduce(math.max);
    if (maxScore <= 0) return scores;
    for (final key in scores.keys.toList(growable: false)) {
      scores[key] = scores[key]! / maxScore;
    }
    return scores;
  }

  List<ProductEntity> _applyProductDiversityBySeller({
    required List<ProductEntity> products,
    required int limit,
  }) {
    if (products.isEmpty || limit <= 0) return const [];
    final cappedLimit = math.min(limit, products.length);
    final bySeller = <String, List<ProductEntity>>{};
    for (final product in products) {
      bySeller.putIfAbsent(product.sellerId, () => <ProductEntity>[]).add(product);
    }
    final out = <ProductEntity>[];
    String? lastSeller;
    while (out.length < cappedLimit) {
      ProductEntity? picked;
      String? pickedSeller;
      for (final entry in bySeller.entries) {
        if (entry.value.isEmpty) continue;
        if (entry.key == lastSeller) continue;
        picked = entry.value.removeAt(0);
        pickedSeller = entry.key;
        break;
      }
      picked ??= () {
        for (final entry in bySeller.entries) {
          if (entry.value.isEmpty) continue;
          pickedSeller = entry.key;
          return entry.value.removeAt(0);
        }
        return null;
      }();
      if (picked == null) break;
      out.add(picked);
      lastSeller = pickedSeller;
    }
    return out;
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
