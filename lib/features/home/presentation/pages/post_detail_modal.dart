import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/entities/post_comment_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../widgets/user_avatar_tap.dart';
import '../widgets/feed_video_player.dart';

/// Полноэкранный просмотр поста (аналог нажатия на пост в Instagram).
///
/// Открывается как DraggableScrollableSheet поверх ленты.
///
/// Пример использования:
/// ```dart
/// PostDetailModal.show(context, post: post, repository: repo, currentUserId: id);
/// ```
class PostDetailModal extends StatefulWidget {
  const PostDetailModal({
    super.key,
    required this.post,
    required this.repository,
    this.currentUserId,
  });

  final PostEntity post;
  final PostRepository repository;
  final String? currentUserId;

  /// Удобный метод для показа модала.
  static Future<void> show(
    BuildContext context, {
    required PostEntity post,
    required PostRepository repository,
    String? currentUserId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PostDetailModal(
        post: post,
        repository: repository,
        currentUserId: currentUserId,
      ),
    );
  }

  @override
  State<PostDetailModal> createState() => _PostDetailModalState();
}

class _PostDetailModalState extends State<PostDetailModal> {
  late PostEntity _post;
  List<PostCommentEntity> _comments = [];
  bool _loadingComments = true;
  final TextEditingController _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _loadComments();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final list = await widget.repository.getComments(_post.id);
      if (!mounted) return;
      setState(() {
        _comments = list;
        _loadingComments = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  Future<void> _toggleLike() async {
    if (widget.currentUserId == null) return;
    try {
      await widget.repository.toggleLike(_post.id, widget.currentUserId!);
      if (!mounted) return;
      setState(() {
        _post = _post.copyWith(
          isLikedByMe: !_post.isLikedByMe,
          likesCount: _post.isLikedByMe
              ? (_post.likesCount - 1).clamp(0, 9999999)
              : _post.likesCount + 1,
        );
      });
    } catch (e) { debugPrint('$e'); }
  }

  Future<void> _toggleSave() async {
    if (widget.currentUserId == null) return;
    try {
      await widget.repository.toggleSave(_post.id, widget.currentUserId!);
      if (!mounted) return;
      setState(() => _post = _post.copyWith(isSavedByMe: !_post.isSavedByMe));
    } catch (e) { debugPrint('$e'); }
  }

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || widget.currentUserId == null || _submitting) return;

    setState(() => _submitting = true);
    try {
      await widget.repository.addComment(
        postId: _post.id,
        userId: widget.currentUserId!,
        text: text,
      );
      _commentCtrl.clear();
      await _loadComments();
    } catch (e) { debugPrint('$e'); } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      expand: false,
      builder: (_, scrollController) {
        return ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: Column(
              children: [
                // Drag handle
                const _DragHandle(),

                Expanded(
                  child: CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      // Шапка: автор + follow кнопка
                      SliverToBoxAdapter(
                        child: _PostHeader(
                          post: _post,
                          currentUserId: widget.currentUserId,
                        ),
                      ),

                      // Медиа: фото/видео
                      SliverToBoxAdapter(
                        child: _PostMedia(
                          post: _post,
                          maxHeight: screenH * 0.55,
                        ),
                      ),

                      // Кнопки действий
                      SliverToBoxAdapter(
                        child: _ActionBar(
                          post: _post,
                          currentUserId: widget.currentUserId,
                          onLike: _toggleLike,
                          onSave: _toggleSave,
                          onComment: () {},
                        ),
                      ),

                      // Caption
                      if (_post.caption.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _Caption(
                            post: _post,
                          ),
                        ),

                      // Комментарии
                      SliverToBoxAdapter(
                        child: _CommentsSection(
                          comments: _comments,
                          loading: _loadingComments,
                          currentUserId: widget.currentUserId,
                          repository: widget.repository,
                        ),
                      ),

                      // Отступ снизу для поля ввода
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 80),
                      ),
                    ],
                  ),
                ),

                // Поле ввода комментария
                if (widget.currentUserId != null)
                  _CommentInput(
                    controller: _commentCtrl,
                    submitting: _submitting,
                    onSubmit: _submitComment,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Шапка поста ───────────────────────────────────────────────

class _PostHeader extends StatelessWidget {
  const _PostHeader({required this.post, required this.currentUserId});

  final PostEntity post;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          UserAvatarTap(
            userId: post.userId,
            avatarUrl: post.userAvatarUrl,
            radius: 18,
            currentUserId: currentUserId,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: UsernameTap(
              userId: post.userId,
              username: post.userName ?? 'Пользователь',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          // Кнопка закрытия
          IconButton(
            icon: const Icon(Icons.close_rounded),
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

// ── Медиа ─────────────────────────────────────────────────────

class _PostMedia extends StatefulWidget {
  const _PostMedia({required this.post, required this.maxHeight});

  final PostEntity post;
  final double maxHeight;

  @override
  State<_PostMedia> createState() => _PostMediaState();
}

class _PostMediaState extends State<_PostMedia> {
  final ValueNotifier<int> _currentImage = ValueNotifier<int>(0);

  @override
  void dispose() {
    _currentImage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;

    // Видео
    if (post.videoUrl != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: FeedVideoPlayer(
          videoUrl: post.videoUrl!,
          isActive: true,
          aspectRatio: 1.0,
          looping: true,
        ),
      );
    }

    final images = post.displayImageUrls;
    if (images.isEmpty) return const SizedBox.shrink();

    // Одно фото
    if (images.length == 1) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: CachedNetworkImage(
          imageUrl: images.first,
          fit: BoxFit.contain,
          width: double.infinity,
          placeholder: (_, unused) => const _ImageShimmer(),
          errorWidget: (_, unused, error) => const _ImageError(),
        ),
      );
    }

    // Галерея фото
    return SizedBox(
      height: widget.maxHeight,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          PageView.builder(
            itemCount: images.length,
            onPageChanged: (i) => _currentImage.value = i,
            itemBuilder: (_, i) => CachedNetworkImage(
              imageUrl: images[i],
              fit: BoxFit.contain,
              width: double.infinity,
              placeholder: (_, unused) => const _ImageShimmer(),
              errorWidget: (_, unused, error) => const _ImageError(),
            ),
          ),
          // Индикаторы точек — перестраиваются только они, не весь виджет
          Positioned(
            bottom: 8,
            child: ValueListenableBuilder<int>(
              valueListenable: _currentImage,
              builder: (_, current, unused) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  images.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: current == i ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: current == i ? Colors.white : Colors.white54,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Кнопки действий ───────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.post,
    required this.currentUserId,
    required this.onLike,
    required this.onSave,
    required this.onComment,
  });

  final PostEntity post;
  final String? currentUserId;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Лайк
          _IconAction(
            icon: post.isLikedByMe
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: post.isLikedByMe
                ? Colors.red
                : Theme.of(context).colorScheme.onSurface,
            count: post.likesCount,
            onTap: currentUserId != null ? onLike : null,
          ),
          const SizedBox(width: 4),

          // Комментарий
          _IconAction(
            icon: Icons.chat_bubble_outline_rounded,
            color: Theme.of(context).colorScheme.onSurface,
            count: post.commentsCount,
            onTap: onComment,
          ),
          const SizedBox(width: 4),

          // Репост
          _IconAction(
            icon: post.isRepostedByMe
                ? Icons.repeat_rounded
                : Icons.repeat_outlined,
            color: post.isRepostedByMe
                ? Colors.green
                : Theme.of(context).colorScheme.onSurface,
            count: post.repostsCount,
            onTap: null,
          ),

          const Spacer(),

          // Сохранить
          _IconAction(
            icon: post.isSavedByMe
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            color: post.isSavedByMe
                ? Colors.amber
                : Theme.of(context).colorScheme.onSurface,
            count: 0,
            onTap: currentUserId != null ? onSave : null,
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.color,
    required this.count,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                _fmt(count),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ── Caption ───────────────────────────────────────────────────

class _Caption extends StatefulWidget {
  const _Caption({required this.post});
  final PostEntity post;

  @override
  State<_Caption> createState() => _CaptionState();
}

class _CaptionState extends State<_Caption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
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

// ── Комментарии ───────────────────────────────────────────────

class _CommentsSection extends StatelessWidget {
  const _CommentsSection({
    required this.comments,
    required this.loading,
    required this.currentUserId,
    required this.repository,
  });

  final List<PostCommentEntity> comments;
  final bool loading;
  final String? currentUserId;
  final PostRepository repository;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (comments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Нет комментариев',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            'Комментарии',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        ...comments.map(
          (c) => _CommentTile(comment: c, currentUserId: currentUserId),
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.currentUserId,
  });

  final PostCommentEntity comment;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatarTap(
            userId: comment.userId,
            avatarUrl: comment.userAvatarUrl,
            radius: 15,
            currentUserId: currentUserId,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  overflow: TextOverflow.ellipsis,
                  maxLines: 6,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '${comment.userName ?? 'Пользователь'}  ',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 13,
                        ),
                      ),
                      TextSpan(
                        text: comment.text,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _timeAgo(comment.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
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
    return '${(diff.inDays / 7).floor()} нед';
  }
}

// ── Поле ввода комментария ────────────────────────────────────

class _CommentInput extends StatelessWidget {
  const _CommentInput({
    required this.controller,
    required this.submitting,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSubmit(),
                decoration: InputDecoration(
                  hintText: 'Добавить комментарий...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            submitting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.send_rounded),
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: onSubmit,
                  ),
          ],
        ),
      ),
    );
  }
}

// ── Вспомогательные виджеты ───────────────────────────────────

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _ImageShimmer extends StatelessWidget {
  const _ImageShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(color: Colors.grey.shade200);
  }
}

class _ImageError extends StatelessWidget {
  const _ImageError();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFEEEEEE),
      child: Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 40),
      ),
    );
  }
}
