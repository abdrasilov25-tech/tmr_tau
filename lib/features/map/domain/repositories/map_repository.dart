import '../entities/map_product.dart';

abstract class MapRepository {
  Future<List<MapProduct>> getNearbyProducts({
    required double latitude,
    required double longitude,
    required double radiusKm,
  });
}
