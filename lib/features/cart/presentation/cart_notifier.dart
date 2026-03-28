import 'package:flutter/foundation.dart';
import '../domain/entities/cart_item_entity.dart';
import '../../product/domain/entities/product_entity.dart';

class CartNotifier extends ChangeNotifier {
  final List<CartItemEntity> _items = [];

  List<CartItemEntity> get items => List.unmodifiable(_items);

  int get itemCount => _items.fold(0, (sum, e) => sum + e.quantity);

  double get total => _items.fold(0, (sum, e) => sum + e.total);

  void addItem(ProductEntity product) {
    final index = _items.indexWhere((e) => e.product.id == product.id);
    if (index >= 0) {
      _items[index] = CartItemEntity(
        product: product,
        quantity: _items[index].quantity + 1,
      );
    } else {
      _items.add(CartItemEntity(product: product));
    }
    notifyListeners();
  }

  void removeItem(String productId) {
    _items.removeWhere((e) => e.product.id == productId);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
