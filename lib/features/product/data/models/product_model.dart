import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/entities/product_entity.dart';

String _categoryNameFromJson(Map<String, dynamic> json) {
  if (json['category'] != null && json['category'] is String) {
    return json['category'] as String;
  }
  final cat = json['categories'];
  if (cat is Map && cat['name'] != null) return cat['name'] as String;
  return 'general';
}

List<String> _imageUrlsFromJson(Map<String, dynamic> json) {
  final rawUrlsCol = json['image_urls'];
  if (rawUrlsCol is List && rawUrlsCol.isNotEmpty) {
    return rawUrlsCol
        .map((e) => e.toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }
  final legacy = json['image_url'] as String? ?? '';
  final t = legacy.trim();
  if (t.isEmpty) return <String>[];
  // Несколько фото в одном text-поле `image_url` как JSON: ["url1","url2"]
  if (t.startsWith('[')) {
    try {
      final decoded = jsonDecode(t);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (e) { debugPrint('$e'); }
  }
  return <String>[t];
}

DateTime? _ts(dynamic v) {
  if (v == null) return null;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

class ProductModel extends ProductEntity {
  const ProductModel({
    required super.id,
    required super.title,
    required super.description,
    required super.price,
    required super.sellerId,
    super.imageUrls = const [],
    super.category = 'general',
    super.categoryId,
    super.likesCount = 0,
    super.commentsCount = 0,
    super.repostsCount = 0,
    super.sellerName,
    super.sellerAvatarUrl,
    super.createdAt,
    super.isLikedByMe = false,
    super.isFollowingSeller = false,
    super.sellerIsVerified = false,
    super.isRepostedByMe = false,
    super.city,
    super.condition = 'any',
    super.isUrgent = false,
    super.isTop = false,
    super.isNegotiable = false,
    super.isGiveaway = false,
    super.latitude,
    super.longitude,
    super.contactPhone,
    super.promoTopUntil,
    super.promoUrgentUntil,
    super.promoHighlightUntil,
    super.statsAccessUntil,
    super.viewCount = 0,
  });

  /// Копия сущности с точечными переопределениями (лента / оптимистичные обновления).
  factory ProductModel.fromEntity(
    ProductEntity e, {
    bool? isLikedByMe,
    bool? isFollowingSeller,
    bool? isRepostedByMe,
    int? likesCount,
    int? repostsCount,
    int? commentsCount,
    int? viewCount,
    DateTime? promoTopUntil,
    DateTime? promoUrgentUntil,
    DateTime? promoHighlightUntil,
    DateTime? statsAccessUntil,
  }) {
    return ProductModel(
      id: e.id,
      title: e.title,
      description: e.description,
      price: e.price,
      imageUrls: e.imageUrls,
      sellerId: e.sellerId,
      category: e.category,
      categoryId: e.categoryId,
      likesCount: likesCount ?? e.likesCount,
      commentsCount: commentsCount ?? e.commentsCount,
      repostsCount: repostsCount ?? e.repostsCount,
      sellerName: e.sellerName,
      sellerAvatarUrl: e.sellerAvatarUrl,
      createdAt: e.createdAt,
      isLikedByMe: isLikedByMe ?? e.isLikedByMe,
      isFollowingSeller: isFollowingSeller ?? e.isFollowingSeller,
      sellerIsVerified: e.sellerIsVerified,
      isRepostedByMe: isRepostedByMe ?? e.isRepostedByMe,
      city: e.city,
      condition: e.condition,
      isUrgent: e.isUrgent,
      isTop: e.isTop,
      isNegotiable: e.isNegotiable,
      isGiveaway: e.isGiveaway,
      latitude: e.latitude,
      longitude: e.longitude,
      contactPhone: e.contactPhone,
      promoTopUntil: promoTopUntil ?? e.promoTopUntil,
      promoUrgentUntil: promoUrgentUntil ?? e.promoUrgentUntil,
      promoHighlightUntil: promoHighlightUntil ?? e.promoHighlightUntil,
      statsAccessUntil: statsAccessUntil ?? e.statsAccessUntil,
      viewCount: viewCount ?? e.viewCount,
    );
  }

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      price: (json['price'] as num).toDouble(),
      imageUrls: _imageUrlsFromJson(json),
      sellerId: json['seller_id'] as String,
      category: json['category'] as String? ?? _categoryNameFromJson(json),
      categoryId: json['category_id'] as String?,
      likesCount: json['likes_count'] as int? ?? 0,
      commentsCount: json['comments_count'] as int? ?? 0,
      repostsCount: json['reposts_count'] as int? ?? 0,
      sellerName: json['seller_name'] as String?,
      sellerAvatarUrl: json['seller_avatar'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      isLikedByMe: json['is_liked_by_me'] as bool? ?? false,
      isFollowingSeller: json['is_following_seller'] as bool? ?? false,
      sellerIsVerified: json['seller_is_verified'] as bool? ?? false,
      city: json['city'] as String?,
      condition: json['condition'] as String? ?? 'any',
      isUrgent: json['is_urgent'] as bool? ?? false,
      isTop: json['is_top'] as bool? ?? false,
      isNegotiable: json['is_negotiable'] as bool? ?? false,
      isGiveaway: json['is_giveaway'] as bool? ?? false,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      contactPhone: json['contact_phone'] as String?,
      promoTopUntil: _ts(json['promo_top_until']),
      promoUrgentUntil: _ts(json['promo_urgent_until']),
      promoHighlightUntil: _ts(json['promo_highlight_until']),
      statsAccessUntil: _ts(json['stats_access_until']),
      viewCount: json['view_count'] as int? ?? 0,
    );
  }
}
