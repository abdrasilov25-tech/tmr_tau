import '../../domain/entities/map_product.dart';
import '../../domain/repositories/map_repository.dart';
import '../datasources/map_remote_datasource.dart';

class MapRepositoryImpl implements MapRepository {
  MapRepositoryImpl(this._dataSource);
  final MapRemoteDataSource _dataSource;

  @override
  Future<List<MapProduct>> getNearbyProducts({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) =>
      _dataSource.getNearbyProducts(
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
      );
}
