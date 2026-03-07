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
    this.isFollowingByMe = false,
    this.products = const [],
    this.isVerified = false,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String? bio;
  final int followersCount;
  final int followingCount;
  final bool isFollowingByMe;
  final List<ProductEntity> products;
  final bool isVerified;

  @override
  List<Object?> get props =>
      [id, name, avatarUrl, bio, followersCount, followingCount, isFollowingByMe, isVerified];
}
