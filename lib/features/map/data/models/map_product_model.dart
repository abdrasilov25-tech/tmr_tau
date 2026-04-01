import '../../domain/entities/map_product.dart';

List<String> _imageUrlsFromJson(Map<String, dynamic> json) {
  final rawUrlsCol = json['image_urls'];
  if (rawUrlsCol is List && rawUrlsCol.isNotEmpty) {
    return rawUrlsCol
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  final legacy = json['image_url'] as String? ?? '';
  final t = legacy.trim();
  return t.isEmpty ? const [] : [t];
}

class MapProductModel extends MapProduct {
  const MapProductModel({
    required super.id,
    required super.title,
    required super.price,
    required super.latitude,
    required super.longitude,
    super.imageUrl,
    super.city,
    super.sellerName,
    super.sellerAvatarUrl,
    super.sellerId,
    super.isUrgent,
    super.isTop,
    super.sellerRatingAverage,
    super.sellerRatingCount,
  });

  factory MapProductModel.fromJson(Map<String, dynamic> json) {
    final urls = _imageUrlsFromJson(json);
    final user = json['users'];
    return MapProductModel(
      id: json['id'] as String,
      title: json['title'] as String,
      price: (json['price'] as num).toDouble(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      imageUrl: urls.isNotEmpty ? urls.first : null,
      city: json['city'] as String?,
      sellerId: json['seller_id'] as String? ?? '',
      sellerName: user is Map ? user['name'] as String? : null,
      sellerAvatarUrl: user is Map ? user['avatar'] as String? : null,
      isUrgent: json['is_urgent'] == true,
      isTop: json['is_top'] == true,
      sellerRatingAverage: (json['seller_rating_avg'] as num?)?.toDouble() ?? 0,
      sellerRatingCount: (json['seller_rating_count'] as num?)?.toInt() ?? 0,
    );
  }
}
