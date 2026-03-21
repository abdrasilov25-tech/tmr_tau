import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import '../../../../core/accounts/account_manager.dart';
import '../../../../core/accounts/account_model.dart';
import '../../../../core/storage/multi_account_storage.dart';
import '../../../../core/storage/chat_story_list_storage.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/theme/theme_index_notifier.dart';
import '../../../../core/widgets/theme_picker_sheet.dart';
import '../widgets/account_switcher_sheet.dart';
import '../widgets/account_switcher_token_sheet.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/pages/login_result.dart';
import '../../../stories/domain/entities/story_group_entity.dart';
import '../../../stories/domain/repositories/stories_repository.dart';
import '../../../stories/presentation/pages/story_viewer_args.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../product/domain/entities/product_entity.dart';
import '../../domain/entities/seller_profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';

class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key, this.initialTabIndex});

  final int? initialTabIndex;

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  SellerProfileEntity? _profile;
  List<PostEntity> _newsPosts = [];
  List<PostEntity> _publicationPosts = [];
  bool _loading = true;
  late int _tabIndex;
  bool _updatingAvatar = false;
  bool _isSwitchingAccount = false;
  bool _autoReloadTriggeredForPublications = false;
  List<StoryGroupEntity> _storyGroups = const [];
  Map<String, bool> _newStoriesByUserId = const {};

  @override
  void initState() {
    super.initState();
    _tabIndex = (widget.initialTabIndex ?? 2).clamp(0, 2);
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
      final newsPosts = posts
          .where((p) => p.kind.trim().toLowerCase() == 'news')
          .toList(growable: false);
      var publicationPosts = posts
          .where((p) => p.kind.trim().toLowerCase() == 'publication')
          .toList(growable: false);
      if (publicationPosts.isEmpty) {
        final publicationFeed = await context.read<PostRepository>().searchPublicationsByCursor(
              query: '',
              limit: 100,
              currentUserId: uid,
            );
        publicationPosts = publicationFeed
            .where((p) => p.userId == uid)
            .toList(growable: false);
      }
      // Подсчитываем актуальное количество подписок через followers.
      final followingUsers = await repo.getFollowingUsers(uid);
      final followingCount = followingUsers.length;
      await _loadProfileStories(uid);
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
          _newsPosts = newsPosts;
          _publicationPosts = publicationPosts;
          _loading = false;
          if (publicationPosts.isNotEmpty) {
            _autoReloadTriggeredForPublications = false;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProfileStories(String uid) async {
    setState(() => _loading = true);
    try {
      final allGroups = await context.read<StoriesRepository>().getStoriesGroupedByUser();
      final ownStories = await context.read<StoriesRepository>().getStoriesByUser(uid);
      final peerIds = <String>{};
      try {
        final rows = await supa.Supabase.instance.client
            .from(SupabaseConstants.messagesTable)
            .select('sender_id, receiver_id')
            .or('sender_id.eq.$uid,receiver_id.eq.$uid');
        for (final row in (rows as List<dynamic>)) {
          final map = row as Map<String, dynamic>;
          final senderId = map['sender_id'] as String?;
          final receiverId = map['receiver_id'] as String?;
          if (senderId == null || receiverId == null) continue;
          if (senderId == uid) {
            peerIds.add(receiverId);
          } else if (receiverId == uid) {
            peerIds.add(senderId);
          }
        }
      } catch (_) {
        // Даже если чат-список недоступен, собственные сторис все равно покажем.
      }
      var groups = allGroups
          .where((g) => g.stories.isNotEmpty)
          .where((g) => g.userId == uid || peerIds.contains(g.userId))
          .toList(growable: false);
      final aliveOwnStories = ownStories
          .where((s) => s.expiresAt.isAfter(DateTime.now()))
          .toList(growable: false);
      if (aliveOwnStories.isNotEmpty &&
          groups.every((g) => g.userId != uid)) {
        groups = [
          StoryGroupEntity(
            userId: uid,
            stories: aliveOwnStories,
            userName: context.read<AuthBloc>().state is AuthAuthenticated
                ? (context.read<AuthBloc>().state as AuthAuthenticated).user.username ??
                    (context.read<AuthBloc>().state as AuthAuthenticated).user.name ??
                    (context.read<AuthBloc>().state as AuthAuthenticated).user.email
                : 'Вы',
            userAvatarUrl: context.read<AuthBloc>().state is AuthAuthenticated
                ? (context.read<AuthBloc>().state as AuthAuthenticated).user.avatarUrl
                : null,
          ),
          ...groups,
        ];
      }
      final seenStorage = context.read<ChatStoryListStorage>();
      final nextMap = <String, bool>{};
      for (final g in groups) {
        final latestStoryAt = g.firstStory.createdAt;
        final lastSeenAt = seenStorage.getLastSeenAt(g.userId);
        nextMap[g.userId] = lastSeenAt == null || latestStoryAt.isAfter(lastSeenAt);
      }
      if (!mounted) return;
      setState(() {
        _storyGroups = groups;
        _newStoriesByUserId = nextMap;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
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
              ListTile(
                leading: const Icon(Icons.person_outline_rounded, size: 28),
                title: const Text('Публикация'),
                subtitle: const Text('Личный пост в публикации профиля'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/add-publication');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuickCreateMenu() {
    final state = context.read<AuthBloc>().state;
    if (state is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы создавать публикации')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Создать',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('Прувнуть в ленту'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/add-publication');
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('Сторис'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/add-story');
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Видео'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/add-publication?video=1');
              },
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('Новость'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/add-news');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading &&
        _tabIndex == 2 &&
        _publicationPosts.isEmpty &&
        !_autoReloadTriggeredForPublications) {
      _autoReloadTriggeredForPublications = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _load();
      });
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: _showQuickCreateMenu,
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
                return const Text(
                  'Профиль',
                  style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700),
                );
              }
              final user = state.user;
              final title = (user.username != null && user.username!.isNotEmpty)
                  ? user.username!
                  : user.email;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                ],
              );
            },
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_rounded, size: 26),
            onPressed: () {
              // Меню: темки, чаты, избранное, выйти
              _showProfileMenu(context);
            },
          ),
        ],
      ),
      body: BlocListener<AuthBloc, AuthState>(
        listenWhen: (prev, curr) =>
            curr is AuthAuthenticated &&
            (prev is! AuthAuthenticated || prev.user.id != curr.user.id),
        listener: (context, state) {
          if (state is AuthAuthenticated) _load();
        },
        child: BlocBuilder<AuthBloc, AuthState>(
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
          final ownGroup = _storyGroups.cast<StoryGroupEntity?>().firstWhere(
                (g) => g?.userId == user.id,
                orElse: () => null,
              );
          return _ProfileContent(
            user: user,
            profile: _profile,
            newsPosts: _newsPosts,
            publicationPosts: _publicationPosts,
            tabIndex: _tabIndex,
            onTabChanged: (i) => setState(() => _tabIndex = i),
            onRefresh: _load,
            onAddTap: _showAddChoice,
            onAvatarTap: _changeAvatar,
            updatingAvatar: _updatingAvatar,
            ownStoryGroup: ownGroup,
            onOpenOwnStory: () async {
              if (ownGroup == null) {
                await context.push('/add-story');
                if (!mounted) return;
                await _loadProfileStories(user.id);
                return;
              }
              await context.push(
                '/stories',
                extra: StoryViewerArgs(groups: [ownGroup], initialGroupIndex: 0),
              );
              if (!mounted) return;
              try {
                final latestStoryAt = ownGroup.firstStory.createdAt;
                await context
                    .read<ChatStoryListStorage>()
                    .setLastSeenAt(ownGroup.userId, latestStoryAt);
                if (!mounted) return;
                setState(() {
                  _newStoriesByUserId = {
                    ..._newStoriesByUserId,
                    ownGroup.userId: false,
                  };
                });
              } catch (_) {}
              if (!mounted) return;
              await _loadProfileStories(user.id);
            },
          );
        },
        ),
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

  void _showThemePicker(BuildContext context, {ThemeIndexNotifier? themeNotifier}) {
    final notifier = themeNotifier ?? context.read<ThemeIndexNotifier>();
    final currentIndex = notifier.value;
    showThemePickerSheet(
      context,
      currentIndex: currentIndex,
      onSelect: (index) => notifier.setIndex(index),
      onAddCustom: () async {
        final picker = ImagePicker();
        final xFile = await picker.pickImage(source: ImageSource.gallery);
        if (kDebugMode) {
          debugPrint('[Темки] pickImage result: ${xFile != null ? "ok ${xFile.path}" : "null"}');
        }
        if (xFile == null || !context.mounted) return;
        final bytes = await xFile.readAsBytes();
        if (kDebugMode) {
          debugPrint('[Темки] readAsBytes: ${bytes.length} bytes');
        }
        if (!context.mounted) return;
        await notifier.setCustomThemeFromImageBytes(bytes);
        if (kDebugMode) {
          debugPrint('[Темки] setCustomThemeFromImageBytes done');
        }
      },
    );
  }

  void _showThemePickerWithNotifier(BuildContext context, ThemeIndexNotifier notifier) {
    _showThemePicker(context, themeNotifier: notifier);
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
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Темки'),
              onTap: () {
                final themeNotifier = context.read<ThemeIndexNotifier>();
                final navigator = Navigator.of(context);
                navigator.pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final overlayContext = navigator.context;
                  if (overlayContext.mounted) {
                    _showThemePickerWithNotifier(overlayContext, themeNotifier);
                  }
                });
              },
            ),
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
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Редактировать профиль'),
              onTap: () {
                Navigator.pop(context);
                context.push('/edit-profile');
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Настройки'),
              onTap: () {
                Navigator.pop(context);
                context.push('/profile/settings');
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Выйти'),
              onTap: () {
                final navigator = Navigator.of(context);
                final rootContext = navigator.context;
                final authState = rootContext.read<AuthBloc>().state;
                if (authState is AuthAuthenticated) {
                  final userId = authState.user.id;
                  // Удаляем токен-аккаунт и сохранённый аккаунт текущего пользователя,
                  // чтобы он не появлялся в «Быстром входе» после выхода.
                  try {
                    rootContext.read<AccountManager>().removeAccount(userId);
                  } catch (_) {}
                  try {
                    rootContext.read<MultiAccountStorage>().removeAccount(userId);
                  } catch (_) {}
                }
                navigator.pop();
                rootContext
                    .read<AuthBloc>()
                    .add(const AuthSignOutRequested());
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
    required this.newsPosts,
    required this.publicationPosts,
    required this.tabIndex,
    required this.onTabChanged,
    required this.onRefresh,
    required this.onAddTap,
    required this.onAvatarTap,
    required this.updatingAvatar,
    required this.ownStoryGroup,
    required this.onOpenOwnStory,
  });

  final AppUser user;
  final SellerProfileEntity? profile;
  final List<PostEntity> newsPosts;
  final List<PostEntity> publicationPosts;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onRefresh;
  final VoidCallback onAddTap;
  final VoidCallback onAvatarTap;
  final bool updatingAvatar;
  final StoryGroupEntity? ownStoryGroup;
  final Future<void> Function()? onOpenOwnStory;

  int get _publicationsCount =>
      (profile?.products.length ?? 0) + newsPosts.length + publicationPosts.length;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
              child: DecoratedBox(
                decoration: ThemedContentSurface.profileCardDecoration(
                  radius: ThemedContentSurface.profileUnifiedRadius,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    ThemedContentSurface.profileUnifiedRadius,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFFE8EDF5),
                              Color(0xFFF8FAFD),
                              Colors.white,
                            ],
                            stops: [0.0, 0.45, 1.0],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 26, 20, 18),
                          child: Column(
                            children: [
                              Stack(
                                alignment: Alignment.bottomRight,
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.18),
                                          blurRadius: 20,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: ownStoryGroup != null
                                            ? const LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Color(0xFFFEDA75),
                                                  Color(0xFFFA7E1E),
                                                  Color(0xFFD62976),
                                                  Color(0xFF962FBF),
                                                  Color(0xFF4F5BD5),
                                                ],
                                              )
                                            : null,
                                        color: ownStoryGroup == null
                                            ? Colors.white
                                            : null,
                                      ),
                                      child: GestureDetector(
                                        onTap: () async {
                                          if (onOpenOwnStory != null) {
                                            await onOpenOwnStory!.call();
                                            return;
                                          }
                                          final imageUrl =
                                              user.avatarUrl ?? profile?.avatarUrl;
                                          if (imageUrl == null ||
                                              imageUrl.isEmpty) {
                                            return;
                                          }
                                          showDialog<void>(
                                            context: context,
                                            builder: (ctx) => Dialog(
                                              backgroundColor: Colors.black,
                                              insetPadding:
                                                  const EdgeInsets.all(24),
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
                                          imageUrl: (() {
                                            final base =
                                                user.avatarUrl ?? profile?.avatarUrl;
                                            if (base == null || base.isEmpty) {
                                              return null;
                                            }
                                            return '$base?uid=${user.id}';
                                          })(),
                                          radius: 46,
                                          fallbackText:
                                              user.name ?? user.email,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: GestureDetector(
                                      onTap: updatingAvatar ? null : onAvatarTap,
                                      child: Container(
                                        width: 26,
                                        height: 26,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2.5,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.12),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: updatingAvatar
                                            ? const Padding(
                                                padding: EdgeInsets.all(4),
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(Colors.white),
                                                ),
                                              )
                                            : const Icon(
                                                Icons.add_rounded,
                                                size: 16,
                                                color: Colors.white,
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                (user.username != null &&
                                        user.username!.isNotEmpty)
                                    ? '@${user.username}'
                                    : user.email,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                      color: ThemedContentSurface
                                          .profileTextPrimary,
                                    ),
                              ),
                              if (user.name != null &&
                                  user.name!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  user.name!,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(
                                        color: ThemedContentSurface
                                            .profileTextSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if ((user.bio ?? profile?.bio) != null &&
                          (user.bio ?? profile?.bio)!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F5F9),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              user.bio ?? profile?.bio ?? '',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: ThemedContentSurface
                                        .profileTextSecondary,
                                    height: 1.45,
                                  ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          (user.bio ?? profile?.bio)?.isNotEmpty == true
                              ? 18
                              : 14,
                          12,
                          16,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _StatItem(
                                value: _publicationsCount,
                                label: 'публикаций',
                              ),
                            ),
                            _statDivider(),
                            Expanded(
                              child: _StatItem(
                                value: profile?.followersCount ??
                                    user.followersCount,
                                label: 'подписчиков',
                                onTap: () => context.push('/followers'),
                              ),
                            ),
                            _statDivider(),
                            Expanded(
                              child: _StatItem(
                                value: profile?.followingCount ??
                                    user.followingCount,
                                label: 'подписок',
                                onTap: () => context.push('/following'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: _ProfileTabBar(
                          tabIndex: tabIndex,
                          onChanged: onTabChanged,
                        ),
                      ),
                      ColoredBox(
                        color: const Color(0xFFF2F3F7),
                        child: SizedBox(
                          height: 400,
                          child: tabIndex == 0
                              ? _ProductsGrid(
                                  products: profile?.products ?? [],
                                )
                              : tabIndex == 1
                                  ? _PostsGrid(
                                      posts: newsPosts,
                                      emptyTitle: 'Нет новостей',
                                      emptyActionLabel: 'Опубликовать новость',
                                      onEmptyAction: () => context.push('/add-news'),
                                    )
                                  : _PostsGrid(
                                      posts: publicationPosts,
                                      emptyTitle: 'Нет публикаций',
                                      emptyActionLabel: 'Создать публикацию',
                                      onEmptyAction: () =>
                                          context.push('/add-publication'),
                                    ),
                        ),
                      ),
                    ],
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

Widget _statDivider() => Container(
      width: 1,
      height: 38,
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: const Color(0xFFE2E5EB),
    );

/// Переключатель «Товары / Новости / Лента» в профиле.
class _ProfileTabBar extends StatelessWidget {
  const _ProfileTabBar({
    required this.tabIndex,
    required this.onChanged,
  });

  final int tabIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFECEEF2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ProfileTabChip(
              selected: tabIndex == 2,
              icon: Icons.person_outline_rounded,
              label: 'Лента',
              onTap: () => onChanged(2),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ProfileTabChip(
              selected: tabIndex == 1,
              icon: Icons.article_rounded,
              label: 'Новости',
              onTap: () => onChanged(1),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ProfileTabChip(
              selected: tabIndex == 0,
              icon: Icons.grid_view_rounded,
              label: 'Товары',
              onTap: () => onChanged(0),
            ),
          ),
        ],
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
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 19,
                color: selected
                    ? ThemedContentSurface.profileTextPrimary
                    : const Color(0xFF8E92A0),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? ThemedContentSurface.profileTextPrimary
                      : const Color(0xFF8E92A0),
                ),
              ),
            ],
          ),
        ),
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
            color: ThemedContentSurface.profileTextPrimary,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: ThemedContentSurface.profileTextSecondary,
          ),
        ),
      ],
    );
    final wrapped = Center(child: content);
    if (onTap == null) return wrapped;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: wrapped,
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
  const _PostsGrid({
    required this.posts,
    required this.emptyTitle,
    required this.emptyActionLabel,
    required this.onEmptyAction,
  });

  final List<PostEntity> posts;
  final String emptyTitle;
  final String emptyActionLabel;
  final VoidCallback onEmptyAction;

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
              emptyTitle,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onEmptyAction,
              icon: const Icon(Icons.add),
              label: Text(emptyActionLabel),
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
