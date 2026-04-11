import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:tmr_tau/core/auth/show_login_prompt.dart';
import 'package:tmr_tau/core/following/following_change_bus.dart';
import 'package:tmr_tau/core/formatting/compact_count_format.dart';
import 'package:tmr_tau/core/widgets/double_tap_like_burst.dart';
import 'package:tmr_tau/core/widgets/cached_avatar.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../profile/domain/repositories/profile_repository.dart';
import '../widgets/feed_video_player.dart';
import '../widgets/reels_comments_sheet.dart';
import '../widgets/user_avatar_tap.dart';

/// Вкладка Reels: только видео-публикации, вертикальный свайп по одному ролику,
/// порядок «случайный» в рамках сессии, просмотр фиксируется после ~1.5 с на ролике.
class ReelsFeedPage extends StatefulWidget {
  const ReelsFeedPage({super.key});

  @override
  State<ReelsFeedPage> createState() => _ReelsFeedPageState();
}

class _ReelsFeedPageState extends State<ReelsFeedPage>
    with AutomaticKeepAliveClientMixin {
  static const int _pageSize = 15;
  static const int _loadThreshold = 4;
  static const Duration _warmCacheTtl = Duration(minutes: 45);
  static _ReelsWarmCache? _warmCache;

  late final PageController _pageController;
  final List<PostEntity> _posts = [];
  int _currentPage = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _apiOffset = 0;
  late String _sessionKey;

  String? _currentUserId;
  Timer? _viewDwellTimer;
  bool _prefetchingFirstVideo = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    final authState = context.read<AuthBloc>().state;
    _currentUserId =
        authState is AuthAuthenticated ? authState.user.id : null;
    _sessionKey =
        '${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1 << 30)}';

    final warmSnapshot = _warmCache;
    var canUseCache = false;
    if (_currentUserId != null && warmSnapshot != null) {
      final w = warmSnapshot;
      if (w.userId == _currentUserId &&
          DateTime.now().difference(w.createdAt) <= _warmCacheTtl) {
        canUseCache = true;
        _sessionKey = w.sessionKey;
        _posts.addAll(w.posts);
        _apiOffset = w.apiOffset;
        _hasMore = w.hasMore;
        _loading = false;
      }
    }

    if (canUseCache) {
      _scheduleViewDwellFor(0);
      unawaited(_prefetchFirstVideo());
      unawaited(_silentRefreshReelsFromNetwork());
    } else {
      unawaited(_loadInitial());
    }
  }

  @override
  void dispose() {
    _viewDwellTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _newSessionAndReload() {
    _warmCache = null;
    _sessionKey =
        '${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1 << 30)}';
    unawaited(_loadInitial());
  }

  void _storeReelsWarmCache() {
    final uid = _currentUserId;
    if (uid == null || _posts.isEmpty) return;
    _warmCache = _ReelsWarmCache(
      userId: uid,
      createdAt: DateTime.now(),
      sessionKey: _sessionKey,
      posts: List<PostEntity>.from(_posts),
      apiOffset: _apiOffset,
      hasMore: _hasMore,
    );
  }

  Future<void> _prefetchFirstVideo() async {
    if (_prefetchingFirstVideo) return;
    if (_posts.isEmpty) return;
    final firstUrl = _posts.first.videoUrl?.trim() ?? '';
    if (firstUrl.isEmpty) return;
    _prefetchingFirstVideo = true;
    try {
      await DefaultCacheManager().getSingleFile(firstUrl);
    } catch (_) {
      // Best effort warm-up; ignore network/cache failures.
    } finally {
      _prefetchingFirstVideo = false;
    }
  }

  Future<void> _silentRefreshReelsFromNetwork() async {
    try {
      final repo = context.read<PostRepository>();
      final list = await repo.getReelsVideoPosts(
        sessionKey: _sessionKey,
        limit: _pageSize,
        offset: 0,
        currentUserId: _currentUserId,
      );
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(list);
        _apiOffset = list.length;
        _hasMore = list.length >= _pageSize;
        if (_posts.isEmpty) {
          _currentPage = 0;
        } else {
          _currentPage = _currentPage.clamp(0, _posts.length - 1);
        }
        _loading = false;
      });
      if (_pageController.hasClients && _posts.isNotEmpty) {
        final idx = _currentPage.clamp(0, _posts.length - 1);
        _pageController.jumpToPage(idx);
      }
      _storeReelsWarmCache();
      unawaited(_prefetchFirstVideo());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_posts.isEmpty) return;
        _scheduleViewDwellFor(
          _currentPage.clamp(0, _posts.length - 1),
        );
      });
    } catch (e) {
      debugPrint('$e');
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _apiOffset = 0;
      _hasMore = true;
    });
    try {
      final repo = context.read<PostRepository>();
      final list = await repo.getReelsVideoPosts(
        sessionKey: _sessionKey,
        limit: _pageSize,
        offset: 0,
        currentUserId: _currentUserId,
      );
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(list);
        _apiOffset = list.length;
        _hasMore = list.length >= _pageSize;
        _loading = false;
        _currentPage = 0;
      });
      _storeReelsWarmCache();
      unawaited(_prefetchFirstVideo());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleViewDwellFor(0);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final repo = context.read<PostRepository>();
      final list = await repo.getReelsVideoPosts(
        sessionKey: _sessionKey,
        limit: _pageSize,
        offset: _apiOffset,
        currentUserId: _currentUserId,
      );
      if (!mounted) return;
      final existing = _posts.map((p) => p.id).toSet();
      final fresh =
          list.where((p) => !existing.contains(p.id)).toList(growable: false);
      setState(() {
        _posts.addAll(fresh);
        _apiOffset += list.length;
        _hasMore = list.length >= _pageSize;
        _loadingMore = false;
      });
      _storeReelsWarmCache();
    } catch (e) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _scheduleViewDwellFor(int index) {
    _viewDwellTimer?.cancel();
    if (_currentUserId == null) return;
    if (index < 0 || index >= _posts.length) return;
    final postId = _posts[index].id;
    _viewDwellTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      if (_currentPage != index) return;
      unawaited(
        context.read<PostRepository>().recordPublicationFeedImpression(
              postId: postId,
              watchedMsDelta: 2000,
            ),
      );
    });
  }

  void _onPageChanged(int index) {
    _scheduleViewDwellFor(index);
    setState(() => _currentPage = index);
    if (index >= _posts.length - _loadThreshold) {
      _loadMore();
    }
  }

  Future<void> _toggleLike(int index) async {
    if (_currentUserId == null) {
      await showLoginRequiredDialog(
        context,
        message: 'Войдите в аккаунт, чтобы ставить лайки.',
      );
      return;
    }
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

  Future<void> _likeFromDoubleTap(int index) async {
    if (index < 0 || index >= _posts.length) return;
    if (_posts[index].isLikedByMe) return;
    await _toggleLike(index);
  }

  Future<void> _toggleRepost(int index) async {
    if (_currentUserId == null) {
      await showLoginRequiredDialog(
        context,
        message: 'Войдите в аккаунт, чтобы сделать репост.',
      );
      return;
    }
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
    if (_currentUserId == null) {
      await showLoginRequiredDialog(
        context,
        message: 'Войдите в аккаунт, чтобы сохранять публикации.',
      );
      return;
    }
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

  Future<void> _toggleFollowAuthor(String authorId) async {
    if (_currentUserId == null) {
      await showLoginRequiredDialog(
        context,
        message: 'Войдите в аккаунт, чтобы подписаться на автора.',
      );
      return;
    }
    if (authorId == _currentUserId) return;
    try {
      await context.read<ProfileRepository>().toggleFollow(
            _currentUserId!,
            authorId,
          );
      FollowingChangeBus.instance.notify();
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _posts.length; i++) {
          if (_posts[i].userId != authorId) continue;
          final p = _posts[i];
          _posts[i] = p.copyWith(isFollowingAuthor: !p.isFollowingAuthor);
        }
      });
    } catch (e) {
      debugPrint('$e');
    }
  }

  void _applyCommentsCount(int index, int count) {
    if (index < 0 || index >= _posts.length) return;
    setState(() {
      _posts[index] = _posts[index].copyWith(commentsCount: count);
    });
  }

  void _openCommentsSheet(BuildContext context, int index) {
    final post = _posts[index];
    ReelsCommentsSheet.show(
      context,
      post: post,
      onCommentsCountChanged: (c) => _applyCommentsCount(index, c),
    );
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

    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, curr) {
        final currId = curr is AuthAuthenticated ? curr.user.id : null;
        final prevId = prev is AuthAuthenticated ? prev.user.id : null;
        if (currId == null) return prevId != null;
        if (prevId != null && prevId != currId) return true;
        if (prevId == null) {
          return prev is AuthUnauthenticated || prev is AuthError;
        }
        return false;
      },
      listener: (context, state) {
        _warmCache = null;
        _currentUserId =
            state is AuthAuthenticated ? state.user.id : null;
        _newSessionAndReload();
      },
      child: _buildReelsBody(context),
    );
  }

  Widget _buildReelsBody(BuildContext context) {
    if (_loading) {
      return const _ReelsLoadingSkeleton();
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
              onPressed: _newSessionAndReload,
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
        physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
        itemCount: _posts.length + (_loadingMore && _hasMore ? 1 : 0),
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
            onDoubleTapLike: () => _likeFromDoubleTap(index),
            onRepost: () => _toggleRepost(index),
            onCommentsTap: () => _openCommentsSheet(context, index),
            onMoreTap: () => _showMoreMenu(index),
            onFollowAuthor: () => _toggleFollowAuthor(post.userId),
          );
        },
      ),
    );
  }
}

class _ReelsWarmCache {
  const _ReelsWarmCache({
    required this.userId,
    required this.createdAt,
    required this.sessionKey,
    required this.posts,
    required this.apiOffset,
    required this.hasMore,
  });

  final String userId;
  final DateTime createdAt;
  final String sessionKey;
  final List<PostEntity> posts;
  final int apiOffset;
  final bool hasMore;
}

class _ReelsLoadingSkeleton extends StatelessWidget {
  const _ReelsLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade900,
        highlightColor: Colors.grey.shade700,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    4,
                    (_) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReelItem extends StatelessWidget {
  const _ReelItem({
    super.key,
    required this.post,
    required this.isActive,
    required this.currentUserId,
    required this.onLike,
    required this.onDoubleTapLike,
    required this.onRepost,
    required this.onCommentsTap,
    required this.onMoreTap,
    required this.onFollowAuthor,
  });

  final PostEntity post;
  final bool isActive;
  final String? currentUserId;
  final VoidCallback onLike;
  final VoidCallback onDoubleTapLike;
  final VoidCallback onRepost;
  final VoidCallback onCommentsTap;
  final VoidCallback onMoreTap;
  final VoidCallback onFollowAuthor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: DoubleTapLikeBurst(
            onDoubleTapLike: onDoubleTapLike,
            shouldTriggerLike: () => !post.isLikedByMe,
            showPersistentLikeIndicator: true,
            isLiked: post.isLikedByMe,
            child: FeedVideoPlayer(
              videoUrl: post.videoUrl!,
              musicPreviewUrl: post.musicPreviewUrl,
              isActive: isActive,
              looping: true,
              showControls: true,
              coverFullscreen: true,
            ),
          ),
        ),
        const Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 240,
          child: _BottomGradient(),
        ),
        Positioned(
          right: 10,
          bottom: 96,
          child: _ReelRightActions(
            post: post,
            currentUserId: currentUserId,
            onLike: onLike,
            onRepost: onRepost,
            onCommentsTap: onCommentsTap,
            onMoreTap: onMoreTap,
            onOpenProfile: () => context.push('/profile/${post.userId}'),
            onFollowAuthor: onFollowAuthor,
          ),
        ),
        Positioned(
          left: 14,
          right: 88,
          bottom: MediaQuery.of(context).padding.bottom + 20,
          child: _ReelBottomInfo(post: post),
        ),
      ],
    );
  }
}

class _ReelRightActions extends StatelessWidget {
  const _ReelRightActions({
    required this.post,
    required this.currentUserId,
    required this.onLike,
    required this.onRepost,
    required this.onCommentsTap,
    required this.onMoreTap,
    required this.onOpenProfile,
    required this.onFollowAuthor,
  });

  final PostEntity post;
  final String? currentUserId;
  final VoidCallback onLike;
  final VoidCallback onRepost;
  final VoidCallback onCommentsTap;
  final VoidCallback onMoreTap;
  final VoidCallback onOpenProfile;
  final VoidCallback onFollowAuthor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ReelsAuthorAvatar(
          post: post,
          currentUserId: currentUserId,
          onOpenProfile: onOpenProfile,
          onFollow: currentUserId != null &&
                  post.userId != currentUserId &&
                  !post.isFollowingAuthor
              ? onFollowAuthor
              : null,
        ),
        const SizedBox(height: 20),
        _ReelActionBtn(
          icon: post.isLikedByMe
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          color: post.isLikedByMe ? Colors.redAccent : Colors.white,
          label: _fmt(post.likesCount),
          onTap: currentUserId != null ? onLike : null,
        ),
        const SizedBox(height: 18),
        _ReelActionBtn(
          icon: Icons.chat_bubble_outline_rounded,
          color: Colors.white,
          label: _fmt(post.commentsCount),
          onTap: onCommentsTap,
        ),
        const SizedBox(height: 18),
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
        const SizedBox(height: 18),
        _ReelActionBtn(
          icon: Icons.send_rounded,
          color: Colors.white,
          label: '',
          onTap: () => context.push('/discover-publications'),
        ),
        const SizedBox(height: 18),
        _ReelActionBtn(
          icon: Icons.more_vert_rounded,
          color: Colors.white,
          label: '',
          onTap: onMoreTap,
        ),
      ],
    );
  }

  String _fmt(int n) {
    if (n <= 0) return '';
    return formatCompactCount(n);
  }
}

/// Аватар в стиле TikTok: градиентное кольцо / подпись «+».
class _ReelsAuthorAvatar extends StatelessWidget {
  const _ReelsAuthorAvatar({
    required this.post,
    required this.currentUserId,
    required this.onOpenProfile,
    this.onFollow,
  });

  final PostEntity post;
  final String? currentUserId;
  final VoidCallback onOpenProfile;
  final VoidCallback? onFollow;

  @override
  Widget build(BuildContext context) {
    final isMe =
        currentUserId != null && post.userId == currentUserId;
    final showPlus = onFollow != null && !isMe;

    return SizedBox(
      width: 58,
      height: showPlus ? 78 : 64,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          GestureDetector(
            onTap: onOpenProfile,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(2.8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: showPlus
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF2ED1C4),
                          Color(0xFFFE2C55),
                        ],
                      )
                    : null,
                color: showPlus ? null : Colors.white.withValues(alpha: 0.42),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                ),
                child: CachedAvatar(
                  imageUrl: post.userAvatarUrl,
                  radius: 22,
                  enableLightboxOnTap: false,
                ),
              ),
            ),
          ),
          if (showPlus)
            Positioned(
              bottom: 2,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onFollow,
                  customBorder: const CircleBorder(),
                  child: Ink(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFE2C55),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 18,
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
            shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
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

class _ReelBottomInfo extends StatelessWidget {
  const _ReelBottomInfo({required this.post});

  final PostEntity post;

  @override
  Widget build(BuildContext context) {
    final mt = (post.musicTitle ?? '').trim();
    final ma = (post.musicArtist ?? '').trim();
    final musicLine = mt.isEmpty
        ? (ma.isEmpty ? null : ma)
        : (ma.isEmpty ? mt : '$mt · $ma');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UsernameTap(
          userId: post.userId,
          username: post.userName ?? 'Пользователь',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
            letterSpacing: -0.2,
            shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
          ),
        ),
        if (post.caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ExpandableCaption(caption: post.caption),
        ],
        if (musicLine != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.music_note_rounded,
                size: 17,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  musicLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 4),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.play_circle_outline_rounded,
              size: 17,
              color: Colors.white.withValues(alpha: 0.88),
            ),
            const SizedBox(width: 6),
            Text(
              formatCompactCount(post.viewsCount),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'просмотров',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 13,
                fontWeight: FontWeight.w500,
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
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.95),
          fontSize: 14,
          height: 1.35,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
        ),
      ),
    );
  }
}

class _BottomGradient extends StatelessWidget {
  const _BottomGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color(0xDD000000),
            Colors.transparent,
          ],
          stops: [0.0, 1.0],
        ),
      ),
    );
  }
}

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
