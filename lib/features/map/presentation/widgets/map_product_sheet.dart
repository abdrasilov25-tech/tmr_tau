import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/map_product.dart';
import '../../../../features/product/domain/entities/product_entity.dart';

class MapProductSheet extends StatelessWidget {
  const MapProductSheet({super.key, required this.product});

  final MapProduct product;

  @override
  Widget build(BuildContext context) {
    return _MapProductSheetBody(product: product);
  }
}

class _MapProductSheetBody extends StatefulWidget {
  const _MapProductSheetBody({required this.product});

  final MapProduct product;

  @override
  State<_MapProductSheetBody> createState() => _MapProductSheetBodyState();
}

class _MapProductSheetBodyState extends State<_MapProductSheetBody> {
  bool _ratingLoading = false;
  int _myStars = 0;

  Future<void> _rateBusiness(int stars) async {
    final client = Supabase.instance.client;
    final authUser = client.auth.currentUser;
    if (authUser == null) return;
    setState(() {
      _ratingLoading = true;
      _myStars = stars;
    });
    try {
      await client.from('business_reviews').upsert({
        'business_user_id': widget.product.sellerId,
        'reviewer_id': authUser.id,
        'stars': stars,
      }, onConflict: 'business_user_id,reviewer_id');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Спасибо за оценку!')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось отправить оценку')),
      );
    } finally {
      if (mounted) {
        setState(() => _ratingLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: product.imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: product.imageUrl!,
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => _placeholder(),
                      )
                    : _placeholder(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.priceFormatted,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: const Color(0xFF2563EB),
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (product.city != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 2),
                          Text(
                            product.city!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ],
                    if (product.sellerName != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        product.sellerName!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey.shade500),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 4),
                        Text(
                          product.sellerRatingCount > 0
                              ? '${product.sellerRatingAverage.toStringAsFixed(1)} (${product.sellerRatingCount})'
                              : 'Нет оценок',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const Text(
                  'Оцените бизнес:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: _ratingLoading ? null : () => _rateBusiness(i),
                    icon: Icon(
                      i <= _myStars ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: const Color(0xFFF59E0B),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Build a minimal ProductEntity for navigation
                final entity = ProductEntity(
                  id: product.id,
                  title: product.title,
                  description: '',
                  price: product.price,
                  sellerId: product.sellerId,
                  imageUrls: product.imageUrl != null ? [product.imageUrl!] : [],
                  city: product.city,
                  sellerName: product.sellerName,
                  sellerAvatarUrl: product.sellerAvatarUrl,
                  latitude: product.latitude,
                  longitude: product.longitude,
                );
                context.push('/product/${product.id}', extra: entity);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Открыть объявление'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 90,
        height: 90,
        color: Colors.grey.shade100,
        child: Icon(Icons.image_outlined, color: Colors.grey.shade400, size: 32),
      );
}
