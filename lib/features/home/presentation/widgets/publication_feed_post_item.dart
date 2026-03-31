import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/double_tap_like_burst.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../pages/post_detail_modal.dart';
import '../pages/video_feed_screen.dart';
import 'user_avatar_tap.dart';

/// Instagram-стиль карточка публикации для ленты.
///
/// Вставляй в ListView.builder вместо старого _InstagramPostItem:
/// ```dart
/// PublicationFeedPostItem(
///   post: post,
///   allVideoPosts: videoPosts, // для VideoFeedScreen
///   postRepository: repository,
///   currentUserId: userId,
///   onLike: () { ... },
///   onSave: () { ... },
/// )
/// ```
class PublicationFeedPostItem extends StatelessWidget {
  const PublicationFeedPostItem({
    super.key,
    required this.post,
    required this.allPosts,
    required this.postRepository,
    this.currentUserId,
    this.onLike,
    this.onSave,
    this.onRepost,
    this.onFollow,
  });

  final PostEntity post;

  /// Все посты ленты (нужны для VideoFeedScreen — чтобы можно было
  /// листать другие видео не возвращаясь в ленту).
  final List<PostEntity> allPosts;

  final PostRepository postRepository;
  final String? currentUserId;

  final VoidCallback? onLike;
  final VoidCallback? onSave;
  final VoidCallback? onRepost;
  final VoidCallback? onFollow;

  bool get _isOwnPost => currentUserId != null && currentUserId == post.userId;

  void _openDetail(BuildContext context) {
    PostDetailModal.show(
      context,
      post: post,
      repository: postRepository,
      currentUserId: currentUserId,
    );
  }

  void _openVideoFeed(BuildContext context) {
    // Передаём только видео-посты, начинаем с текущего
    final videoPosts = allPosts.where((p) => p.videoUrl != null).toList();
    if (videoPosts.isEmpty) return;

    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => VideoFeedScreen(
          initialPost: post,
          allPosts: videoPosts,
          postRepository: postRepository,
          currentUserId: currentUserId,
        ),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Шапка: аватар + имя + кнопка ───────────────────
          _PostHeader(
            post: post,
            currentUserId: currentUserId,
            isOwnPost: _isOwnPost,
            onFollow: onFollow,
          ),

          // ── Медиа (фото галерея или видео превью) ───────────
          _PostMedia(
            post: post,
            onTap: post.videoUrl != null
                ? () => _openVideoFeed(context)
                : null,
            onDoubleTap: onLike,
          ),

          // ── Кнопки действий ─────────────────────────────────
          _ActionRow(
            post: post,
            currentUserId: currentUserId,
            onLike: onLike,
            onComment: () => _openDetail(context),
            onRepost: onRepost,
            onSave: onSave,
          ),

          // ── Счётчик лайков ──────────────────────────────────
          if (post.likesCount > 0)
            _LikesLabel(count: post.likesCount),

          // ── Caption ─────────────────────────────────────────
          if (post.caption.isNotEmpty)
            _CaptionLine(post: post),

          // ── Превью комментариев ─────────────────────────────
          if (post.commentsCount > 0)
            _CommentHint(
              count: post.commentsCount,
              onTap: () => _openDetail(context),
            ),

          const SizedBox(height: 8),
          const Divider(height: 1, thickness: 0.3),
        ],
      ),
    );
  }
}

// ── Шапка ────────────────────────────────────────────────────

class _PostHeader extends StatelessWidget {
  const _PostHeader({
    required this.post,
    required this.currentUserId,
    required this.isOwnPost,
    required this.onFollow,
  });

  final PostEntity post;
  final String? currentUserId;
  final bool isOwnPost;
  final VoidCallback? onFollow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Аватар — переходит на профиль
          UserAvatarTap(
            userId: post.userId,
            avatarUrl: post.userAvatarUrl,
            radius: 18,
            currentUserId: currentUserId,
          ),
          const SizedBox(width: 10),

          // Имя — переходит на профиль
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                UsernameTap(
                  userId: post.userId,
                  username: post.userName ?? 'Пользователь',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (post.createdAt != DateTime(0))
                  Text(
                    _timeAgo(post.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.45),
                    ),
                  ),
              ],
            ),
          ),

          // Кнопка Follow (не для своих постов)
          if (!isOwnPost && onFollow != null)
            _FollowButton(onTap: onFollow!),

          // Меню (три точки)
          _OptionsMenu(post: post, currentUserId: currentUserId),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин';
    if (diff.inDays < 1) return '${diff.inHours} ч';
    if (diff.inDays < 7) return '${diff.inDays} д';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} нед';
    return '${(diff.inDays / 30).floor()} мес';
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'Follow',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _OptionsMenu extends StatelessWidget {
  const _OptionsMenu({required this.post, required this.currentUserId});

  final PostEntity post;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.more_horiz_rounded, size: 22),
      visualDensity: VisualDensity.compact,
      onPressed: () => _showOptions(context),
    );
  }

  void _showOptions(BuildContext context) {
    final isOwn =
        currentUserId != null && currentUserId == post.userId;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOwn) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Редактировать'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/edit-post', extra: post);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Удалить',
                    style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(context),
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Пожаловаться'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/report-post', extra: post);
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: const Text('Скопировать ссылку'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Медиа ─────────────────────────────────────────────────────

class _PostMedia extends StatefulWidget {
  const _PostMedia({
    required this.post,
    this.onTap,
    this.onDoubleTap,
  });

  final PostEntity post;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  @override
  State<_PostMedia> createState() => _PostMediaState();
}

class _PostMediaState extends State<_PostMedia> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final post = widget.post;

    // Видео — показываем превью с иконкой play
    if (post.videoUrl != null) {
      return _VideoThumbnail(
        imageUrl: post.imageUrl,
        onTap: widget.onTap,
      );
    }

    final images = post.displayImageUrls;
    if (images.isEmpty) return const SizedBox.shrink();

    // Одно фото
    if (images.length == 1) {
      return DoubleTapLikeBurst(
        onDoubleTapLike: widget.onDoubleTap ?? () {},
        child: GestureDetector(
          onTap: widget.onTap,
          child: AspectRatio(
            aspectRatio: 1,
            child: CachedNetworkImage(
              imageUrl: images.first,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  const ColoredBox(color: Color(0xFFEEEEEE)),
              errorWidget: (_, __, ___) => const ColoredBox(
                color: Color(0xFFEEEEEE),
                child: Icon(Icons.broken_image_outlined,
                    color: Colors.grey, size: 40),
              ),
            ),
          ),
        ),
      );
    }

    // Галерея фото
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: PageView.builder(
            itemCount: images.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) => DoubleTapLikeBurst(
              onDoubleTapLike: widget.onDoubleTap ?? () {},
              child: GestureDetector(
                onTap: widget.onTap,
                child: CachedNetworkImage(
                  imageUrl: images[i],
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      const ColoredBox(color: Color(0xFFEEEEEE)),
                  errorWidget: (_, __, ___) => const ColoredBox(
                    color: Color(0xFFEEEEEE),
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.grey, size: 40),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Точки-индикаторы (только если > 1 фото)
        if (images.length > 1)
          Positioned(
            bottom: 10,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                images.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  width: _currentIndex == i ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _currentIndex == i
                        ? Colors.white
                        : Colors.white54,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        // Счётчик фотографий в правом верхнем углу
        Positioned(
          top: 10,
          right: 10,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_currentIndex + 1}/${images.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoThumbnail extends StatelessWidget {
  const _VideoThumbnail({
    required this.imageUrl,
    this.onTap,
  });

  final String imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Постер
            imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        const ColoredBox(color: Color(0xFF1A1A1A)),
                  )
                : const ColoredBox(color: Color(0xFF1A1A1A)),

            // Иконка видео по центру
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 42,
                ),
              ),
            ),

            // Метка «Видео» в углу
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_rounded,
                        color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Видео',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Кнопки действий ───────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.post,
    required this.currentUserId,
    required this.onLike,
    required this.onComment,
    required this.onRepost,
    required this.onSave,
  });

  final PostEntity post;
  final String? currentUserId;
  final VoidCallback? onLike;
  final VoidCallback onComment;
  final VoidCallback? onRepost;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          // Лайк
          _ActionButton(
            icon: post.isLikedByMe
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: post.isLikedByMe
                ? Colors.red
                : Theme.of(context).colorScheme.onSurface,
            onTap: currentUserId != null ? onLike : null,
          ),

          // Комментарий
          _ActionButton(
            icon: Icons.chat_bubble_outline_rounded,
            color: Theme.of(context).colorScheme.onSurface,
            onTap: onComment,
          ),

          // Репост
          _ActionButton(
            icon: post.isRepostedByMe
                ? Icons.repeat_rounded
                : Icons.repeat_outlined,
            color: post.isRepostedByMe
                ? Colors.green
                : Theme.of(context).colorScheme.onSurface,
            onTap: currentUserId != null ? onRepost : null,
          ),

          const Spacer(),

          // Сохранить
          _ActionButton(
            icon: post.isSavedByMe
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            color: post.isSavedByMe
                ? Colors.amber
                : Theme.of(context).colorScheme.onSurface,
            onTap: currentUserId != null ? onSave : null,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color, size: 26),
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}

// ── Caption и метки ───────────────────────────────────────────

class _LikesLabel extends StatelessWidget {
  const _LikesLabel({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Text(
        '$count ${_pluralLikes(count)}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  String _pluralLikes(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'лайк';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return 'лайка';
    }
    return 'лайков';
  }
}

class _CaptionLine extends StatefulWidget {
  const _CaptionLine({required this.post});
  final PostEntity post;

  @override
  State<_CaptionLine> createState() => _CaptionLineState();
}

class _CaptionLineState extends State<_CaptionLine> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '${widget.post.userName ?? 'Пользователь'}  ',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                ),
              ),
              TextSpan(
                text: widget.post.caption,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          maxLines: _expanded ? null : 2,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _CommentHint extends StatelessWidget {
  const _CommentHint({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        child: Text(
          'Смотреть все комментарии ($count)',
          style: TextStyle(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
