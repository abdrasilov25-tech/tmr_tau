import 'package:equatable/equatable.dart';

enum OrderStatus { pending, confirmed, shipped, delivered, cancelled }

extension OrderStatusLabel on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.pending:
        return 'Ожидание';
      case OrderStatus.confirmed:
        return 'Подтверждён';
      case OrderStatus.shipped:
        return 'В доставке';
      case OrderStatus.delivered:
        return 'Доставлен';
      case OrderStatus.cancelled:
        return 'Отменён';
    }
  }
}

class OrderEntity extends Equatable {
  const OrderEntity({
    required this.id,
    required this.productTitle,
    required this.productImageUrl,
    required this.price,
    required this.quantity,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String productTitle;
  final String productImageUrl;
  final double price;
  final int quantity;
  final OrderStatus status;
  final DateTime createdAt;

  double get total => price * quantity;

  @override
  List<Object?> get props =>
      [id, productTitle, productImageUrl, price, quantity, status, createdAt];
}
