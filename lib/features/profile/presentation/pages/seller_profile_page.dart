import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/app_error_view.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../../../core/widgets/verified_badge.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
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

class _SellerProfileView extends StatelessWidget {
  const _SellerProfileView({required this.profile});

  final SellerProfileEntity profile;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                CachedAvatar(
                  imageUrl: profile.avatarUrl,
                  radius: 48,
                  fallbackText: profile.name,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      profile.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (profile.isVerified) ...[
                      const SizedBox(width: 6),
                      const VerifiedBadge(size: 22),
                    ],
                  ],
                ),
                if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile.bio!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${profile.followersCount} подписчиков',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(width: 24),
                    Text(
                      '${profile.followingCount} подписок',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(width: 24),
                    Text(
                      '${profile.products.length} товаров',
                      style: Theme.of(context).textTheme.bodyMedium,
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
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Товары',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
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
