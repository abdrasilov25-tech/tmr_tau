import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/app_error_view.dart';
import '../../../../core/widgets/feed_product_card_skeleton.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../../../core/widgets/double_tap_like_burst.dart';
import '../../../product/presentation/widgets/product_promo_badges.dart';
import '../../../../core/widgets/verified_badge.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../product/domain/entities/product_entity.dart';
import '../../../profile/domain/repositories/profile_repository.dart';
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
  static const int _sponsoredEvery = 6;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bloc = context.read<FeedBloc>();
      if (bloc.state is FeedInitial) {
        final authState = context.read<AuthBloc>().state;
        final userId = authState is AuthAuthenticated
            ? authState.user.id
            : context.read<AuthRepository>().currentUser?.id;
        bloc.add(FeedLoaded(currentUserId: userId));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final currentUserId = authState is AuthAuthenticated
        ? authState.user.id
        : context.read<AuthRepository>().currentUser?.id;
    return Scaffold(
      backgroundColor: Colors.transparent,
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
                  return const FeedProductSkeletonSliver(itemCount: 5);
                }
                if (state is FeedFailure) {
                  return SliverFillRemaining(
                    child: AppErrorView(
                      message: state.message,
                      onRetry: () => context.read<FeedBloc>().add(
                            FeedLoaded(
                              currentUserId: currentUserId,
                              forceRefresh: true,
                            ),
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
                                onPressed: () => context.go('/add-product'),
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
                        final totalCards =
                            state.products.length + _sponsoredSlots(state.products.length);
                        if (index == totalCards) {
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
                        if (_isSponsoredIndex(index)) {
                          return _SponsoredCard(
                            onTap: () => context.go('/qarmet-wallet'),
                          );
                        }
                        final productIndex = _productIndexByFeedIndex(index);
                        final product = state.products[productIndex];
                        return _ProductCard(
                          product: product,
                          currentUserId: currentUserId,
                          onProductTap: () => context.push(
                            '/product/${product.id}',
                            extra: product,
                          ),
                          onSellerTap: () =>
                              context.push('/profile/${product.sellerId}'),
                          onLike: () {
                            final userId = currentUserId;
                            if (userId != null) {
                              context.read<FeedBloc>().add(
                                    FeedToggleLike(
                                      productId: product.id,
                                      userId: userId,
                                    ),
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
                          onRepost: currentUserId != null
                              ? () => context.read<FeedBloc>().add(
                                    FeedToggleRepost(
                                      productId: product.id,
                                      userId: currentUserId,
                                    ),
                                  )
                              : null,
                        );
                      },
                      childCount:
                          state.products.length + _sponsoredSlots(state.products.length) + 1,
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

  static int _sponsoredSlots(int productCount) {
    if (productCount < _sponsoredEvery) return 0;
    return productCount ~/ _sponsoredEvery;
  }

  static bool _isSponsoredIndex(int index) {
    return (index + 1) % (_sponsoredEvery + 1) == 0;
  }

  static int _productIndexByFeedIndex(int feedIndex) {
    final sponsoredBefore = (feedIndex + 1) ~/ (_sponsoredEvery + 1);
    return feedIndex - sponsoredBefore;
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
  Set<String> _followingUserIds = const {};
  Set<String> _viewedStoryIds = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final authState = context.read<AuthBloc>().state;
      final currentUserId =
          authState is AuthAuthenticated ? authState.user.id : null;
      final repo = context.read<StoriesRepository>();
      final listFuture = repo.getStoriesGroupedByUser();
      Future<Set<String>> viewedStoryIdsFuture() async {
        if (currentUserId == null) return const <String>{};
        return repo.getViewedStoryIds(currentUserId);
      }
      Future<Set<String>> followingIdsFuture() async {
        if (currentUserId == null) return const <String>{};
        final profiles = await context
            .read<ProfileRepository>()
            .getFollowingUsers(currentUserId);
        return profiles.map((p) => p.id).toSet();
      }
      final list = await listFuture;
      final followingIds = await followingIdsFuture();
      final viewedStoryIds = await viewedStoryIdsFuture();
      if (mounted) {
        setState(() {
          _groups = list;
          _followingUserIds = followingIds;
          _viewedStoryIds = viewedStoryIds;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось загрузить истории: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final isLoggedIn = authState is AuthAuthenticated;
    final currentUserId = authState is AuthAuthenticated ? authState.user.id : null;
    final ownGroup = currentUserId == null
        ? null
        : _groups.cast<StoryGroupEntity?>().firstWhere(
              (g) => g?.userId == currentUserId,
              orElse: () => null,
            );
    final otherGroups = currentUserId == null
        ? _groups
        : _groups
            .where(
              (g) => g.userId != currentUserId && _followingUserIds.contains(g.userId),
            )
            .toList(growable: false);
    final allGroupsForViewer = <StoryGroupEntity>[
      if (ownGroup case final StoryGroupEntity group) group,
      ...otherGroups,
    ];
    bool groupHasUnseen(StoryGroupEntity group) {
      if (currentUserId == null) return true;
      return group.stories.any((s) => !_viewedStoryIds.contains(s.id));
    }
    final sortedOtherGroups = [...otherGroups]..sort((a, b) {
      final aUnseen = groupHasUnseen(a);
      final bUnseen = groupHasUnseen(b);
      if (aUnseen != bUnseen) return aUnseen ? -1 : 1;
      final aLatest = a.stories.first.createdAt;
      final bLatest = b.stories.first.createdAt;
      return bLatest.compareTo(aLatest);
    });

    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        children: [
          if (isLoggedIn)
            _StoryCircle(
              label: 'Ваша история',
              avatarUrl: ownGroup?.userAvatarUrl,
              showPlusBadge: true,
              onTap: () async {
                if (ownGroup != null) {
                  await context.push(
                    '/stories',
                    extra: StoryViewerArgs(
                      groups: allGroupsForViewer,
                      initialGroupIndex: 0,
                    ),
                  );
                  if (mounted) _load();
                  return;
                }
                await context.push('/add-story');
                if (context.mounted) _load();
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
            ...sortedOtherGroups.map((g) => _StoryCircle(
                  label: g.userName ?? 'История',
                  avatarUrl: g.userAvatarUrl,
                  hasUnseen: groupHasUnseen(g),
                  onTap: () async {
                    final initialIndex =
                        ownGroup == null
                            ? sortedOtherGroups.indexOf(g)
                            : sortedOtherGroups.indexOf(g) + 1;
                    await context.push(
                      '/stories',
                      extra: StoryViewerArgs(
                        groups: [
                          if (ownGroup case final StoryGroupEntity group) group,
                          ...sortedOtherGroups,
                        ],
                        initialGroupIndex: initialIndex,
                      ),
                    );
                    if (mounted) _load();
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
    this.showPlusBadge = false,
    this.hasUnseen = true,
    this.avatarUrl,
    this.onTap,
  });

  final String label;
  final bool showPlusBadge;
  final bool hasUnseen;
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
            SizedBox(
              width: 56,
              height: 56,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: hasUnseen
                            ? const Color(0xFFE91E63)
                            : Colors.grey.shade600,
                        width: hasUnseen ? 2.4 : 2,
                      ),
                    ),
                    child: ClipOval(
                      child: avatarUrl != null && avatarUrl!.isNotEmpty
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
                  if (showPlusBadge)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E88E5),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: const Icon(
                          Icons.add,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 64,
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
    this.onRepost,
  });

  final ProductEntity product;
  final String? currentUserId;
  final VoidCallback onProductTap;
  final VoidCallback onSellerTap;
  final VoidCallback? onLike;
  final VoidCallback? onFollow;
  final VoidCallback onComment;
  final VoidCallback? onRepost;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.grey.shade900,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: product.showHighlightBadge
            ? const BorderSide(color: Color(0xFFFFC107), width: 2)
            : BorderSide.none,
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final dpr = MediaQuery.devicePixelRatioOf(context);
                final w = constraints.maxWidth;
                final imageStack = Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedProductImage(
                      imageUrl: product.imageUrl,
                      width: double.infinity,
                      height: double.infinity,
                      memCacheWidth: (w * dpr).round(),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: ProductPromoBadges(product: product),
                    ),
                  ],
                );
                return AspectRatio(
                  aspectRatio: 1,
                  child: onLike != null
                      ? DoubleTapLikeBurst(
                          iconSize: 80,
                          onDoubleTapLike: onLike!,
                          shouldTriggerLike: () => !product.isLikedByMe,
                          showPersistentLikeIndicator: true,
                          isLiked: product.isLikedByMe,
                          child: imageStack,
                        )
                      : imageStack,
                );
              },
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
                    if (product.likesCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '${product.likesCount}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.chat_bubble_outline,
                          size: 24, color: Colors.white),
                      onPressed: onComment,
                      padding: EdgeInsets.zero,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.repeat,
                        size: 24,
                        color:
                            product.isRepostedByMe ? Colors.greenAccent : Colors.white,
                      ),
                      onPressed: onRepost,
                      padding: EdgeInsets.zero,
                    ),
                    if (product.repostsCount > 0)
                      Text(
                        '${product.repostsCount}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    const Spacer(),
                    Icon(
                      Icons.visibility_outlined,
                      size: 20,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${product.viewCount}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
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

class _SponsoredCard extends StatelessWidget {
  const _SponsoredCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF111827),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blue.shade700, width: 1.2),
      ),
      child: ListTile(
        leading: const Icon(Icons.campaign_outlined, color: Colors.white),
        title: const Text(
          'Sponsored',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Поднимите свой товар в топ и получите больше просмотров',
          style: TextStyle(color: Colors.white70),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white70),
        onTap: onTap,
      ),
    );
  }
}
