import 'package:equatable/equatable.dart';

class MysterySpot extends Equatable {
  const MysterySpot({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.qarmetReward,
    required this.alreadyClaimed,
    this.isSellerSponsored = false,
    this.sellerName,
    this.sellerOffer,
    this.sellerId,
    this.productId,
  });

  final String id;
  final double latitude;
  final double longitude;
  final int qarmetReward;
  final bool alreadyClaimed;
  final bool isSellerSponsored;
  final String? sellerName;
  final String? sellerOffer;
  final String? sellerId;
  final String? productId;

  @override
  List<Object?> get props => [id, alreadyClaimed];
}

class MysterySpotRevealResult {
  const MysterySpotRevealResult({
    required this.qarmetAwarded,
    required this.newBalance,
    required this.alreadyClaimed,
    this.isSellerSponsored = false,
    this.sellerOffer,
    this.productId,
  });

  final int qarmetAwarded;
  final int newBalance;
  final bool alreadyClaimed;
  final bool isSellerSponsored;
  final String? sellerOffer;
  final String? productId;
}
