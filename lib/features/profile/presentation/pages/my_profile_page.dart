import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../product/domain/entities/product_entity.dart';
import '../../domain/entities/seller_profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';

class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key});

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  SellerProfileEntity? _profile;
  List<PostEntity> _posts = [];
  bool _loading = true;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AuthBloc>().state;
    if (state is! AuthAuthenticated) {
      setState(() => _loading = false);
      return;
    }
    final uid = state.user.id;
    setState(() => _loading = true);
    try {
      final profile = await context.read<ProfileRepository>().getSellerProfile(uid);
      final posts = await context.read<PostRepository>().getPostsByUser(uid, currentUserId: uid);
      if (mounted) {
        setState(() {
          _profile = profile;
          _posts = posts;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAddChoice() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Добавить',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.shopping_bag_outlined, size: 28),
                title: const Text('Товар'),
                subtitle: const Text('Продать вещь на маркете'),
                onTap: () {
                  Navigator.pop(context);
                  context.go('/home/add');
                },
              ),
              ListTile(
                leading: const Icon(Icons.article_outlined, size: 28),
                title: const Text('Новость'),
                subtitle: const Text('Фото или короткое видео в ленту новостей'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/add-news');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          context.read<AuthBloc>().state is AuthAuthenticated
              ? (context.read<AuthBloc>().state as AuthAuthenticated).user.name ?? 'Профиль'
              : 'Профиль',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_outlined, size: 28),
            onPressed: () => _showAddChoice(),
          ),
          IconButton(
            icon: const Icon(Icons.menu_rounded, size: 26),
            onPressed: () {
              // Меню: настройки, заказы, избранное, выйти
              _showProfileMenu(context);
            },
          ),
        ],
      ),
      body: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          final user = state is AuthAuthenticated ? state.user : null;
          if (user == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Войдите в аккаунт'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.push('/login'),
                    child: const Text('Войти'),
                  ),
                ],
              ),
            );
          }
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return _ProfileContent(
            user: user,
            profile: _profile,
            posts: _posts,
            tabIndex: _tabIndex,
            onTabChanged: (i) => setState(() => _tabIndex = i),
            onRefresh: _load,
            onAddTap: _showAddChoice,
          );
        },
      ),
    );
  }

  void _showProfileMenu(BuildContext context) {
    final user = context.read<AuthBloc>().state is AuthAuthenticated
        ? (context.read<AuthBloc>().state as AuthAuthenticated).user
        : null;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.shopping_bag_outlined),
              title: const Text('Мои заказы'),
              onTap: () {
                Navigator.pop(context);
                context.push('/orders');
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('Избранное'),
              onTap: () {
                Navigator.pop(context);
                context.go('/home/favorites');
              },
            ),
            ListTile(
              leading: const Icon(Icons.store_outlined),
              title: const Text('Мой магазин'),
              onTap: () {
                Navigator.pop(context);
                if (user != null) context.push('/profile/${user.id}');
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Выйти'),
              onTap: () {
                Navigator.pop(context);
                context.read<AuthBloc>().add(const AuthSignOutRequested());
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.user,
    required this.profile,
    required this.posts,
    required this.tabIndex,
    required this.onTabChanged,
    required this.onRefresh,
    required this.onAddTap,
  });

  final AppUser user;
  final SellerProfileEntity? profile;
  final List<PostEntity> posts;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onRefresh;
  final VoidCallback onAddTap;

  int get _publicationsCount =>
      (profile?.products.length ?? 0) + posts.length;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  CachedAvatar(
                    imageUrl: user.avatarUrl ?? profile?.avatarUrl,
                    radius: 48,
                    fallbackText: user.name ?? user.email,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user.name ?? user.email,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if ((user.bio ?? profile?.bio) != null &&
                      (user.bio ?? profile?.bio)!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      user.bio ?? profile?.bio ?? '',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatItem(
                        value: _publicationsCount,
                        label: 'публикаций',
                      ),
                      _StatItem(
                        value: profile?.followersCount ?? user.followersCount,
                        label: 'подписчиков',
                      ),
                      _StatItem(
                        value: profile?.followingCount ?? user.followingCount,
                        label: 'подписок',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () => onTabChanged(0),
                          icon: Icon(
                            Icons.grid_on_rounded,
                            size: 22,
                            color: tabIndex == 0 ? Colors.black87 : Colors.grey,
                          ),
                          label: Text(
                            'Товары',
                            style: TextStyle(
                              fontWeight: tabIndex == 0 ? FontWeight.w600 : FontWeight.normal,
                              color: tabIndex == 0 ? Colors.black87 : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      Container(width: 1, height: 24, color: Colors.grey.shade300),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () => onTabChanged(1),
                          icon: Icon(
                            Icons.article_outlined,
                            size: 22,
                            color: tabIndex == 1 ? Colors.black87 : Colors.grey,
                          ),
                          label: Text(
                            'Новости',
                            style: TextStyle(
                              fontWeight: tabIndex == 1 ? FontWeight.w600 : FontWeight.normal,
                              color: tabIndex == 1 ? Colors.black87 : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 400,
                  child: tabIndex == 0
                      ? _ProductsGrid(products: profile?.products ?? [])
                      : _PostsGrid(posts: posts),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

class _ProductsGrid extends StatelessWidget {
  const _ProductsGrid({required this.products});

  final List<ProductEntity> products;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_bag_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Нет товаров',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => context.go('/home/add'),
              icon: const Icon(Icons.add),
              label: const Text('Добавить товар'),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.85,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final p = products[index];
        return GestureDetector(
          onTap: () => context.push('/product/${p.id}', extra: p),
          child: CachedProductImage(imageUrl: p.imageUrl),
        );
      },
    );
  }
}

class _PostsGrid extends StatelessWidget {
  const _PostsGrid({required this.posts});

  final List<PostEntity> posts;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Нет новостей',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => context.push('/add-news'),
              icon: const Icon(Icons.add),
              label: const Text('Опубликовать новость'),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.85,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final p = posts[index];
        if (p.imageUrl.isEmpty) {
          return Container(
            color: Colors.grey.shade200,
            child: const Center(
              child: Icon(Icons.article_outlined, size: 32),
            ),
          );
        }
        return Image.network(
          p.imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image_outlined),
          ),
        );
      },
    );
  }
}
