import 'package:equatable/equatable.dart';

class ProductEntity extends Equatable {
  const ProductEntity({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.sellerId,
    this.imageUrls = const [],
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
    this.contactPhone,
  });

  final String id;
  final String title;
  final String description;
  final double price;
  final String sellerId;
  /// Все фото объявления (первая — обложка в ленте).
  final List<String> imageUrls;
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
  /// Телефон для звонка покупателю (как в OLX), опционально.
  final String? contactPhone;

  /// Обложка (совместимость со старым полем `image_url`).
  String get imageUrl => imageUrls.isNotEmpty ? imageUrls.first : '';

  String get priceFormatted => '${price.toStringAsFixed(0)} ₸';

  @override
  List<Object?> get props => [
    id,
    title,
    description,
    price,
    sellerId,
    imageUrls,
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
    contactPhone,
  ];
}
