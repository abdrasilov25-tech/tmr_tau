import 'package:equatable/equatable.dart';

/// Описание IAP-пакета Qarmet (расширяемая конфигурация витрины).
class QarmetProduct extends Equatable {
  const QarmetProduct({
    required this.productId,
    required this.title,
    required this.baseQarmet,
    required this.bonusQarmet,
    required this.priceKzt,
    this.isSubscription = false,
  });

  final String productId;
  final String title;
  final int baseQarmet;
  final int bonusQarmet;
  final int priceKzt;
  final bool isSubscription;

  int get totalQarmet => baseQarmet + bonusQarmet;
  double get pricePerQarmet => priceKzt / totalQarmet;

  @override
  List<Object?> get props => [
    productId,
    title,
    baseQarmet,
    bonusQarmet,
    priceKzt,
    isSubscription,
  ];
}
