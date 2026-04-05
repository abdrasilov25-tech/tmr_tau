import 'package:equatable/equatable.dart';

/// Map boost levels for seller visibility on the map.
/// 0 = none, 1 = Boost (50 Qarmet/24h), 2 = Top Zone (150 Qarmet/24h).
enum MapBoostLevel { none, boost, topZone }

class MapProduct extends Equatable {
  const MapProduct({
    required this.id,
    required this.title,
    required this.price,
    required this.latitude,
    required this.longitude,
    this.imageUrl,
    this.city,
    this.sellerName,
    this.sellerAvatarUrl,
    this.sellerId = '',
    this.isUrgent = false,
    this.isTop = false,
    this.sellerRatingAverage = 0,
    this.sellerRatingCount = 0,
    this.mapBoostLevel = MapBoostLevel.none,
    this.mapBoostExpiresAt,
    this.mapMarkerSticker,
  });

  final String id;
  final String title;
  final double price;
  final double latitude;
  final double longitude;
  final String? imageUrl;
  final String? city;
  final String? sellerName;
  final String? sellerAvatarUrl;
  final String sellerId;
  final bool isUrgent;
  final bool isTop;
  final double sellerRatingAverage;
  final int sellerRatingCount;
  final MapBoostLevel mapBoostLevel;
  final DateTime? mapBoostExpiresAt;
  final String? mapMarkerSticker;

  bool get isBoosted =>
      mapBoostLevel != MapBoostLevel.none &&
      (mapBoostExpiresAt == null ||
          mapBoostExpiresAt!.isAfter(DateTime.now().toUtc()));

  String get priceFormatted => '${price.toStringAsFixed(0)} ₸';

  @override
  List<Object?> get props => [
        id,
        title,
        price,
        latitude,
        longitude,
        isUrgent,
        isTop,
        sellerRatingAverage,
        sellerRatingCount,
        mapBoostLevel,
        mapBoostExpiresAt,
        mapMarkerSticker,
      ];
}
