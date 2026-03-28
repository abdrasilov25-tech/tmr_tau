import '../entities/order_entity.dart';

abstract interface class OrdersRepository {
  Future<List<OrderEntity>> getOrders();
}
