import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../bloc/news_bloc.dart';

class NewsFeedPage extends StatelessWidget {
  const NewsFeedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated
        ? authState.user.id
        : context.read<AuthRepository>().currentUser?.id;
    return BlocProvider(
      create: (c) => NewsBloc(c.read<PostRepository>())..add(NewsLoaded(currentUserId: userId)),
      child: BlocListener<AuthBloc, AuthState>(
        listenWhen: (prev, curr) =>
            curr is AuthAuthenticated &&
            (prev is! AuthAuthenticated || prev.user.id != curr.user.id),
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            context.read<NewsBloc>().add(NewsRefresh(currentUserId: state.user.id));
          }
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Новости Темиртау',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
          ),
          centerTitle: true,
        ),
        body: BlocBuilder<NewsBloc, NewsState>(
          builder: (context, state) {
            if (state is NewsLoading) {
              return const Center(child: AppLoading());
            }
            if (state is NewsFailure) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(state.message),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.read<NewsBloc>().add(NewsRefresh(currentUserId: userId)),
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              );
            }
            if (state is NewsSuccess) {
              if (state.posts.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.article_outlined, size: 80, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Пока нет новостей',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Жители Темиртау могут выкладывать фото и короткие видео',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => context.push('/add-news'),
                        icon: const Icon(Icons.add),
                        label: const Text('Опубликовать новость'),
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  context.read<NewsBloc>().add(NewsRefresh(currentUserId: userId));
                },
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
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
                    );
                  },
                ),
              );
            }
            return const Center(child: AppLoading());
          },
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
  });

  final PostEntity post;
  final String? currentUserId;
  final VoidCallback onLike;

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
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _PostVideoPlayer(videoUrl: post.videoUrl!),
                ),
              ] else if (post.imageUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    post.imageUrl,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return AspectRatio(
                        aspectRatio: 1,
                        child: Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    (loadingProgress.expectedTotalBytes ?? 1)
                                : null,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 200,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image_outlined, size: 48),
                    ),
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
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
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
          _controller.value.isPlaying
              ? _controller.pause()
              : _controller.play();
        });
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          ),
          if (!_controller.value.isPlaying)
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
