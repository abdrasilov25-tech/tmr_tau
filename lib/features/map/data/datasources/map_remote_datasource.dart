import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../models/map_product_model.dart';

abstract class MapRemoteDataSource {
  Future<List<MapProductModel>> getNearbyProducts({
    required double latitude,
    required double longitude,
    required double radiusKm,
  });
}

class MapRemoteDataSourceImpl implements MapRemoteDataSource {
  MapRemoteDataSourceImpl(this._client);
  final SupabaseClient _client;

  static const _select =
      'id, title, price, image_url, image_urls, city, seller_id, latitude, longitude, is_urgent, is_top, users!seller_id(name, avatar)';

  @override
  Future<List<MapProductModel>> getNearbyProducts({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) async {
    // Bounding box: 1° latitude ≈ 111 km
    final deltaLat = radiusKm / 111.0;
    final deltaLng =
        radiusKm / (111.0 * math.cos(latitude * math.pi / 180.0));

    final res = await _client
        .from(SupabaseConstants.productsTable)
        .select(_select)
        .not('latitude', 'is', null)
        .not('longitude', 'is', null)
        .gte('latitude', latitude - deltaLat)
        .lte('latitude', latitude + deltaLat)
        .gte('longitude', longitude - deltaLng)
        .lte('longitude', longitude + deltaLng)
        .limit(300);

    final products = (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    final sellerIds = products
        .map((e) => e['seller_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    final ratingBySeller = <String, ({double avg, int count})>{};
    if (sellerIds.isNotEmpty) {
      final reviews = await _client
          .from('business_reviews')
          .select('business_user_id,stars')
          .inFilter('business_user_id', sellerIds);
      for (final row in (reviews as List)) {
        final m = row as Map<String, dynamic>;
        final sellerId = m['business_user_id'] as String?;
        final stars = (m['stars'] as num?)?.toDouble();
        if (sellerId == null || stars == null) continue;
        final prev = ratingBySeller[sellerId];
        if (prev == null) {
          ratingBySeller[sellerId] = (avg: stars, count: 1);
        } else {
          final sum = prev.avg * prev.count + stars;
          final count = prev.count + 1;
          ratingBySeller[sellerId] = (avg: sum / count, count: count);
        }
      }
    }

    return products.map((p) {
      final sellerId = p['seller_id'] as String?;
      final rating = sellerId == null ? null : ratingBySeller[sellerId];
      return MapProductModel.fromJson({
        ...p,
        'seller_rating_avg': rating?.avg ?? 0,
        'seller_rating_count': rating?.count ?? 0,
      });
    }).toList(growable: false);
  }
}
