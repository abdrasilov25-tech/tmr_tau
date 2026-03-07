import 'package:flutter_test/flutter_test.dart';
import 'package:tmr_tau/features/product/domain/entities/product_entity.dart';

void main() {
  group('ProductEntity', () {
    test('priceFormatted возвращает цену с символом ₸', () {
      const product = ProductEntity(
        id: '1',
        title: 'Товар',
        description: '',
        price: 15000,
        imageUrl: '',
        sellerId: 's1',
      );
      expect(product.priceFormatted, '15000 ₸');
    });

    test('priceFormatted округляет дробную часть', () {
      const product = ProductEntity(
        id: '2',
        title: 'Товар',
        description: '',
        price: 9999.99,
        imageUrl: '',
        sellerId: 's1',
      );
      expect(product.priceFormatted, '10000 ₸');
    });
  });
}
