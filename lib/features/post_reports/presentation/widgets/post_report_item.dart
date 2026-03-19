import 'package:flutter/material.dart';

import '../../../../core/widgets/cached_product_image.dart';
import '../../domain/entities/post_report_entity.dart';

class PostReportItem extends StatelessWidget {
  const PostReportItem({
    super.key,
    required this.item,
    this.onTapPost,
  });

  final PostReportEntity item;
  final VoidCallback? onTapPost;

  @override
  Widget build(BuildContext context) {
    final hasImage = item.postImageUrl != null && item.postImageUrl!.isNotEmpty;
    final hasVideo = item.postVideoUrl != null && item.postVideoUrl!.isNotEmpty;
    final isMediaPresent = hasImage || hasVideo;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTapPost,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 78,
                height: 78,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: isMediaPresent
                      ? hasImage
                          ? CachedProductImage(
                              imageUrl: item.postImageUrl ?? '',
                            )
                          : Container(
                              color: Colors.grey.shade300,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.play_circle_fill,
                                size: 36,
                                color: Colors.white70,
                              ),
                            )
                      : Container(
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const Icon(Icons.article_outlined, size: 28),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _reasonLabel(item.reason),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    if (item.comment != null && item.comment!.isNotEmpty) ...[
                      Text(
                        item.comment!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      _formatDate(item.createdAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d.$m.${dt.year}';
  }

  String _reasonLabel(String reason) {
    switch (reason) {
      case 'spam':
        return 'Спам';
      case 'abuse':
        return 'Оскорбления';
      case 'nudity':
        return 'Ненормативный контент';
      case 'copyright':
        return 'Нарушение авторских прав';
      case 'other':
        return 'Другое';
      default:
        return reason;
    }
  }
}

