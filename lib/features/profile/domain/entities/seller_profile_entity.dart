import 'package:equatable/equatable.dart';
import '../../../product/domain/entities/product_entity.dart';

class SellerProfileEntity extends Equatable {
  const SellerProfileEntity({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.bio,
    this.followersCount = 0,
    this.followingCount = 0,
    /// Сумма лайков по всем публикациям пользователя (как «Лайки» в TikTok).
    this.totalReceivedPostLikes = 0,
    this.isFollowingByMe = false,
    this.products = const [],
    this.isVerified = false,
    this.instagramUrl,
    this.telegramUsername,
    this.websiteUrl,
    /// Номер жителя города (из `public.users.resident_number`).
    this.residentNumber,
    /// Подписка Official Page (IAP): витрина, график «Профессиональная» и т.п.
    this.officialPageActive = false,
    /// Лучший результат в «Тап судьбы» — показывается всем на профиле.
    this.bestTapScore = 0,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String? bio;
  final int followersCount;
  final int followingCount;
  final int totalReceivedPostLikes;
  final bool isFollowingByMe;
  final List<ProductEntity> products;
  final bool isVerified;
  final String? instagramUrl;
  final String? telegramUsername;
  final String? websiteUrl;
  final String? residentNumber;
  final bool officialPageActive;
  final int bestTapScore;

  SellerProfileEntity copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? bio,
    int? followersCount,
    int? followingCount,
    int? totalReceivedPostLikes,
    bool? isFollowingByMe,
    List<ProductEntity>? products,
    bool? isVerified,
    String? instagramUrl,
    String? telegramUsername,
    String? websiteUrl,
    String? residentNumber,
    bool? officialPageActive,
    int? bestTapScore,
  }) {
    return SellerProfileEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      totalReceivedPostLikes:
          totalReceivedPostLikes ?? this.totalReceivedPostLikes,
      isFollowingByMe: isFollowingByMe ?? this.isFollowingByMe,
      products: products ?? this.products,
      isVerified: isVerified ?? this.isVerified,
      instagramUrl: instagramUrl ?? this.instagramUrl,
      telegramUsername: telegramUsername ?? this.telegramUsername,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      residentNumber: residentNumber ?? this.residentNumber,
      officialPageActive: officialPageActive ?? this.officialPageActive,
      bestTapScore: bestTapScore ?? this.bestTapScore,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        avatarUrl,
        bio,
        followersCount,
        followingCount,
        totalReceivedPostLikes,
        isFollowingByMe,
        products,
        isVerified,
        instagramUrl,
        telegramUsername,
        websiteUrl,
        residentNumber,
        officialPageActive,
        bestTapScore,
      ];
}
