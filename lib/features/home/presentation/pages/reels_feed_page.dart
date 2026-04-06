import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:tmr_tau/core/formatting/compact_count_format.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../widgets/feed_video_player.dart';
import '../widgets/user_avatar_tap.dart';
import '../widgets/vertical_snap_page_scroll_physics.dart';

/// Встроенная вкладка Reels — вертикальный бесконечный видео-фид в стиле Instagram.
/// Используется как первая вкладка в [MainHomePage].
class ReelsFeedPage extends StatefulWidget {
  const ReelsFeedPage({super.key});

  @override
  State<ReelsFeedPage> createState() => _ReelsFeedPageState();
}

class _ReelsFeedPageState extends State<ReelsFeedPage>
    with AutomaticKeepAliveClientMixin {
  static const int _pageSize = 10;
  static const int _loadThreshold = 3;

  late final PageController _pageController;
  final List<PostEntity> _posts = [];
  int _currentPage = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  String? _currentUserId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    final authState = context.read<AuthBloc>().state;
    _currentUserId =
        authState is AuthAuthenticated ? authState.user.id : null;
    _loadInitial();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    try {
      final repo = context.read<PostRepository>();
      final raw = await repo.getFeedPosts(
        limit: _pageSize,
        offset: 0,
        currentUserId: _currentUserId,
      );
      final videos = raw.where((p) => p.videoUrl != null).toList();
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(videos);
        _hasMore = raw.length >= _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final repo = context.read<PostRepository>();
      final existingIds = _posts.map((p) => p.id).toSet();
      final raw = await repo.getFeedPosts(
        limit: _pageSize,
        offset: _posts.length,
        currentUserId: _currentUserId,
      );
      final newVideos = raw
          .where((p) => p.videoUrl != null && !existingIds.contains(p.id))
          .toList();
      if (!mounted) return;
      setState(() {
        _posts.addAll(newVideos);
        _hasMore = raw.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    if (index >= _posts.length - _loadThreshold) _loadMore();
  }

  Future<void> _toggleLike(int index) async {
    if (_currentUserId == null) return;
    final post = _posts[index];
    try {
      await context
          .read<PostRepository>()
          .toggleLike(post.id, _currentUserId!);
      if (!mounted) return;
      setState(() {
        _posts[index] = post.copyWith(
          isLikedByMe: !post.isLikedByMe,
          likesCount: post.isLikedByMe
              ? (post.likesCount - 1).clamp(0, 9999999)
              : post.likesCount + 1,
        );
      });
    } catch (e) {
      debugPrint('$e');
    }
  }

  Future<void> _toggleRepost(int index) async {
    if (_currentUserId == null) return;
    final post = _posts[index];
    try {
      await context
          .read<PostRepository>()
          .toggleRepost(post.id, _currentUserId!);
      if (!mounted) return;
      setState(() {
        _posts[index] = post.copyWith(
          isRepostedByMe: !post.isRepostedByMe,
          repostsCount: post.isRepostedByMe
              ? (post.repostsCount - 1).clamp(0, 9999999)
              : post.repostsCount + 1,
        );
      });
    } catch (e) {
      debugPrint('$e');
    }
  }

  Future<void> _toggleSave(int index) async {
    if (_currentUserId == null) return;
    final post = _posts[index];
    try {
      await context
          .read<PostRepository>()
          .toggleSave(post.id, _currentUserId!);
      if (!mounted) return;
      setState(() {
        _posts[index] = post.copyWith(isSavedByMe: !post.isSavedByMe);
      });
    } catch (e) {
      debugPrint('$e');
    }
  }

  void _showMoreMenu(int index) {
    final post = _posts[index];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReelsMoreMenu(
        isSaved: post.isSavedByMe,
        onSave: () {
          Navigator.pop(context);
          _toggleSave(index);
        },
        onReport: () {
          Navigator.pop(context);
          context.push('/report-post/${post.id}');
        },
        onUseSound: () {
          Navigator.pop(context);
          // Переход на создание видео с этим треком (будущая фича)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Скоро: снять видео под этот звук')),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Нет видео', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadInitial,
              child: const Text('Обновить'),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        onPageChanged: _onPageChanged,
        physics: const VerticalSnapPageScrollPhysics(),
        itemCount: _posts.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _posts.length) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white54),
            );
          }
          final post = _posts[index];
          return _ReelItem(
            key: ValueKey(post.id),
            post: post,
            isActive: _currentPage == index,
            currentUserId: _currentUserId,
            onLike: () => _toggleLike(index),
            onRepost: () => _toggleRepost(index),
            onMoreTap: () => _showMoreMenu(index),
          );
        },
      ),
    );
  }
}

// ── Один рил (одна страница видео) ──────────────────────────────

class _ReelItem extends StatelessWidget {
  const _ReelItem({
    super.key,
    required this.post,
    required this.isActive,
    required this.currentUserId,
    required this.onLike,
    required this.onRepost,
    required this.onMoreTap,
  });

  final PostEntity post;
  final bool isActive;
  final String? currentUserId;
  final VoidCallback onLike;
  final VoidCallback onRepost;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: FeedVideoPlayer(
            videoUrl: post.videoUrl!,
            isActive: isActive,
            looping: true,
            showControls: true,
            coverFullscreen: true,
          ),
        ),

        // Нижний градиент
        const Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 240,
          child: _BottomGradient(),
        ),

        // Правая панель действий
        Positioned(
          right: 12,
          bottom: 96,
          child: _ReelRightActions(
            post: post,
            currentUserId: currentUserId,
            onLike: onLike,
            onRepost: onRepost,
            onMoreTap: onMoreTap,
          ),
        ),

        // Автор + caption + просмотры
        Positioned(
          left: 14,
          right: 80,
          bottom: MediaQuery.of(context).padding.bottom + 20,
          child: _ReelBottomInfo(post: post),
        ),
      ],
    );
  }
}

// ── Правая панель: лайк, коммент, репост, поделиться, три точки ─

class _ReelRightActions extends StatelessWidget {
  const _ReelRightActions({
    required this.post,
    required this.currentUserId,
    required this.onLike,
    required this.onRepost,
    required this.onMoreTap,
  });

  final PostEntity post;
  final String? currentUserId;
  final VoidCallback onLike;
  final VoidCallback onRepost;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Лайк
        _ReelActionBtn(
          icon: post.isLikedByMe
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          color: post.isLikedByMe ? Colors.red : Colors.white,
          label: _fmt(post.likesCount),
          onTap: currentUserId != null ? onLike : null,
        ),
        const SizedBox(height: 20),

        // Комментарии
        _ReelActionBtn(
          icon: Icons.chat_bubble_outline_rounded,
          color: Colors.white,
          label: _fmt(post.commentsCount),
          onTap: () => context.push('/post/${post.id}', extra: post),
        ),
        const SizedBox(height: 20),

        // Репост
        _ReelActionBtn(
          icon: post.isRepostedByMe
              ? Icons.repeat_rounded
              : Icons.repeat_outlined,
          color: post.isRepostedByMe
              ? const Color(0xFF22D3EE)
              : Colors.white,
          label: _fmt(post.repostsCount),
          onTap: currentUserId != null ? onRepost : null,
        ),
        const SizedBox(height: 20),

        // Поделиться (прямая отправка в чат)
        _ReelActionBtn(
          icon: Icons.send_rounded,
          color: Colors.white,
          label: '',
          onTap: () => _shareReel(context),
        ),
        const SizedBox(height: 20),

        // Три точки
        _ReelActionBtn(
          icon: Icons.more_vert_rounded,
          color: Colors.white,
          label: '',
          onTap: onMoreTap,
        ),
      ],
    );
  }

  void _shareReel(BuildContext context) {
    // Открываем список пользователей для отправки в чат
    context.push('/discover-publications');
  }

  String _fmt(int n) {
    if (n <= 0) return '';
    return formatCompactCount(n);
  }
}

class _ReelActionBtn extends StatelessWidget {
  const _ReelActionBtn({
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
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: 32,
            shadows: const [Shadow(color: Colors.black45, blurRadius: 6)],
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Информация об авторе (левый нижний угол) ─────────────────────

class _ReelBottomInfo extends StatelessWidget {
  const _ReelBottomInfo({required this.post});

  final PostEntity post;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            UserAvatarTap(
              userId: post.userId,
              avatarUrl: post.userAvatarUrl,
              radius: 18,
            ),
            const SizedBox(width: 8),
            UsernameTap(
              userId: post.userId,
              username: post.userName ?? 'Пользователь',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ],
        ),
        if (post.caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          _ExpandableCaption(caption: post.caption),
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
              Icons.play_arrow_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 4),
            Text(
              formatCompactCount(post.viewsCount),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ],
        ),
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

// ── Нижний градиент ───────────────────────────────────────────────

class _BottomGradient extends StatelessWidget {
  const _BottomGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
    );
  }
}

// ── Меню трёх точек (bottom sheet) ───────────────────────────────

class _ReelsMoreMenu extends StatelessWidget {
  const _ReelsMoreMenu({
    required this.isSaved,
    required this.onSave,
    required this.onReport,
    required this.onUseSound,
  });

  final bool isSaved;
  final VoidCallback onSave;
  final VoidCallback onReport;
  final VoidCallback onUseSound;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _MenuItem(
            icon: isSaved
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            iconColor: isSaved ? Colors.amber.shade700 : Colors.black87,
            label: isSaved ? 'Сохранено' : 'Сохранить',
            onTap: onSave,
          ),
          _MenuItem(
            icon: Icons.music_note_rounded,
            iconColor: const Color(0xFF2563EB),
            label: 'Снять под этот звук',
            onTap: onUseSound,
          ),
          _MenuItem(
            icon: Icons.flag_outlined,
            iconColor: Colors.red,
            label: 'Пожаловаться',
            onTap: onReport,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
