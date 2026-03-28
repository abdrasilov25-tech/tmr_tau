import 'package:flutter/material.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/double_tap_like_burst.dart';
import '../../../post/domain/entities/post_entity.dart';
import 'feed_video_media.dart';

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: SizedBox(
          width: 52,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(height: 2),
              Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.onTap, required this.isSaved});

  final VoidCallback onTap;
  final bool isSaved;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: SizedBox(
          width: 44,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: Colors.white,
                size: 21,
              ),
              const SizedBox(height: 2),
              const Text(
                'Сохран.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: SizedBox(
          width: 52,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.send_outlined, color: Colors.white, size: 21),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Публичный виджет: один элемент TikTok-ленты.
class FeedPostItem extends StatefulWidget {
  const FeedPostItem({
    super.key,
    required this.height,
    required this.post,
    required this.currentUserId,
    required this.onLike,
    required this.onComment,
    required this.onRepost,
    required this.onSave,
    required this.onShare,
  });

  final double height;
  final PostEntity post;
  final String? currentUserId;

  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onRepost;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  State<FeedPostItem> createState() => _FeedPostItemState();
}

class _FeedPostItemState extends State<FeedPostItem> {
  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final mediaHeight = widget.height;

    return SizedBox(
      height: mediaHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: DoubleTapLikeBurst(
              onDoubleTapLike: widget.onLike,
              shouldTriggerLike: () => !p.isLikedByMe,
              showPersistentLikeIndicator: true,
              isLiked: p.isLikedByMe,
              child: FeedPostMedia(
                imageUrls: p.displayImageUrls,
                videoUrl: p.videoUrl,
                fillHeight: mediaHeight,
              ),
            ),
          ),
          // Верхняя панель: автор.
          Positioned(
            left: 12,
            right: 12,
            top: 10,
            child: SafeArea(
              bottom: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CachedAvatar(
                    imageUrl: p.userAvatarUrl?.isNotEmpty == true
                        ? '${p.userAvatarUrl}?uid=${p.userId}'
                        : null,
                    radius: 18,
                    fallbackText: p.userName ?? 'П',
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      p.userName ?? 'Пользователь',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Низ: описание + действия.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((p.caption).trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          p.caption.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      border: Border(
                        top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08)),
                      ),
                    ),
                    child: Row(
                      children: [
                        _ActionButton(
                          icon: p.isLikedByMe
                              ? Icons.favorite
                              : Icons.favorite_border,
                          iconColor:
                              p.isLikedByMe ? Colors.redAccent : Colors.white,
                          label: 'Лайк',
                          count: p.likesCount,
                          onTap: widget.onLike,
                        ),
                        _ActionButton(
                          icon: Icons.chat_bubble_outline_rounded,
                          iconColor: Colors.white,
                          label: 'Коммент',
                          count: p.commentsCount,
                          onTap: widget.onComment,
                        ),
                        _ActionButton(
                          icon: p.isRepostedByMe
                              ? Icons.repeat
                              : Icons.repeat_outlined,
                          iconColor: p.isRepostedByMe
                              ? Colors.cyanAccent
                              : Colors.white,
                          label: 'Репост',
                          count: p.repostsCount,
                          onTap: widget.onRepost,
                        ),
                        _ShareButton(
                          onTap: widget.onShare,
                          label: 'Поделиться',
                        ),
                        const Spacer(),
                        _SaveButton(
                          onTap: widget.onSave,
                          isSaved: p.isSavedByMe,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
