import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class CachedProductImage extends StatelessWidget {
  const CachedProductImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    /// Ограничение декодирования в пикселях (для ленты — ширина экрана × DPR).
    this.memCacheWidth,
    this.memCacheHeight,
    /// В ленте не крутим индикатор на каждой карточке — только плейсхолдер.
    this.compactPlaceholder = false,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final bool compactPlaceholder;

  @override
  Widget build(BuildContext context) {
    final child = imageUrl.isEmpty
        ? Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.shopping_bag_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
          )
        : CachedNetworkImage(
            imageUrl: imageUrl,
            width: width,
            height: height,
            fit: fit,
            memCacheWidth: memCacheWidth,
            memCacheHeight: memCacheHeight,
            placeholder: (context, url) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: compactPlaceholder
                  ? const SizedBox.expand()
                  : const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.image_not_supported_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          );
    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: child,
      );
    }
    return child;
  }
}
