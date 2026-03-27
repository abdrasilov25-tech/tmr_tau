import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tmr_tau/features/map/domain/entities/map_product.dart';
import 'package:tmr_tau/features/map/domain/repositories/map_repository.dart';
import 'package:tmr_tau/features/map/domain/usecases/get_nearby_products.dart';

class _MockMapRepository extends Mock implements MapRepository {}

void main() {
  test('GetNearbyProducts пробрасывает координаты и радиус в репозиторий', () async {
    final repo = _MockMapRepository();
    final useCase = GetNearbyProducts(repo);
    final sample = [
      MapProduct(
        id: '1',
        title: 't',
        price: 1,
        latitude: 1,
        longitude: 2,
      ),
    ];
    when(
      () => repo.getNearbyProducts(
        latitude: 51.1,
        longitude: 71.4,
        radiusKm: 10,
      ),
    ).thenAnswer((_) async => sample);

    final out = await useCase(
      latitude: 51.1,
      longitude: 71.4,
      radiusKm: 10,
    );

    expect(out, sample);
    verify(
      () => repo.getNearbyProducts(
        latitude: 51.1,
        longitude: 71.4,
        radiusKm: 10,
      ),
    ).called(1);
  });
}
