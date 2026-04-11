import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/auth/show_login_prompt.dart';
import '../../../../core/following/following_change_bus.dart';
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
  bool _didInitialFetch = false;
  String? _error;
  int _dbOffset = 0;
  _PublicationPageChunk? _prefetchedNextPage;
  bool _prefetching = false;

  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 12;
  static const Duration _warmCacheTtl = Duration(minutes: 3);
  static _PublicationFeedWarmCache? _warmCache;

  StreamSubscription<void>? _followingChangeSub;

  String? get _currentUserId {
    final state = context.read<AuthBloc>().state;
    if (state is AuthAuthenticated) return state.user.id;
    return Supabase.instance.client.auth.currentUser?.id;
  }

  PostRepository get _postRepo => context.read<PostRepository>();

  @override
  bool get wantKeepAlive => true; // Сохраняем позицию скролла

  @override
  void initState() {
    super.initState();
    _followingChangeSub =
        FollowingChangeBus.instance.stream.listen((_) {
      if (!mounted) return;
      unawaited(_reconcileFollowFlagsFromServer());
    });
    final cache = _warmCache;
    final uid = _currentUserId ?? '';
    if (cache != null &&
        cache.userId == uid &&
        DateTime.now().difference(cache.createdAt) <= _warmCacheTtl) {
      _posts = List<PostEntity>.from(cache.posts);
      _dbOffset = cache.dbOffset;
      _hasMore = cache.hasMore;
      _loading = false;
      _didInitialFetch = true;
    }
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load(showLoader: _posts.isEmpty);
    });
  }

  @override
  void dispose() {
    _followingChangeSub?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  // ── Скролл до конца → подгружаем ───────────────────────────
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent * 0.7) {
      _schedulePrefetchIfNeeded();
    }
    if (position.pixels >= position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  // ── Первая загрузка ────────────────────────────────────────
  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      _error = null;
    }
    try {
      final page = await _fetchPublicationPage(
        offset: 0,
        targetCount: _pageSize,
      );
      if (!mounted) return;
      _warmCache = _PublicationFeedWarmCache(
        createdAt: DateTime.now(),
        userId: _currentUserId ?? '',
        posts: page.posts,
        dbOffset: page.nextOffset,
        hasMore: page.hasMore,
      );
      setState(() {
        _posts = page.posts;
        _dbOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _loading = false;
        _didInitialFetch = true;
      });
      _schedulePrefetchIfNeeded();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _didInitialFetch = true;
      });
    }
  }

  Future<_PublicationPageChunk> _fetchPublicationPage({
    required int offset,
    required int targetCount,
  }) async {
    final collected = <PostEntity>[];
    var nextOffset = offset;
    var hasMoreRaw = true;
    var attempts = 0;

    while (collected.length < targetCount && hasMoreRaw && attempts < 4) {
      attempts++;
      final batch = await _postRepo.getFeedPosts(
        limit: _pageSize,
        offset: nextOffset,
        currentUserId: _currentUserId,
        excludeVideoPublications: true,
      );
      final pubs = batch
          .where((p) => p.kind.trim().toLowerCase() == 'publication')
          .toList(growable: false);
      if (pubs.isNotEmpty) {
        collected.addAll(pubs);
      }
      nextOffset += batch.length;
      hasMoreRaw = batch.length >= _pageSize;
    }

    if (collected.length > targetCount) {
      collected.removeRange(targetCount, collected.length);
    }

    return _PublicationPageChunk(
      posts: collected,
      nextOffset: nextOffset,
      hasMore: hasMoreRaw,
    );
  }

  // ── Пагинация ──────────────────────────────────────────────
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final page = _prefetchedNextPage != null && _prefetchedNextPage!.nextOffset > _dbOffset
          ? _prefetchedNextPage!
          : await _fetchPublicationPage(
              offset: _dbOffset,
              targetCount: _pageSize,
            );
      _prefetchedNextPage = null;

      final existingIds = _posts.map((p) => p.id).toSet();
      final newPosts =
          page.posts.where((p) => !existingIds.contains(p.id)).toList();

      if (!mounted) return;
      final merged = [..._posts, ...newPosts];
      _warmCache = _PublicationFeedWarmCache(
        createdAt: DateTime.now(),
        userId: _currentUserId ?? '',
        posts: merged,
        dbOffset: page.nextOffset,
        hasMore: page.hasMore,
      );
      setState(() {
        _posts = merged;
        _dbOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
      _schedulePrefetchIfNeeded();
    } catch (e) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _schedulePrefetchIfNeeded() {
    if (_prefetching || !_hasMore || _loading || _loadingMore) return;
    _prefetching = true;
    Future<void>.microtask(() async {
      try {
        final page = await _fetchPublicationPage(
          offset: _dbOffset,
          targetCount: _pageSize,
        );
        if (!mounted) return;
        if (page.posts.isEmpty) return;
        _prefetchedNextPage = page;
      } catch (e) {
        // Prefetch must never break visible feed rendering.
      } finally {
        _prefetching = false;
      }
    });
  }

  // ── Оптимистичные обновления ───────────────────────────────
  Future<void> _toggleLike(PostEntity post) async {
    final uid = _currentUserId;
    if (uid == null) {
      await showLoginRequiredDialog(
        context,
        message: 'Войдите в аккаунт, чтобы ставить лайки.',
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
    } catch (e) {
      // Откатываем при ошибке
      _updatePost(post);
    }
  }

  Future<void> _toggleSave(PostEntity post) async {
    final uid = _currentUserId;
    if (uid == null) {
      await showLoginRequiredDialog(
        context,
        message: 'Войдите в аккаунт, чтобы сохранять публикации.',
      );
      return;
    }
    _updatePost(post.copyWith(isSavedByMe: !post.isSavedByMe));
    try {
      await _postRepo.toggleSave(post.id, uid);
    } catch (e) {
      _updatePost(post);
    }
  }

  Future<void> _toggleRepost(PostEntity post) async {
    final uid = _currentUserId;
    if (uid == null) {
      await showLoginRequiredDialog(
        context,
        message: 'Войдите в аккаунт, чтобы сделать репост.',
      );
      return;
    }
    _updatePost(post.copyWith(
      isRepostedByMe: !post.isRepostedByMe,
      repostsCount: post.isRepostedByMe
          ? (post.repostsCount - 1).clamp(0, 9999999)
          : post.repostsCount + 1,
    ));
    try {
      await _postRepo.toggleRepost(post.id, uid);
    } catch (e) {
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

  void _hidePost(PostEntity post) {
    if (!mounted) return;
    setState(() {
      _posts = _posts.where((p) => p.id != post.id).toList(growable: false);
    });
  }

  Future<void> _reconcileFollowFlagsFromServer() async {
    final uid = _currentUserId;
    if (uid == null) return;
    try {
      final following =
          await context.read<ProfileRepository>().getFollowingUsers(uid);
      final set = following.map((p) => p.id).toSet();
      if (!mounted) return;
      setState(() {
        _posts = _posts
            .map((p) {
              if (p.userId == uid) return p;
              final should = set.contains(p.userId);
              if (p.isFollowingAuthor == should) return p;
              return p.copyWith(isFollowingAuthor: should);
            })
            .toList(growable: false);
      });
    } catch (e) { debugPrint('$e'); }
  }

  // ── Follow ─────────────────────────────────────────────────
  Future<void> _toggleFollow(PostEntity post) async {
    final uid = _currentUserId;
    if (uid == null || uid == post.userId) return;
    final prev = post.isFollowingAuthor;
    _updatePost(post.copyWith(isFollowingAuthor: !prev));
    try {
      final profileRepo = context.read<ProfileRepository>();
      await profileRepo.toggleFollow(uid, post.userId);
    } catch (e) {
      _updatePost(post.copyWith(isFollowingAuthor: prev));
    }
  }

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin

    if (_loading) return const _FeedSkeleton();
    if (_error != null) {
      return AppErrorView(message: _error!, onRetry: _load);
    }
    if (_posts.isEmpty && _didInitialFetch) return const _EmptyFeed();

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
            onHide: () => _hidePost(post),
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
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (_, index) => const _PostSkeleton(),
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
                  .withValues(alpha: 0.3),
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
                        .withValues(alpha: 0.5),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicationPageChunk {
  const _PublicationPageChunk({
    required this.posts,
    required this.nextOffset,
    required this.hasMore,
  });

  final List<PostEntity> posts;
  final int nextOffset;
  final bool hasMore;
}

class _PublicationFeedWarmCache {
  const _PublicationFeedWarmCache({
    required this.createdAt,
    required this.userId,
    required this.posts,
    required this.dbOffset,
    required this.hasMore,
  });

  final DateTime createdAt;
  final String userId;
  final List<PostEntity> posts;
  final int dbOffset;
  final bool hasMore;
}
