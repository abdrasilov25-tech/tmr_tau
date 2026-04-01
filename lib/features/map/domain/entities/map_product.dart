import 'package:equatable/equatable.dart';

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
      ];
}
