import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/add_choice_sheet.dart';
import '../../../../core/widgets/app_error_view.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../../../core/widgets/verified_badge.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../product/domain/entities/product_entity.dart';
import '../../../stories/domain/entities/story_group_entity.dart';
import '../../../stories/domain/repositories/stories_repository.dart';
import '../../../stories/presentation/pages/story_viewer_args.dart';
import '../bloc/feed_bloc.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bloc = context.read<FeedBloc>();
      if (bloc.state is FeedInitial) {
        final userId = context.read<AuthBloc>().state is AuthAuthenticated
            ? (context.read<AuthBloc>().state as AuthAuthenticated).user.id
            : null;
        bloc.add(FeedLoaded(currentUserId: userId));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthBloc>().state is AuthAuthenticated
        ? (context.read<AuthBloc>().state as AuthAuthenticated).user.id
        : null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: CustomScrollView(
          cacheExtent: 400,
          slivers: [
            SliverToBoxAdapter(
              child: _FeedAppBar(),
            ),
            const SliverToBoxAdapter(
              child: _StoriesStrip(),
            ),
            BlocBuilder<FeedBloc, FeedState>(
              builder: (context, state) {
                if (state is FeedLoading) {
                  return const SliverFillRemaining(
                    child: Center(child: AppLoading()),
                  );
                }
                if (state is FeedFailure) {
                  return SliverFillRemaining(
                    child: AppErrorView(
                      message: state.message,
                      onRetry: () => context.read<FeedBloc>().add(
                            FeedLoaded(currentUserId: currentUserId),
                          ),
                    ),
                  );
                }
                if (state is FeedSuccess) {
                  if (state.products.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.storefront_rounded,
                                size: 80,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Пока нет товаров',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Добавьте первый товар или подождите публикаций.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: () => context.go('/home/add'),
                                icon: const Icon(Icons.add),
                                label: const Text('Добавить товар'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index == state.products.length) {
                          if (state.hasMore && !state.isLoadingMore) {
                            context.read<FeedBloc>().add(
                                  FeedLoadMore(
                                      currentUserId: currentUserId),
                                );
                          }
                          return state.isLoadingMore
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                        color: Colors.white),
                                  ),
                                )
                              : const SizedBox.shrink();
                        }
                        final product = state.products[index];
                        return _ProductCard(
                          product: product,
                          currentUserId: currentUserId,
                          onProductTap: () => context.push(
                            '/product/${product.id}',
                            extra: product,
                          ),
                          onSellerTap: () =>
                              context.push('/profile/${product.sellerId}'),
                          onLike: currentUserId != null
                              ? () => context.read<FeedBloc>().add(
                                    FeedToggleLike(
                                      productId: product.id,
                                      userId: currentUserId,
                                    ),
                                  )
                              : null,
                          onFollow: currentUserId != null &&
                                  currentUserId != product.sellerId
                              ? () => context.read<FeedBloc>().add(
                                    FeedToggleFollow(
                                      followerId: currentUserId,
                                      followingId: product.sellerId,
                                    ),
                                  )
                              : null,
                          onComment: () => context.push(
                            '/product/${product.id}',
                            extra: product,
                          ),
                        );
                      },
                      childCount: state.products.length + 1,
                    ),
                  );
                }
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedAppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(
            'tmr_tau',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.article_outlined, color: Colors.white),
            onPressed: () => context.go('/home/news'),
          ),
        ],
      ),
    );
  }
}

class _StoriesStrip extends StatefulWidget {
  const _StoriesStrip();

  @override
  State<_StoriesStrip> createState() => _StoriesStripState();
}

class _StoriesStripState extends State<_StoriesStrip> {
  List<StoryGroupEntity> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = context.read<StoriesRepository>();
      final list = await repo.getStoriesGroupedByUser();
      if (mounted) setState(() {
        _groups = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = context.read<AuthBloc>().state is AuthAuthenticated;

    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        children: [
          if (isLoggedIn)
            _StoryCircle(
              label: 'Ваша история',
              isAdd: true,
              onTap: () {
                showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (sheetContext) => AddChoiceSheet(
                    onProuvnut: () {
                      Navigator.pop(sheetContext);
                      context.push('/add-news');
                    },
                    onStory: () async {
                      Navigator.pop(sheetContext);
                      await context.push('/add-story');
                      if (context.mounted) _load();
                    },
                    onVideo: () async {
                      Navigator.pop(sheetContext);
                      await context.push('/add-story?video=1');
                      if (context.mounted) _load();
                    },
                  ),
                );
              },
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    color: Colors.white54,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            ..._groups.map((g) => _StoryCircle(
                  label: g.userName ?? 'История',
                  avatarUrl: g.userAvatarUrl,
                  onTap: () {
                    context.push(
                      '/stories',
                      extra: StoryViewerArgs(
                        groups: _groups,
                        initialGroupIndex: _groups.indexOf(g),
                      ),
                    );
                  },
                )),
        ],
      ),
    );
  }
}

class _StoryCircle extends StatelessWidget {
  const _StoryCircle({
    required this.label,
    this.isAdd = false,
    this.avatarUrl,
    this.onTap,
  });

  final String label;
  final bool isAdd;
  final String? avatarUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isAdd ? Colors.grey : Colors.white24,
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: isAdd
                    ? Icon(Icons.add, size: 28, color: Colors.grey.shade400)
                    : avatarUrl != null && avatarUrl!.isNotEmpty
                        ? CachedAvatar(
                            imageUrl: avatarUrl,
                            radius: 28,
                            fallbackText: label,
                          )
                        : Container(
                            color: Colors.grey.shade800,
                            child: CachedAvatar(
                              imageUrl: null,
                              radius: 28,
                              fallbackText: label,
                            ),
                          ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 64,
              height: 14,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    this.currentUserId,
    required this.onProductTap,
    required this.onSellerTap,
    this.onLike,
    this.onFollow,
    required this.onComment,
  });

  final ProductEntity product;
  final String? currentUserId;
  final VoidCallback onProductTap;
  final VoidCallback onSellerTap;
  final VoidCallback? onLike;
  final VoidCallback? onFollow;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.grey.shade900,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onSellerTap,
                  child: CachedAvatar(
                    imageUrl: product.sellerAvatarUrl,
                    radius: 18,
                    fallbackText: product.sellerName ?? product.sellerId,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: onSellerTap,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            product.sellerName ?? 'Продавец',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (product.sellerIsVerified) ...[
                          const SizedBox(width: 4),
                          const VerifiedBadge(size: 14),
                        ],
                      ],
                    ),
                  ),
                ),
                if (onFollow != null)
                  TextButton(
                    onPressed: onFollow,
                    child: Text(
                      product.isFollowingSeller ? 'Отписаться' : 'Подписаться',
                      style: TextStyle(
                        color: product.isFollowingSeller
                            ? Colors.grey
                            : Colors.blue.shade300,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onProductTap,
            child: AspectRatio(
              aspectRatio: 1,
              child: CachedProductImage(
                imageUrl: product.imageUrl,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        product.isLikedByMe ? Icons.favorite : Icons.favorite_border,
                        color: product.isLikedByMe ? Colors.red : Colors.white,
                        size: 26,
                      ),
                      onPressed: onLike,
                      padding: EdgeInsets.zero,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chat_bubble_outline,
                          size: 24, color: Colors.white),
                      onPressed: onComment,
                      padding: EdgeInsets.zero,
                    ),
                    if (product.likesCount > 0)
                      Text(
                        '${product.likesCount}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
                Text(
                  product.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  product.priceFormatted,
                  style: TextStyle(
                    color: Colors.blue.shade300,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
