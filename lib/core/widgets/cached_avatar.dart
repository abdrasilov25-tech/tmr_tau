import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class CachedAvatar extends StatelessWidget {
  const CachedAvatar({
    super.key,
    this.imageUrl,
    this.radius = 24,
    this.fallbackText,
    this.enableLightboxOnTap = true,
  });

  final String? imageUrl;
  final double radius;
  final String? fallbackText;

  /// Если false — тап не открывает полноэкранный просмотр (нужно для [UserAvatarTap] / перехода в профиль).
  final bool enableLightboxOnTap;

  @override
  Widget build(BuildContext context) {
    final fallback = fallbackText != null && fallbackText!.isNotEmpty
        ? fallbackText![0].toUpperCase()
        : '?';
    final rawUrl = imageUrl;
    if (rawUrl == null || rawUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Text(
          fallback,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }
    // Для разных аккаунтов мы используем уникальный URL (uid в query),
    // поэтому принудительная очистка кэша на каждом build не требуется.
    final url = rawUrl;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // CachedNetworkImage требует memCache* > 0; при нулевом радиусе/DPR избегаем падения.
    final px = math.max(1, (radius * 2 * dpr).round());
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          memCacheWidth: px,
          memCacheHeight: px,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
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
    );

    if (!enableLightboxOnTap) {
      return avatar;
    }

    return GestureDetector(
      onTap: () {
        final u = imageUrl;
        if (u == null || u.isEmpty) return;
        showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: const EdgeInsets.all(24),
            child: AspectRatio(
              aspectRatio: 1,
              child: InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: u,
                  fit: BoxFit.cover,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (_, unused) =>
                      const ColoredBox(color: Colors.black26),
                  errorWidget: (_, unused, error) =>
                      const ColoredBox(color: Colors.black54),
                ),
              ),
            ),
          ),
        );
      },
      child: avatar,
    );
  }
}
