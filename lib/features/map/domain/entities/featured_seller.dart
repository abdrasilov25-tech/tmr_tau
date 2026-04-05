import 'package:equatable/equatable.dart';

class FeaturedSeller extends Equatable {
  const FeaturedSeller({
    required this.userId,
    required this.sellerName,
    required this.bidAmount,
    this.sellerAvatarUrl,
  });

  final String userId;
  final String sellerName;
  final String? sellerAvatarUrl;
  final int bidAmount;

  @override
  List<Object?> get props => [userId, bidAmount];
}
