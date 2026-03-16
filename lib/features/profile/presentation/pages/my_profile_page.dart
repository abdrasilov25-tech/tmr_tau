import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import '../../../../core/accounts/account_manager.dart';
import '../../../../core/accounts/account_model.dart';
import '../../../../core/storage/multi_account_storage.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../../../core/widgets/add_choice_sheet.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../widgets/account_switcher_sheet.dart';
import '../widgets/account_switcher_token_sheet.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/pages/login_result.dart';
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
  bool _updatingAvatar = false;
  bool _isSwitchingAccount = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _changeAvatar() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы изменить аватар')),
      );
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _updatingAvatar = true);
    try {
      final file = File(picked.path);
      final ext = file.path.split('.').last;
      final fileName =
          '${authState.user.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      // Храним аватары в отдельном бакете avatars.
      final storageRef = supa.Supabase.instance.client.storage
          .from(SupabaseConstants.bucketAvatars);
      await storageRef.upload(
        fileName,
        file,
        fileOptions: const supa.FileOptions(upsert: true),
      );
      final publicUrl = storageRef.getPublicUrl(fileName);

      await context.read<ProfileRepository>().updateProfile(
            userId: authState.user.id,
            avatarUrl: publicUrl,
          );

      if (mounted) {
        context.read<AuthBloc>().add(const AuthCheckRequested());
        await _load();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Аватар обновлён')),
        );
      }
    } catch (e, st) {
      if (!mounted) return;
      String message = 'Не удалось обновить аватар: $e';
      if (e is supa.StorageException) {
        message = 'Storage error: ${e.message}';
      } else if (e is supa.PostgrestException) {
        message = 'Postgrest error: ${e.message}';
      }
      // Для отладки можно смотреть полный текст ошибки в консоли.
      // ignore: avoid_print
      print('Avatar upload error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _updatingAvatar = false);
    }
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
      final repo = context.read<ProfileRepository>();
      final profile = await repo.getSellerProfile(uid);
      final posts =
          await context.read<PostRepository>().getPostsByUser(uid, currentUserId: uid);
      // Подсчитываем актуальное количество подписок через followers.
      final followingUsers = await repo.getFollowingUsers(uid);
      final followingCount = followingUsers.length;
      if (mounted) {
        setState(() {
          _profile = profile == null
              ? null
              : SellerProfileEntity(
                  id: profile.id,
                  name: profile.name,
                  avatarUrl: profile.avatarUrl,
                  bio: profile.bio,
                  followersCount: profile.followersCount,
                  followingCount: followingCount,
                  isFollowingByMe: profile.isFollowingByMe,
                  products: profile.products,
                  isVerified: profile.isVerified,
                );
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

  void _showStoryChoice() {
    final state = context.read<AuthBloc>().state;
    if (state is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы добавить историю')),
      );
      return;
    }
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
        },
        onVideo: () async {
          Navigator.pop(sheetContext);
          await context.push('/add-story?video=1');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: _showStoryChoice,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: GestureDetector(
          onTap: () {
            final state = context.read<AuthBloc>().state;
            if (state is! AuthAuthenticated) return;
            _showAccountSwitcher(context, state.user);
          },
          child: Builder(
            builder: (context) {
              final state = context.read<AuthBloc>().state;
              if (state is! AuthAuthenticated) {
                return Text(
                  'Профиль',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                );
              }
              final user = state.user;
              final primary = (user.username != null &&
                      user.username!.isNotEmpty)
                  ? user.username!
                  : user.email;
              return Text(
                primary,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
              );
            },
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
              // Меню: чаты, избранное, выйти
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
            onAvatarTap: _changeAvatar,
            updatingAvatar: _updatingAvatar,
          );
        },
      ),
    );
  }

  void _showAccountSwitcher(BuildContext context, AppUser currentUser) {
    final rootContext = context;
    final accountStorage = rootContext.read<MultiAccountStorage>();
    final accountManager = rootContext.read<AccountManager>();
    final savedAccounts = accountStorage.getAccounts();
    showModalBottomSheet<void>(
      context: rootContext,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => FutureBuilder<List<AccountModel>>(
          future: accountManager.loadAccounts(),
          builder: (sheetContext, snapshot) {
            final accounts = snapshot.data ?? const [];
            final active = accountManager.activeAccount;
            if (accounts.isEmpty) {
              // Fallback на старый переключатель, если ещё нет токен-аккаунтов.
              return AccountSwitcherSheet(
                scrollController: scrollController,
                currentUser: currentUser,
                savedAccounts: savedAccounts,
                onAddAccount: () async {
                  await accountStorage.addAccount(
                    SavedAccount(
                      id: currentUser.id,
                      email: currentUser.email,
                      name: currentUser.name,
                      avatarUrl: currentUser.avatarUrl,
                    ),
                  );
                  final result = await rootContext.push<dynamic>(
                    '/login',
                    extra: {'addAccount': true},
                  );
                  if (!mounted) return;
                  if (result is LoginResult) {
                    if (result.password != null &&
                        result.password!.isNotEmpty) {
                      accountStorage.savePasswordImmediate(
                        result.userId,
                        result.email,
                        result.password!,
                      );
                    }
                    await accountStorage.addAccount(
                      SavedAccount(
                        id: result.userId,
                        email: result.email,
                        name: result.name,
                        avatarUrl: result.avatarUrl,
                      ),
                      password: result.password,
                    );
                    setState(() {});
                  }
                },
                onSwitchAccount: (account, closeSheet) async {
                  if (_isSwitchingAccount) return;
                  _isSwitchingAccount = true;
                  closeSheet();
                  String? password;
                  try {
                    password = await accountStorage.getPassword(
                      account.id,
                      email: account.email,
                    );
                  } catch (_) {
                    password = null;
                  }
                  if (password == null || password.isEmpty) {
                    if (!mounted) {
                      _isSwitchingAccount = false;
                      return;
                    }
                    ScaffoldMessenger.of(rootContext).showSnackBar(
                      const SnackBar(
                        content: Text('Введите пароль для переключения'),
                      ),
                    );
                    await rootContext.push<void>(
                      '/login',
                      extra: {'email': account.email},
                    );
                    if (mounted) {
                      setState(() => _isSwitchingAccount = false);
                    }
                    return;
                  }
                  if (!mounted) {
                    _isSwitchingAccount = false;
                    return;
                  }
                  rootContext.read<AuthBloc>().add(
                        AuthSwitchToAccountRequested(
                          email: account.email,
                          password: password,
                        ),
                      );
                  setState(() => _isSwitchingAccount = false);
                },
              );
            }
            return AccountSwitcherTokenSheet(
              scrollController: scrollController,
              activeAccount: active,
              accounts: accounts,
              savedAccounts: savedAccounts,
              onAddAccount: () async {
                await accountStorage.addAccount(
                  SavedAccount(
                    id: currentUser.id,
                    email: currentUser.email,
                    name: currentUser.name,
                    avatarUrl: currentUser.avatarUrl,
                  ),
                );
                final result = await rootContext.push<dynamic>(
                  '/login',
                  extra: {'addAccount': true},
                );
                if (!mounted) return;
                if (result is LoginResult) {
                  if (result.password != null && result.password!.isNotEmpty) {
                    accountStorage.savePasswordImmediate(
                      result.userId,
                      result.email,
                      result.password!,
                    );
                  }
                  await accountStorage.addAccount(
                    SavedAccount(
                      id: result.userId,
                      email: result.email,
                      name: result.name,
                      avatarUrl: result.avatarUrl,
                    ),
                    password: result.password,
                  );
                  setState(() {});
                }
              },
              onSelectAccount: (account) async {
                if (_isSwitchingAccount) return;
                _isSwitchingAccount = true;
                Navigator.of(sheetContext).pop();
                try {
                  await accountManager.switchAccount(account);
                } on supa.AuthApiException catch (e) {
                  final code = e.code ?? '';
                  final message = e.message.toLowerCase();
                  final isInvalidRefreshToken =
                      code == 'refresh_token_not_found' ||
                      message.contains('invalid refresh token');
                  if (isInvalidRefreshToken) {
                    if (!mounted) {
                      _isSwitchingAccount = false;
                      return;
                    }
                    ScaffoldMessenger.of(rootContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Сессия аккаунта устарела. Войдите заново.',
                        ),
                      ),
                    );
                    await rootContext.push<void>(
                      '/login',
                      extra: {'email': account.email},
                    );
                    if (mounted) {
                      setState(() => _isSwitchingAccount = false);
                    }
                    return;
                  }
                  rethrow;
                }
                if (!mounted) {
                  _isSwitchingAccount = false;
                  return;
                }
                rootContext
                    .read<AuthBloc>()
                    .add(const AuthCheckRequested());
                setState(() => _isSwitchingAccount = false);
              },
            );
          },
        ),
      ),
    );
  }

  void _showProfileMenu(BuildContext context) {
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
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Мои чаты'),
              onTap: () {
                Navigator.pop(context);
                context.push('/chats');
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('Избранное'),
              onTap: () {
                Navigator.pop(context);
                context.push('/favorites');
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
    required this.onAvatarTap,
    required this.updatingAvatar,
  });

  final AppUser user;
  final SellerProfileEntity? profile;
  final List<PostEntity> posts;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onRefresh;
  final VoidCallback onAddTap;
  final VoidCallback onAvatarTap;
  final bool updatingAvatar;

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
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      GestureDetector(
                        onTap: () {
                          final imageUrl = user.avatarUrl ?? profile?.avatarUrl;
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
                          imageUrl: user.avatarUrl ?? profile?.avatarUrl,
                          radius: 48,
                          fallbackText: user.name ?? user.email,
                        ),
                      ),
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: GestureDetector(
                          onTap: updatingAvatar ? null : onAvatarTap,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blueAccent,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: updatingAvatar
                                ? const Padding(
                                    padding: EdgeInsets.all(3),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  )
                                : const Icon(
                                    Icons.add,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    (user.username != null && user.username!.isNotEmpty)
                        ? '@${user.username}'
                        : user.email,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if (user.name != null && user.name!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      user.name!,
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade700,
                              ),
                    ),
                  ],
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
                  TextButton(
                    onPressed: () => context.push('/edit-profile'),
                    child: const Text('Редактировать профиль'),
                  ),
                  const SizedBox(height: 8),
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
                        onTap: () => context.push('/followers'),
                      ),
                      _StatItem(
                        value: profile?.followingCount ?? user.followingCount,
                        label: 'подписок',
                        onTap: () => context.push('/following'),
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
  const _StatItem({
    required this.value,
    required this.label,
    this.onTap,
  });

  final int value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Column(
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
    if (onTap == null) return content;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: content,
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
        final hasVideo = p.videoUrl != null && p.videoUrl!.isNotEmpty;
        if (p.imageUrl.isEmpty && !hasVideo) {
          return Container(
            color: Colors.grey.shade200,
            child: const Center(
              child: Icon(Icons.article_outlined, size: 32),
            ),
          );
        }
        if (hasVideo && p.imageUrl.isEmpty) {
          return Container(
            color: Colors.grey.shade300,
            child: const Center(
              child: Icon(Icons.videocam, size: 40, color: Colors.white70),
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
                child: Icon(Icons.play_circle_fill, size: 36, color: Colors.white70),
              ),
          ],
        );
      },
    );
  }
}
