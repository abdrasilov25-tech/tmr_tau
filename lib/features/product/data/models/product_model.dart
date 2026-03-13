import '../../domain/entities/product_entity.dart';

String _categoryNameFromJson(Map<String, dynamic> json) {
  if (json['category'] != null && json['category'] is String) {
    return json['category'] as String;
  }
  final cat = json['categories'];
  if (cat is Map && cat['name'] != null) return cat['name'] as String;
  return 'general';
}

class ProductModel extends ProductEntity {
  const ProductModel({
    required super.id,
    required super.title,
    required super.description,
    required super.price,
    required super.imageUrl,
    required super.sellerId,
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
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      price: (json['price'] as num).toDouble(),
      imageUrl: json['image_url'] as String? ?? '',
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
    );
  }
}
