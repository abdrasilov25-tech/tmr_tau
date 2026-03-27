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
      'id, title, price, image_url, image_urls, city, seller_id, latitude, longitude, users!seller_id(name, avatar)';

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

    return (res as List)
        .map((e) => MapProductModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
