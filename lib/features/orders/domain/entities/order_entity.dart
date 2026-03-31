import 'package:equatable/equatable.dart';

enum OrderStatus {
  pendingSeller,
  inEscrow,
  completed,
  cancelled,
}

class OrderEntity extends Equatable {
  const OrderEntity({
    required this.id,
    required this.buyerId,
    required this.sellerId,
    required this.productId,
    required this.productTitle,
    required this.status,
    required this.amountKzt,
    required this.commissionPercent,
    required this.commissionKzt,
    required this.sellerAmountKzt,
    required this.createdAt,
    this.sellerAcceptedAt,
    this.buyerConfirmedAt,
    this.completedAt,
    this.cancelledAt,
  });

  final String id;
  final String buyerId;
  final String sellerId;
  final String productId;
  final String productTitle;
  final OrderStatus status;
  final double amountKzt;
  final int commissionPercent;
  final double commissionKzt;
  final double sellerAmountKzt;
  final DateTime createdAt;
  final DateTime? sellerAcceptedAt;
  final DateTime? buyerConfirmedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  bool get isTerminal =>
      status == OrderStatus.completed || status == OrderStatus.cancelled;

  @override
  List<Object?> get props => [
        id,
        buyerId,
        sellerId,
        productId,
        productTitle,
        status,
        amountKzt,
        commissionPercent,
        commissionKzt,
        sellerAmountKzt,
        createdAt,
        sellerAcceptedAt,
        buyerConfirmedAt,
        completedAt,
        cancelledAt,
      ];
}
