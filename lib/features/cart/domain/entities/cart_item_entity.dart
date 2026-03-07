import 'package:equatable/equatable.dart';
import '../../../product/domain/entities/product_entity.dart';

class CartItemEntity extends Equatable {
  const CartItemEntity({
    required this.product,
    this.quantity = 1,
  });

  final ProductEntity product;
  final int quantity;

  double get total => product.price * quantity;

  @override
  List<Object?> get props => [product, quantity];
}
