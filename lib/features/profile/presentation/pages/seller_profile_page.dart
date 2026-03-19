import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/widgets/app_error_view.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../../../core/widgets/verified_badge.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../chat/presentation/widgets/start_chat_button.dart';
import '../../../product/domain/entities/product_entity.dart';
import '../../domain/entities/seller_profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';
import '../bloc/profile_bloc.dart';

class SellerProfilePage extends StatelessWidget {
  const SellerProfilePage({super.key, required this.sellerId});

  final String sellerId;

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthBloc>().state is AuthAuthenticated
        ? (context.read<AuthBloc>().state as AuthAuthenticated).user.id
        : null;
    return BlocProvider(
      create: (c) => ProfileBloc(c.read<ProfileRepository>())
        ..add(ProfileLoadRequested(sellerId, currentUserId: currentUserId)),
      child: Scaffold(
        appBar: AppBar(title: const Text('Профиль')),
        body: BlocBuilder<ProfileBloc, ProfileState>(
          builder: (context, state) {
            if (state is ProfileLoading) return const AppLoading();
            if (state is ProfileFailure) {
              return AppErrorView(
                message: state.message,
                onRetry: () => context
                    .read<ProfileBloc>()
                    .add(ProfileLoadRequested(sellerId)),
              );
            }
            if (state is ProfileSuccess) {
              return _SellerProfileView(profile: state.profile);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

class _SellerProfileView extends StatefulWidget {
  const _SellerProfileView({required this.profile});

  final SellerProfileEntity profile;

  @override
  State<_SellerProfileView> createState() => _SellerProfileViewState();
}

class _SellerProfileViewState extends State<_SellerProfileView> {
  int _tabIndex = 0;
  List<PostEntity> _publicationPosts = const [];
  bool _loadingPublications = true;

  @override
  void initState() {
    super.initState();
    _loadPublications();
  }

  Future<void> _loadPublications() async {
    final authState = context.read<AuthBloc>().state;
    final currentUserId =
        authState is AuthAuthenticated ? authState.user.id : null;
    try {
      final posts = await context.read<PostRepository>().getPostsByUser(
            widget.profile.id,
            currentUserId: currentUserId,
          );
      if (!mounted) return;
      setState(() {
        _publicationPosts = posts
            .where((p) => p.kind == 'publication')
            .toList(growable: false);
        _loadingPublications = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPublications = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: DecoratedBox(
              decoration: ThemedContentSurface.profileCardDecoration(),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                GestureDetector(
                  onTap: () {
                    final imageUrl = profile.avatarUrl;
                    if (imageUrl == null || imageUrl.isEmpty) return;
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => Dialog(
                        backgroundColor: Colors.black,
                        insetPadding: const EdgeInsets.all(24),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: InteractiveViewer(
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: CachedAvatar(
                    imageUrl: profile.avatarUrl != null &&
                            profile.avatarUrl!.isNotEmpty
                        ? '${profile.avatarUrl}?uid=${profile.id}'
                        : null,
                    radius: 48,
                    fallbackText: profile.name,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      profile.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: ThemedContentSurface.profileTextPrimary,
                          ),
                    ),
                    if (profile.isVerified) ...[
                      const SizedBox(width: 6),
                      const VerifiedBadge(size: 22),
                    ],
                  ],
                ),
                if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      profile.bio!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: ThemedContentSurface.profileTextSecondary,
                            height: 1.35,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${profile.followersCount} подписчиков',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: ThemedContentSurface.profileTextSecondary,
                          ),
                    ),
                    const SizedBox(width: 24),
                    Text(
                      '${profile.followingCount} подписок',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: ThemedContentSurface.profileTextSecondary,
                          ),
                    ),
                    const SizedBox(width: 24),
                    Text(
                      '${profile.products.length} товаров',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: ThemedContentSurface.profileTextSecondary,
                          ),
                    ),
                  ],
                ),
                if (context.read<AuthBloc>().state is AuthAuthenticated &&
                    (context.read<AuthBloc>().state as AuthAuthenticated).user.id != profile.id) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final uid = (context.read<AuthBloc>().state as AuthAuthenticated).user.id;
                            context.read<ProfileBloc>().add(
                                  ProfileToggleFollow(
                                    followerId: uid,
                                    followingId: profile.id,
                                  ),
                                );
                          },
                          child: Text(
                            profile.isFollowingByMe ? 'Отписаться' : 'Подписаться',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StartChatButton(
                          peerId: profile.id,
                          peerName: profile.name,
                        ),
                      ),
                    ],
                  ),
                ],
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: DecoratedBox(
              decoration: ThemedContentSurface.profileCardDecoration(radius: 16),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: _ProfileTabChip(
                        selected: _tabIndex == 0,
                        icon: Icons.shopping_bag_outlined,
                        label: 'Товары',
                        onTap: () => setState(() => _tabIndex = 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ProfileTabChip(
                        selected: _tabIndex == 1,
                        icon: Icons.person_outline_rounded,
                        label: 'Лента',
                        onTap: () => setState(() => _tabIndex = 1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_tabIndex == 0)
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final product = profile.products[index];
                return _ProductGridTile(
                  product: product,
                  onTap: () =>
                      context.push('/product/${product.id}', extra: product),
                );
              },
              childCount: profile.products.length,
            ),
          )
        else
          SliverToBoxAdapter(
            child: _ProfilePublicationsGrid(
              posts: _publicationPosts,
              loading: _loadingPublications,
            ),
          ),
      ],
    );
  }
}

class _ProductGridTile extends StatelessWidget {
  const _ProductGridTile({
    required this.product,
    required this.onTap,
  });

  final ProductEntity product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CachedProductImage(
                imageUrl: product.imageUrl,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                product.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                product.priceFormatted,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTabChip extends StatelessWidget {
  const _ProfileTabChip({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? Colors.black87 : Colors.grey),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black87 : Colors.grey,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfilePublicationsGrid extends StatelessWidget {
  const _ProfilePublicationsGrid({
    required this.posts,
    required this.loading,
  });

  final List<PostEntity> posts;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Нет публикаций',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.85,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final p = posts[index];
        final hasVideo = p.videoUrl != null && p.videoUrl!.isNotEmpty;
        if (p.imageUrl.isEmpty && !hasVideo) {
          return Container(
            color: Colors.grey.shade200,
            child: const Center(child: Icon(Icons.person_outline_rounded)),
          );
        }
        if (hasVideo && p.imageUrl.isEmpty) {
          return Container(
            color: Colors.grey.shade300,
            child: const Center(
              child: Icon(Icons.play_circle_fill, size: 36, color: Colors.white70),
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              p.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
            if (hasVideo)
              const Center(
                child: Icon(Icons.play_circle_fill, size: 34, color: Colors.white70),
              ),
          ],
        );
      },
    );
  }
}
