import 'package:equatable/equatable.dart';

class QarmetPromotionHistoryItem extends Equatable {
  const QarmetPromotionHistoryItem({
    required this.productId,
    required this.title,
    required this.isTopActive,
    required this.isUrgentActive,
    required this.isHighlightActive,
    this.promoTopUntil,
    this.promoUrgentUntil,
    this.promoHighlightUntil,
  });

  final String productId;
  final String title;
  final bool isTopActive;
  final bool isUrgentActive;
  final bool isHighlightActive;
  final DateTime? promoTopUntil;
  final DateTime? promoUrgentUntil;
  final DateTime? promoHighlightUntil;

  bool get hasAnyPromotion =>
      isTopActive || isUrgentActive || isHighlightActive;

  @override
  List<Object?> get props => [
    productId,
    title,
    isTopActive,
    isUrgentActive,
    isHighlightActive,
    promoTopUntil,
    promoUrgentUntil,
    promoHighlightUntil,
  ];
}
