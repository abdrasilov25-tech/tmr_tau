import 'package:equatable/equatable.dart';

class ProductEntity extends Equatable {
  const ProductEntity({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.sellerId,
    this.category = 'general',
    this.categoryId,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.repostsCount = 0,
    this.sellerName,
    this.sellerAvatarUrl,
    this.createdAt,
    this.isLikedByMe = false,
    this.isFollowingSeller = false,
    this.sellerIsVerified = false,
    this.isRepostedByMe = false,
    this.city,
    this.condition = 'any',
    this.isUrgent = false,
    this.isTop = false,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String title;
  final String description;
  final double price;
  final String imageUrl;
  final String sellerId;
  final String category;
  final String? categoryId;
  final int likesCount;
  final int commentsCount;
  final int repostsCount;
  final String? sellerName;
  final String? sellerAvatarUrl;
  final DateTime? createdAt;
  final bool isLikedByMe;
  final bool isFollowingSeller;
  final bool sellerIsVerified;
  final bool isRepostedByMe;
  final String? city;
  final String condition;
  final bool isUrgent;
  final bool isTop;
  final double? latitude;
  final double? longitude;

  String get priceFormatted => '${price.toStringAsFixed(0)} ₸';

  @override
  List<Object?> get props => [
    id,
    title,
    description,
    price,
    imageUrl,
    sellerId,
    category,
    categoryId,
    likesCount,
    commentsCount,
    repostsCount,
    sellerName,
    sellerAvatarUrl,
    createdAt,
    isLikedByMe,
    isFollowingSeller,
    sellerIsVerified,
    isRepostedByMe,
    city,
    condition,
    isUrgent,
    isTop,
    latitude,
    longitude,
  ];
}
