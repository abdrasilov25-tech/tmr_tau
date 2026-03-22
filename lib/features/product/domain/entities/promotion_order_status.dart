import 'package:equatable/equatable.dart';

enum PromotionPaymentStatus {
  pending,
  paid,
  failed,
  cancelled,
}

/// Статус заказа из таблицы `product_promotion_orders` (после webhook / опроса).
class PromotionOrderStatus extends Equatable {
  const PromotionOrderStatus({
    required this.orderId,
    required this.status,
    this.providerRef,
  });

  final String orderId;
  final PromotionPaymentStatus status;
  final String? providerRef;

  @override
  List<Object?> get props => [orderId, status, providerRef];
}
