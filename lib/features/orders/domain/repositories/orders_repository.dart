import '../entities/order_entity.dart';

abstract class OrdersRepository {
  Future<OrderEntity> createSafeOrder({
    required String buyerId,
    required String sellerId,
    required String productId,
    required String productTitle,
    required double amountKzt,
    int commissionPercent = 4,
  });

  Future<List<OrderEntity>> getMyOrders(String userId);

  Future<void> acceptOrderBySeller({
    required String orderId,
    required String sellerId,
  });

  Future<void> confirmReceiptByBuyer({
    required String orderId,
    required String buyerId,
  });

  Future<void> cancelOrder({
    required String orderId,
    required String actorId,
  });
}
