import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:tmr_tau/core/formatting/compact_count_format.dart';

import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../widgets/feed_video_player.dart';
import '../widgets/user_avatar_tap.dart';

/// TikTok / Instagram Reels стиль вертикального видео-фида.
///
/// Открывается при тапе на видео-пост в ленте:
/// ```dart
/// Navigator.of(context).push(
///   MaterialPageRoute(
///     builder: (_) => VideoFeedScreen(
///       initialPost: post,
///       allPosts: videoPosts,
///       postRepository: repo,
///       currentUserId: userId,
///     ),
///   ),
/// );
/// ```
class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({
    super.key,
    required this.initialPost,
    required this.allPosts,
    required this.postRepository,
    this.currentUserId,
  });

  /// Пост с которого начинаем просмотр.
  final PostEntity initialPost;

  /// Начальный список видео-постов (должны иметь videoUrl != null).
  final List<PostEntity> allPosts;

  final PostRepository postRepository;
  final String? currentUserId;

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  late final PageController _pageController;
  late final List<PostEntity> _posts;

  int _currentPage = 0;
  bool _loadingMore = false;
  bool _hasMore = true;

  /// Количество постов от конца при котором начинаем догружать.
  static const _loadMoreThreshold = 3;
  static const _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _posts = List.of(widget.allPosts.where((p) => p.videoUrl != null));

    // Найти начальный индекс поста
    final startIndex = _posts.indexWhere((p) => p.id == widget.initialPost.id);
    _currentPage = startIndex < 0 ? 0 : startIndex;

    _pageController = PageController(initialPage: _currentPage);

    // Скрыть системный UI для full-screen эффекта
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pageController.dispose();
    // Восстановить системный UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);

    try {
      final more = await widget.postRepository.getFeedPosts(
        limit: _pageSize,
        offset: _posts.length,
        currentUserId: widget.currentUserId,
      );

      // Фильтруем только видео-посты, исключаем уже загруженные
      final existingIds = _posts.map((p) => p.id).toSet();
      final newVideos = more
          .where((p) => p.videoUrl != null && !existingIds.contains(p.id))
          .toList();

      if (!mounted) return;
      setState(() {
        _posts.addAll(newVideos);
        _hasMore = more.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);

    // Начинаем подгрузку заранее
    if (index >= _posts.length - _loadMoreThreshold) {
      _loadMore();
    }
  }

  Future<void> _toggleLike(PostEntity post) async {
    if (widget.currentUserId == null) return;
    try {
      await widget.postRepository.toggleLike(post.id, widget.currentUserId!);
      final idx = _posts.indexWhere((p) => p.id == post.id);
      if (idx < 0 || !mounted) return;
      setState(() {
        _posts[idx] = post.copyWith(
          isLikedByMe: !post.isLikedByMe,
          likesCount: post.isLikedByMe
              ? (post.likesCount - 1).clamp(0, 9999999)
              : post.likesCount + 1,
        );
      });
    } catch (e) { debugPrint('$e'); }
  }

  Future<void> _toggleSave(PostEntity post) async {
    if (widget.currentUserId == null) return;
    try {
      await widget.postRepository.toggleSave(post.id, widget.currentUserId!);
      final idx = _posts.indexWhere((p) => p.id == post.id);
      if (idx < 0 || !mounted) return;
      setState(() {
        _posts[idx] = post.copyWith(isSavedByMe: !post.isSavedByMe);
      });
    } catch (e) { debugPrint('$e'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Вертикальный PageView со snap-скроллом
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: _onPageChanged,
            physics: const _SnapPageScrollPhysics(),
            itemCount: _posts.length + (_loadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              // Последний элемент — индикатор загрузки
              if (index == _posts.length) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white54),
                );
              }

              final post = _posts[index];
              return _VideoPage(
                key: ValueKey(post.id),
                post: post,
                isActive: _currentPage == index,
                currentUserId: widget.currentUserId,
                onLike: () => _toggleLike(post),
                onSave: () => _toggleSave(post),
              );
            },
          ),

          // Кнопка «Назад»
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: _CloseButton(onTap: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    );
  }
}

// ── Отдельная страница видео ─────────────────────────────────

class _VideoPage extends StatelessWidget {
  const _VideoPage({
    super.key,
    required this.post,
    required this.isActive,
    required this.currentUserId,
    required this.onLike,
    required this.onSave,
  });

  final PostEntity post;
  final bool isActive;
  final String? currentUserId;
  final VoidCallback onLike;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Фоновый постер (пока видео грузится)
        if (post.imageUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: post.imageUrl,
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            memCacheWidth: (MediaQuery.sizeOf(context).shortestSide *
                    MediaQuery.devicePixelRatioOf(context))
                .round()
                .clamp(256, 2048),
            placeholder: (context, url) => const ColoredBox(color: Colors.black),
            errorWidget: (context, url, error) =>
                const ColoredBox(color: Colors.black),
          ),

        // Видеоплеер на весь экран
        Center(
          child: FeedVideoPlayer(
            videoUrl: post.videoUrl!,
            isActive: isActive,
            aspectRatio: 9 / 16,
            looping: true,
            showControls: true,
          ),
        ),

        // Затемнённый градиент снизу для текста
        const Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 220,
          child: _BottomGradient(),
        ),

        // Правая панель действий
        Positioned(
          right: 12,
          bottom: 100,
          child: _RightActions(
            post: post,
            currentUserId: currentUserId,
            onLike: onLike,
            onSave: onSave,
          ),
        ),

        // Информация об авторе и caption снизу слева
        Positioned(
          left: 12,
          right: 80,
          bottom: MediaQuery.of(context).padding.bottom + 24,
          child: _BottomInfo(post: post),
        ),
      ],
    );
  }
}

// ── Информация об авторе (левый нижний угол) ─────────────────

class _BottomInfo extends StatelessWidget {
  const _BottomInfo({required this.post});

  final PostEntity post;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Автор
        Row(
          children: [
            UserAvatarTap(
              userId: post.userId,
              avatarUrl: post.userAvatarUrl,
              radius: 16,
            ),
            const SizedBox(width: 8),
            UsernameTap(
              userId: post.userId,
              username: post.userName ?? 'Пользователь',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ],
        ),

        // Caption
        if (post.caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ExpandableCaption(caption: post.caption),
        ],
        if (post.videoUrl != null && post.videoUrl!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.play_arrow_rounded,
                size: 19,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Text(
                formatCompactCount(post.viewsCount),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 4),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ExpandableCaption extends StatefulWidget {
  const _ExpandableCaption({required this.caption});
  final String caption;

  @override
  State<_ExpandableCaption> createState() => _ExpandableCaptionState();
}

class _ExpandableCaptionState extends State<_ExpandableCaption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Text(
        widget.caption,
        maxLines: _expanded ? null : 2,
        overflow: _expanded ? null : TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
        ),
      ),
    );
  }
}

// ── Правая панель действий ────────────────────────────────────

class _RightActions extends StatelessWidget {
  const _RightActions({
    required this.post,
    required this.currentUserId,
    required this.onLike,
    required this.onSave,
  });

  final PostEntity post;
  final String? currentUserId;
  final VoidCallback onLike;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Лайк
        _ActionBtn(
          icon: post.isLikedByMe
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          color: post.isLikedByMe ? Colors.red : Colors.white,
          label: _formatCount(post.likesCount),
          onTap: currentUserId != null ? onLike : null,
        ),
        const SizedBox(height: 20),

        // Комментарии
        _ActionBtn(
          icon: Icons.chat_bubble_outline_rounded,
          color: Colors.white,
          label: _formatCount(post.commentsCount),
          onTap: () => context.push('/post/${post.id}', extra: post),
        ),
        const SizedBox(height: 20),

        // Сохранить
        _ActionBtn(
          icon: post.isSavedByMe
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          color: post.isSavedByMe ? Colors.amber : Colors.white,
          label: '',
          onTap: currentUserId != null ? onSave : null,
        ),
        const SizedBox(height: 20),

        // Поделиться
        _ActionBtn(
          icon: Icons.send_rounded,
          color: Colors.white,
          label: '',
          onTap: () {},
        ),
      ],
    );
  }

  String _formatCount(int n) {
    if (n == 0) return '';
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30,
              shadows: const [Shadow(color: Colors.black45, blurRadius: 4)]),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Утилиты ───────────────────────────────────────────────────

class _BottomGradient extends StatelessWidget {
  const _BottomGradient();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Colors.white, size: 20),
      ),
    );
  }
}

/// Custom scroll physics для резкого snap между страницами.
class _SnapPageScrollPhysics extends ScrollPhysics {
  const _SnapPageScrollPhysics({super.parent});

  @override
  _SnapPageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _SnapPageScrollPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring =>
      const SpringDescription(mass: 80, stiffness: 100, damping: 1);
}
