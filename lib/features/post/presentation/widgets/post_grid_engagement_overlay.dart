import 'package:flutter/material.dart';

import 'package:tmr_tau/core/formatting/compact_count_format.dart';
import '../../domain/entities/post_entity.dart';

/// Нижняя полоса с лайками, комментариями и (для видео) просмотрами — как в сетке Instagram.
class PostGridEngagementOverlay extends StatelessWidget {
  const PostGridEngagementOverlay({
    super.key,
    required this.post,
    required this.showViewCount,
  });

  final PostEntity post;
  final bool showViewCount;

  static bool isProbablyVideoPost(PostEntity post) {
    final videoUrl = (post.videoUrl ?? '').trim().toLowerCase();
    if (videoUrl.isNotEmpty) return true;
    final img = post.imageUrl.trim().toLowerCase();
    if (img.isEmpty) return false;
    return img.contains('/videos/') ||
        img.endsWith('.mp4') ||
        img.endsWith('.mov') ||
        img.endsWith('.m4v') ||
        img.endsWith('.webm') ||
        img.endsWith('.m3u8');
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.75),
              Colors.transparent,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 12, 5, 5),
          child: Row(
            children: [
              const Icon(
                Icons.favorite_rounded,
                size: 12,
                color: Colors.white,
              ),
              const SizedBox(width: 3),
              Text(
                formatCompactCount(post.likesCount),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 11,
                color: Colors.white,
              ),
              const SizedBox(width: 3),
              Text(
                formatCompactCount(post.commentsCount),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
                ),
              ),
              if (showViewCount) ...[
                const Spacer(),
                Icon(
                  Icons.play_arrow_rounded,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
                const SizedBox(width: 3),
                Text(
                  formatCompactCount(post.viewsCount),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 2),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
