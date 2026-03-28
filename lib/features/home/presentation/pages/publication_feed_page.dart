import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/app_error_view.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../profile/domain/repositories/profile_repository.dart';
import '../widgets/publication_feed_post_item.dart';

/// Лента публикаций в стиле Instagram.
///
/// Вставляй как вкладку/страницу в TabBarView или как отдельный роут.
/// Требует PostRepository и ProfileRepository в дереве провайдеров.
///
/// ```dart
/// BlocProvider(
///   create: (_) => PublicationFeedCubit(
///     postRepository: context.read<PostRepository>(),
///     profileRepository: context.read<ProfileRepository>(),
///   )..load(currentUserId),
///   child: const PublicationFeedPage(),
/// )
/// ```
class PublicationFeedPage extends StatefulWidget {
  const PublicationFeedPage({
    super.key,
    this.showAppBar = true,
  });

  /// Показывать ли встроенный AppBar.
  final bool showAppBar;

  @override
  State<PublicationFeedPage> createState() => _PublicationFeedPageState();
}

class _PublicationFeedPageState extends State<PublicationFeedPage>
    with AutomaticKeepAliveClientMixin {
  // ── Состояние ──────────────────────────────────────────────
  List<PostEntity> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 12;

  String? get _currentUserId {
    final state = context.read<AuthBloc>().state;
    return state is AuthAuthenticated ? state.user.id : null;
  }

  PostRepository get _postRepo => context.read<PostRepository>();

  @override
  bool get wantKeepAlive => true; // Сохраняем позицию скролла

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  // ── Скролл до конца → подгружаем ───────────────────────────
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  // ── Первая загрузка ────────────────────────────────────────
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final posts = await _postRepo.getFeedPosts(
        limit: _pageSize,
        offset: 0,
        currentUserId: _currentUserId,
      );
      // Только публикации (не новости)
      final pubs = posts
          .where((p) => p.kind.trim().toLowerCase() == 'publication')
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _posts = pubs;
        _hasMore = posts.length >= _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── Пагинация ──────────────────────────────────────────────
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final more = await _postRepo.getFeedPosts(
        limit: _pageSize,
        offset: _posts.length,
        currentUserId: _currentUserId,
      );
      final pubs = more
          .where((p) => p.kind.trim().toLowerCase() == 'publication')
          .toList(growable: false);

      final existingIds = _posts.map((p) => p.id).toSet();
      final newPosts =
          pubs.where((p) => !existingIds.contains(p.id)).toList();

      if (!mounted) return;
      setState(() {
        _posts = [..._posts, ...newPosts];
        _hasMore = more.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ── Оптимистичные обновления ───────────────────────────────
  Future<void> _toggleLike(PostEntity post) async {
    final uid = _currentUserId;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы ставить лайки')),
      );
      return;
    }
    // Оптимистично обновляем UI немедленно
    _updatePost(post.copyWith(
      isLikedByMe: !post.isLikedByMe,
      likesCount: post.isLikedByMe
          ? (post.likesCount - 1).clamp(0, 9999999)
          : post.likesCount + 1,
    ));
    // Записываем в БД в фоне
    try {
      await _postRepo.toggleLike(post.id, uid);
    } catch (_) {
      // Откатываем при ошибке
      _updatePost(post);
    }
  }

  Future<void> _toggleSave(PostEntity post) async {
    final uid = _currentUserId;
    if (uid == null) return;
    _updatePost(post.copyWith(isSavedByMe: !post.isSavedByMe));
    try {
      await _postRepo.toggleSave(post.id, uid);
    } catch (_) {
      _updatePost(post);
    }
  }

  Future<void> _toggleRepost(PostEntity post) async {
    final uid = _currentUserId;
    if (uid == null) return;
    _updatePost(post.copyWith(
      isRepostedByMe: !post.isRepostedByMe,
      repostsCount: post.isRepostedByMe
          ? (post.repostsCount - 1).clamp(0, 9999999)
          : post.repostsCount + 1,
    ));
    try {
      await _postRepo.toggleRepost(post.id, uid);
    } catch (_) {
      _updatePost(post);
    }
  }

  void _updatePost(PostEntity updated) {
    if (!mounted) return;
    setState(() {
      final idx = _posts.indexWhere((p) => p.id == updated.id);
      if (idx >= 0) {
        final copy = List.of(_posts);
        copy[idx] = updated;
        _posts = copy;
      }
    });
  }

  // ── Follow ─────────────────────────────────────────────────
  Future<void> _toggleFollow(PostEntity post) async {
    final uid = _currentUserId;
    if (uid == null || uid == post.userId) return;
    try {
      final profileRepo = context.read<ProfileRepository>();
      await profileRepo.toggleFollow(uid, post.userId);
    } catch (_) {}
  }

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin

    if (_loading) return const _FeedSkeleton();
    if (_error != null) {
      return AppErrorView(message: _error!, onRetry: _load);
    }
    if (_posts.isEmpty) return const _EmptyFeed();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scrollController,
        cacheExtent: 1200, // Предзагружаем ~2 поста вперёд
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _posts.length + 1,
        itemBuilder: (context, index) {
          // Последний элемент — индикатор загрузки
          if (index == _posts.length) {
            return _loadingMore
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : const SizedBox.shrink();
          }

          final post = _posts[index];
          // RepaintBoundary внутри PublicationFeedPostItem —
          // изолирует перерисовку каждого поста
          return PublicationFeedPostItem(
            key: ValueKey(post.id), // для правильного rebuild
            post: post,
            allPosts: _posts,
            postRepository: _postRepo,
            currentUserId: _currentUserId,
            onLike: () => _toggleLike(post),
            onSave: () => _toggleSave(post),
            onRepost: () => _toggleRepost(post),
            onFollow: _currentUserId != null &&
                    _currentUserId != post.userId
                ? () => _toggleFollow(post)
                : null,
          );
        },
      ),
    );
  }
}

// ── Скелетон загрузки ─────────────────────────────────────────

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, __) => const _PostSkeleton(),
    );
  }
}

class _PostSkeleton extends StatelessWidget {
  const _PostSkeleton();

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Шапка
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _Shimmer(width: 36, height: 36, radius: 18, color: base),
              const SizedBox(width: 10),
              _Shimmer(width: 120, height: 12, radius: 6, color: base),
            ],
          ),
        ),
        // Медиа
        _Shimmer(
          width: double.infinity,
          height: MediaQuery.of(context).size.width,
          radius: 0,
          color: base,
        ),
        // Кнопки
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              _Shimmer(width: 28, height: 28, radius: 6, color: base),
              const SizedBox(width: 8),
              _Shimmer(width: 28, height: 28, radius: 6, color: base),
              const SizedBox(width: 8),
              _Shimmer(width: 28, height: 28, radius: 6, color: base),
            ],
          ),
        ),
        // Caption
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: _Shimmer(width: 200, height: 12, radius: 6, color: base),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _Shimmer(width: 140, height: 11, radius: 6, color: base),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _Shimmer extends StatelessWidget {
  const _Shimmer({
    required this.width,
    required this.height,
    required this.radius,
    required this.color,
  });

  final double width;
  final double height;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ── Пустая лента ──────────────────────────────────────────────

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_camera_outlined,
              size: 72,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withOpacity(0.3),
            ),
            const SizedBox(height: 20),
            Text(
              'Публикаций пока нет',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Подпишитесь на авторов или создайте\nпервую публикацию',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.5),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
