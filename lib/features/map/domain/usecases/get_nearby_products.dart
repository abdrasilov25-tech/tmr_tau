import '../entities/map_product.dart';
import '../repositories/map_repository.dart';

class GetNearbyProducts {
  const GetNearbyProducts(this._repository);
  final MapRepository _repository;

  Future<List<MapProduct>> call({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) =>
      _repository.getNearbyProducts(
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
      );
}
