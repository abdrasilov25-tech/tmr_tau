import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/featured_seller.dart';

/// Compact banner shown on the map — displays today's top bidder.
/// Tapping opens the bid sheet for sellers, or seller profile for buyers.
class FeaturedSellerBanner extends StatelessWidget {
  const FeaturedSellerBanner({
    super.key,
    required this.featured,
    required this.currentUserId,
    required this.onBidTap,
    required this.onSellerTap,
  });

  final FeaturedSeller featured;
  final String? currentUserId;
  final VoidCallback onBidTap;
  final VoidCallback onSellerTap;

  bool get _isCurrentUserFeatured => currentUserId == featured.userId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSellerTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A1A), Color(0xFF2D2D2D)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Trophy icon
            const Text('🏆', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            // Avatar
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey.shade700,
              backgroundImage: featured.sellerAvatarUrl != null
                  ? CachedNetworkImageProvider(featured.sellerAvatarUrl!)
                  : null,
              child: featured.sellerAvatarUrl == null
                  ? const Icon(Icons.person, size: 16, color: Colors.white54)
                  : null,
            ),
            const SizedBox(width: 8),
            // Name + label
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Продавец дня',
                    style: TextStyle(
                      color: Color(0xFFF59E0B),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    _isCurrentUserFeatured ? 'Вы — лидер!' : featured.sellerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Bid badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
              ),
              child: Text(
                '${featured.bidAmount} Q',
                style: const TextStyle(
                  color: Color(0xFFF59E0B),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Bid CTA
            GestureDetector(
              onTap: onBidTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isCurrentUserFeatured ? 'Поднять' : 'Обогнать',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when no one has bid yet — encourages first bid.
class FeaturedSellerEmptyBanner extends StatelessWidget {
  const FeaturedSellerEmptyBanner({super.key, required this.onBidTap});

  final VoidCallback onBidTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onBidTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFF59E0B).withValues(alpha: 0.12),
              const Color(0xFFF97316).withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            const Text('🏆', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Место продавца дня свободно — станьте первым!',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF92400E),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Занять',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
