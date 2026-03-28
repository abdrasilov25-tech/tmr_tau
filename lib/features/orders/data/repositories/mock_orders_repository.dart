import '../../domain/entities/order_entity.dart';
import '../../domain/repositories/orders_repository.dart';

class MockOrdersRepository implements OrdersRepository {
  static final List<OrderEntity> _mockOrders = [
    OrderEntity(
      id: 'order_001',
      productTitle: 'Кроссовки Nike Air Max 270',
      productImageUrl:
          'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=200',
      price: 45000,
      quantity: 1,
      status: OrderStatus.delivered,
      createdAt: DateTime.now().subtract(const Duration(days: 14)),
    ),
    OrderEntity(
      id: 'order_002',
      productTitle: 'Рюкзак Adidas Classic',
      productImageUrl:
          'https://images.unsplash.com/photo-1553062407-98eeb64c6a62?w=200',
      price: 12500,
      quantity: 2,
      status: OrderStatus.shipped,
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    OrderEntity(
      id: 'order_003',
      productTitle: 'Футболка с принтом',
      productImageUrl:
          'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=200',
      price: 3900,
      quantity: 1,
      status: OrderStatus.pending,
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    ),
  ];

  @override
  Future<List<OrderEntity>> getOrders() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return List.unmodifiable(_mockOrders);
  }
}
