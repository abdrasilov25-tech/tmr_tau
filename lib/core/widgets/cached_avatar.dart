import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class CachedAvatar extends StatelessWidget {
  const CachedAvatar({
    super.key,
    this.imageUrl,
    this.radius = 24,
    this.fallbackText,
  });

  final String? imageUrl;
  final double radius;
  final String? fallbackText;

  @override
  Widget build(BuildContext context) {
    final fallback = fallbackText != null && fallbackText!.isNotEmpty
        ? fallbackText![0].toUpperCase()
        : '?';
    if (imageUrl == null || imageUrl!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Text(
          fallback,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }
    return GestureDetector(
      onTap: () {
        final url = imageUrl;
        if (url == null || url.isEmpty) return;
        showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: const EdgeInsets.all(24),
            child: AspectRatio(
              aspectRatio: 1,
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        );
      },
      child: CircleAvatar(
        radius: radius,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: imageUrl!,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            placeholder: (context, url) => Center(
              child: Text(
                fallback,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            errorWidget: (context, url, error) => Text(
              fallback,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
      ),
    );
  }
}
