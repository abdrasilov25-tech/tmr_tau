import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/media/cached_video_controller.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/double_tap_like_burst.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../post/presentation/widgets/post_share_sheet.dart';
import '../../../post/presentation/widgets/post_photo_gallery.dart';
import '../bloc/news_bloc.dart';

/// Лента новостей: сверху блок «как в Threads» — аватар и подсказка, тап открывает создание новости.
class NewsFeedPage extends StatelessWidget {
  const NewsFeedPage({super.key});

  Future<void> _openAddNews(BuildContext context, String? userId) async {
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Войдите, чтобы опубликовать новость'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await context.push<PostEntity?>('/add-news');
    if (!context.mounted) return;
    context.read<NewsBloc>().add(NewsRefresh(currentUserId: userId));
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final userId = authState is AuthAuthenticated
        ? authState.user.id
        : context.read<AuthRepository>().currentUser?.id;
    return Builder(
      builder: (nested) {
        return Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: Text(
                  'Новости Темиртау',
                  style: Theme.of(nested).textTheme.titleLarge?.copyWith(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                centerTitle: true,
                actions: [
                  IconButton(
                    tooltip: 'Новая новость',
                    onPressed: () => _openAddNews(nested, userId),
                    icon: Icon(Icons.add, color: Colors.grey.shade800),
                  ),
                ],
              ),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: _NewsThreadsComposer(
                      avatarUrl: authState is AuthAuthenticated ? authState.user.avatarUrl : null,
                      displayName: authState is AuthAuthenticated
                          ? (authState.user.name ?? authState.user.email)
                          : null,
                      isLoggedIn: userId != null,
                      onTap: () => _openAddNews(nested, userId),
                    ),
                  ),
                  Expanded(
                child: BlocBuilder<NewsBloc, NewsState>(
                  builder: (context, state) {
                    if (state is NewsLoading) {
                      return const Center(child: AppLoading());
                    }
                    if (state is NewsFailure) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                state.message,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () => context.read<NewsBloc>().add(
                                    NewsLoaded(currentUserId: userId),
                                  ),
                              child: const Text('Повторить'),
                            ),
                          ],
                        ),
                      );
                    }
                    if (state is NewsSuccess) {
                      Future<void> refresh() async {
                        context.read<NewsBloc>().add(NewsRefresh(currentUserId: userId));
                      }

                      if (state.posts.isEmpty) {
                        return RefreshIndicator(
                          onRefresh: refresh,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                            children: [
                              Icon(Icons.article_outlined, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 20),
                              Text(
                                'Пока нет новостей',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Нажмите на строку выше — поделитесь, что происходит в городе.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Colors.grey.shade600,
                                      height: 1.35,
                                    ),
                              ),
                            ],
                          ),
                        );
                      }
                      return RefreshIndicator(
                        onRefresh: refresh,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: state.posts.length + (state.hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= state.posts.length) {
                              context.read<NewsBloc>().add(NewsLoadMore());
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            return _NewsPostCard(
                              post: state.posts[index],
                              currentUserId: userId,
                              onLike: () {
                                if (userId != null) {
                                  context.read<NewsBloc>().add(
                                        NewsToggleLike(postId: state.posts[index].id, userId: userId),
                                      );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Войдите, чтобы ставить лайки'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                              onShare: () async {
                                if (userId == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Войдите, чтобы поделиться публикацией'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  return;
                                }
                                await showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  showDragHandle: true,
                                  builder: (_) => PostShareSheet(
                                    currentUserId: userId,
                                    post: state.posts[index],
                                    onAddToStory: () async {},
                                  ),
                                );
                              },
                              onSave: () async {
                                if (userId == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Войдите, чтобы сохранять публикации'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  return;
                                }
                                try {
                                  await context.read<PostRepository>().toggleSave(
                                        state.posts[index].id,
                                        userId,
                                      );
                                  if (!context.mounted) return;
                                  context.read<NewsBloc>().add(
                                        NewsRefresh(currentUserId: userId),
                                      );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        state.posts[index].isSavedByMe
                                            ? 'Удалено из сохраненного'
                                            : 'Сохранено',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                } catch (_) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Не удалось сохранить'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      );
                    }
                    return const Center(child: AppLoading());
                  },
                ),
              ),
                ],
              ),
            );
      },
    );
  }
}

class _NewsThreadsComposer extends StatelessWidget {
  const _NewsThreadsComposer({
    required this.avatarUrl,
    required this.displayName,
    required this.isLoggedIn,
    required this.onTap,
  });

  final String? avatarUrl;
  final String? displayName;
  final bool isLoggedIn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = displayName?.trim();
    final fallback = !isLoggedIn
        ? '?'
        : (name != null && name.isNotEmpty
            ? name.substring(0, 1).toUpperCase()
            : '?');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300.withValues(alpha: 0.6)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                CachedAvatar(
                  imageUrl: avatarUrl,
                  radius: 22,
                  fallbackText: fallback,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isLoggedIn
                        ? 'Что происходит в Темиртау?'
                        : 'Войдите, чтобы рассказать о Темиртау',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade600,
                      height: 1.25,
                    ),
                  ),
                ),
                Icon(
                  Icons.perm_media_outlined,
                  size: 22,
                  color: Colors.grey.shade500,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewsPostCard extends StatelessWidget {
  const _NewsPostCard({
    required this.post,
    this.currentUserId,
    required this.onLike,
    required this.onShare,
    required this.onSave,
  });

  final PostEntity post;
  final String? currentUserId;
  final VoidCallback onLike;
  final Future<void> Function() onShare;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () async {
          final deleted = await context.push<bool>('/post/${post.id}', extra: post);
          if (deleted == true && context.mounted) {
            context.read<NewsBloc>().add(NewsRefresh(currentUserId: currentUserId));
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => context.push('/profile/${post.userId}'),
                    child: CachedAvatar(
                      imageUrl: post.userAvatarUrl,
                      radius: 20,
                      fallbackText: post.userName ?? post.userId,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => context.push('/profile/${post.userId}'),
                          child: Text(
                            post.userName ?? 'Житель',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Text(
                          _timeAgo(post.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (post.caption.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  post.caption,
                  style: const TextStyle(fontSize: 15, height: 1.35),
                ),
              ],
              if (post.videoUrl != null && post.videoUrl!.isNotEmpty) ...[
                const SizedBox(height: 12),
                DoubleTapLikeBurst(
                  iconSize: 72,
                  onDoubleTapLike: onLike,
                  shouldTriggerLike: () => !post.isLikedByMe,
                  showPersistentLikeIndicator: true,
                  isLiked: post.isLikedByMe,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _PostVideoPlayer(videoUrl: post.videoUrl!),
                  ),
                ),
              ] else if (post.displayImageUrls.isNotEmpty) ...[
                const SizedBox(height: 12),
                DoubleTapLikeBurst(
                  iconSize: 72,
                  onDoubleTapLike: onLike,
                  shouldTriggerLike: () => !post.isLikedByMe,
                  showPersistentLikeIndicator: true,
                  isLiked: post.isLikedByMe,
                  child: PostNetworkPhotoGallery(
                    urls: post.displayImageUrls,
                    height: post.displayImageUrls.length > 1 ? 300 : 280,
                    borderRadius: 8,
                    viewportFraction: post.displayImageUrls.length > 1 ? 0.92 : 1,
                    enableTapToOpenFullscreen: false,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      post.isLikedByMe ? Icons.favorite : Icons.favorite_border,
                      size: 22,
                      color: post.isLikedByMe ? Colors.red : null,
                    ),
                    onPressed: onLike,
                  ),
                  Text(
                    '${post.likesCount}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () async {
                      final deleted = await context.push<bool>('/post/${post.id}', extra: post);
                      if (deleted == true && context.mounted) {
                        context.read<NewsBloc>().add(NewsRefresh(currentUserId: currentUserId));
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 22, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(
                          '${post.commentsCount}',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: Icon(
                      post.isRepostedByMe ? Icons.repeat : Icons.repeat_outlined,
                      size: 22,
                      color: post.isRepostedByMe ? Colors.green : Colors.grey.shade700,
                    ),
                    onPressed: currentUserId != null
                        ? () => context.read<NewsBloc>().add(
                              NewsToggleRepost(postId: post.id, userId: currentUserId!),
                            )
                        : null,
                  ),
                  Text(
                    '${post.repostsCount}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Поделиться',
                    icon: Icon(Icons.send_outlined, size: 22, color: Colors.grey.shade700),
                    onPressed: onShare,
                  ),
                  IconButton(
                    tooltip: 'Сохранить',
                    icon: Icon(
                      post.isSavedByMe ? Icons.bookmark : Icons.bookmark_border,
                      size: 22,
                      color: post.isSavedByMe ? Colors.black87 : Colors.grey.shade700,
                    ),
                    onPressed: onSave,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин';
    if (diff.inHours < 24) return '${diff.inHours} ч';
    if (diff.inDays < 7) return '${diff.inDays} дн';
    return '${dateTime.day}.${dateTime.month}.${dateTime.year}';
  }
}

class _PostVideoPlayer extends StatefulWidget {
  const _PostVideoPlayer({required this.videoUrl});

  final String videoUrl;

  @override
  State<_PostVideoPlayer> createState() => _PostVideoPlayerState();
}

class _PostVideoPlayerState extends State<_PostVideoPlayer> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      final c = await createCachedVideoController(widget.videoUrl);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.grey.shade300,
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return GestureDetector(
      onTap: () {
        setState(() {
          c.value.isPlaying ? c.pause() : c.play();
        });
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
          if (!c.value.isPlaying)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 48),
            ),
        ],
      ),
    );
  }
}
