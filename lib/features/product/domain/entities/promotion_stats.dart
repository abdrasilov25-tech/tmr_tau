import 'package:equatable/equatable.dart';

/// Актуальная статистика и сроки продвижения для карточки товара.
class PromotionStats extends Equatable {
  const PromotionStats({
    required this.productId,
    required this.totalViews,
    this.promoTopUntil,
    this.promoUrgentUntil,
    this.promoHighlightUntil,
    this.statsAccessUntil,
    this.latitude,
    this.longitude,
  });

  final String productId;
  final int totalViews;
  final DateTime? promoTopUntil;
  final DateTime? promoUrgentUntil;
  final DateTime? promoHighlightUntil;
  final DateTime? statsAccessUntil;
  final double? latitude;
  final double? longitude;

  bool get hasCoords => latitude != null && longitude != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'product_id': productId,
        'total_views': totalViews,
        'promo_top_until': promoTopUntil?.toIso8601String(),
        'promo_urgent_until': promoUrgentUntil?.toIso8601String(),
        'promo_highlight_until': promoHighlightUntil?.toIso8601String(),
        'stats_access_until': statsAccessUntil?.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
      };

  factory PromotionStats.fromJson(Map<String, dynamic> json) {
    DateTime? ts(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    return PromotionStats(
      productId: json['product_id']?.toString() ?? '',
      totalViews: (json['total_views'] as num?)?.toInt() ?? 0,
      promoTopUntil: ts(json['promo_top_until']),
      promoUrgentUntil: ts(json['promo_urgent_until']),
      promoHighlightUntil: ts(json['promo_highlight_until']),
      statsAccessUntil: ts(json['stats_access_until']),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }

  @override
  List<Object?> get props => <Object?>[
        productId,
        totalViews,
        promoTopUntil,
        promoUrgentUntil,
        promoHighlightUntil,
        statsAccessUntil,
        latitude,
        longitude,
      ];
}
