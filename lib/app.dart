import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'core/accounts/account_manager.dart';
import 'core/accounts/account_model.dart';
import 'core/accounts/account_repository.dart';
import 'core/accounts/session_restorer.dart';
import 'core/storage/chat_list_storage.dart';
import 'core/storage/chat_story_list_storage.dart';
import 'core/storage/local_reactions_storage.dart';
import 'core/storage/multi_account_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/domain/theme_repository.dart';
import 'core/theme/data/theme_repository_impl.dart';
import 'core/theme/theme_index_notifier.dart';
import 'core/router/app_router.dart';
import 'core/network/connectivity_host.dart';
import 'features/auth/data/datasources/auth_remote_datasource.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/domain/repositories/auth_repository.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/comments/data/repositories/comments_repository_impl.dart';
import 'features/comments/domain/repositories/comments_repository.dart';
import 'features/feed/data/repositories/feed_repository_impl.dart';
import 'features/feed/domain/repositories/feed_repository.dart';
import 'features/feed/presentation/bloc/feed_bloc.dart';
import 'features/notifications/data/repositories/notifications_repository_impl.dart';
import 'features/notifications/domain/repositories/notifications_repository.dart';
import 'features/post/data/repositories/post_repository_impl.dart';
import 'features/post/domain/repositories/post_repository.dart';
import 'features/product/data/repositories/categories_repository_impl.dart';
import 'features/product/data/repositories/product_repository_impl.dart';
import 'features/product/domain/repositories/categories_repository.dart';
import 'features/product/domain/repositories/product_repository.dart';
import 'features/product/domain/repositories/product_monetization_repository.dart';
import 'features/product/data/repositories/product_monetization_repository_impl.dart';
import 'features/product/data/services/payment_service.dart';
import 'features/profile/data/repositories/profile_repository_impl.dart';
import 'features/profile/domain/repositories/profile_repository.dart';
import 'features/stories/data/repositories/stories_repository_impl.dart';
import 'features/stories/domain/repositories/stories_repository.dart';
import 'features/settings/data/repositories/settings_repository_impl.dart';
import 'features/settings/domain/repositories/settings_repository.dart';

class TmrTauApp extends StatefulWidget {
  const TmrTauApp({
    super.key,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    this.supabaseInitialized = true,
    required this.localReactionsStorage,
    required this.chatListStorage,
    required this.chatStoryListStorage,
    required this.multiAccountStorage,
    required this.accountRepository,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;
  final bool supabaseInitialized;
  final LocalReactionsStorage localReactionsStorage;
  final ChatListStorage chatListStorage;
  final ChatStoryListStorage chatStoryListStorage;
  final MultiAccountStorage multiAccountStorage;
  final AccountRepository accountRepository;

  @override
  State<TmrTauApp> createState() => _TmrTauAppState();
}

class _TmrTauAppState extends State<TmrTauApp> {
  late final supa.SupabaseClient _client;
  late final AuthRepository _authRepository;
  late final ProductRepository _productRepository;
  late final ProductMonetizationRepository _productMonetizationRepository;
  late final PaymentService _paymentService;
  late final CategoriesRepository _categoriesRepository;
  late final FeedRepository _feedRepository;
  late final ProfileRepository _profileRepository;
  late final CommentsRepository _commentsRepository;
  late final StoriesRepository _storiesRepository;
  late final NotificationsRepository _notificationsRepository;
  late final PostRepository _postRepository;
  late final SettingsRepository _settingsRepository;
  late final AppRouter _appRouter;
  late final AccountManager _accountManager;
  late final ThemeRepository _themeRepository;
  late final ThemeIndexNotifier _themeIndexNotifier;

  @override
  void initState() {
    super.initState();
    if (!widget.supabaseInitialized) {
      return;
    }
    _themeRepository = ThemeRepositoryImpl(widget.localReactionsStorage);
    _themeIndexNotifier = ThemeIndexNotifier(_themeRepository);
    _client = supa.Supabase.instance.client;
    final authDataSource = AuthRemoteDataSourceImpl(_client);
    _authRepository = AuthRepositoryImpl(authDataSource, _client);
    _productRepository = ProductRepositoryImpl(_client);
    _productMonetizationRepository = ProductMonetizationRepositoryImpl(_client);
    _paymentService = PaymentService(_client);
    _categoriesRepository = CategoriesRepositoryImpl(_client);
    _profileRepository = ProfileRepositoryImpl(_client);
    _settingsRepository = SettingsRepositoryImpl(_client);
    _feedRepository = FeedRepositoryImpl(
      _productRepository,
      _profileRepository,
      _settingsRepository,
    );
    _commentsRepository = CommentsRepositoryImpl(_client);
    _storiesRepository = StoriesRepositoryImpl(_client);
    _notificationsRepository = NotificationsRepositoryImpl(_client);
    _postRepository = PostRepositoryImpl(_client);
    _accountManager = AccountManager(
      widget.accountRepository,
      SessionRestorer(_client),
    );
    _appRouter = AppRouter(
      feedRepository: _feedRepository,
      productRepository: _productRepository,
      profileRepository: _profileRepository,
      notificationsRepository: _notificationsRepository,
      postRepository: _postRepository,
      commentsRepository: _commentsRepository,
      settingsRepository: _settingsRepository,
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.supabaseInitialized) {
      return MaterialApp(
        title: 'tmr_tau',
        theme: ThemeData.light(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'Supabase не настроен. Создайте файл .env из .env.example '
                    'и укажите SUPABASE_URL и SUPABASE_ANON_KEY',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return ConnectivityHost(
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<LocalReactionsStorage>.value(
            value: widget.localReactionsStorage),
        RepositoryProvider<ChatListStorage>.value(value: widget.chatListStorage),
        RepositoryProvider<ChatStoryListStorage>.value(
          value: widget.chatStoryListStorage,
        ),
        RepositoryProvider<MultiAccountStorage>.value(
            value: widget.multiAccountStorage),
        RepositoryProvider<AccountRepository>.value(
            value: widget.accountRepository),
        RepositoryProvider<AccountManager>.value(value: _accountManager),
        RepositoryProvider<ThemeIndexNotifier>.value(value: _themeIndexNotifier),
        RepositoryProvider<AuthRepository>.value(value: _authRepository),
        RepositoryProvider<FeedRepository>.value(value: _feedRepository),
        RepositoryProvider<ProductRepository>.value(value: _productRepository),
        RepositoryProvider<ProductMonetizationRepository>.value(
          value: _productMonetizationRepository,
        ),
        RepositoryProvider<PaymentService>.value(value: _paymentService),
        RepositoryProvider<CategoriesRepository>.value(
            value: _categoriesRepository),
        RepositoryProvider<ProfileRepository>.value(value: _profileRepository),
        RepositoryProvider<CommentsRepository>.value(value: _commentsRepository),
        RepositoryProvider<StoriesRepository>.value(value: _storiesRepository),
        RepositoryProvider<NotificationsRepository>.value(
          value: _notificationsRepository,
        ),
        RepositoryProvider<PostRepository>.value(value: _postRepository),
        RepositoryProvider<SettingsRepository>.value(
          value: _settingsRepository,
        ),
      ],
      child: BlocProvider(
        create: (context) => AuthBloc(
          _authRepository,
          widget.multiAccountStorage,
        )..add(const AuthCheckRequested()),
        child: BlocListener<AuthBloc, AuthState>(
          listener: (context, state) async {
            if (state is AuthAuthenticated) {
              // При входе/переключении аккаунта очищаем локальные лайки/репосты и состояние чатов,
              // чтобы прошлый аккаунт не «перетекал» в новый.
              await widget.localReactionsStorage.clearReactions();
              await widget.chatListStorage.clearAll();
              await widget.chatStoryListStorage.clearAll();
              if (!context.mounted) return;
              final session =
                  supa.Supabase.instance.client.auth.currentSession;
              final refreshToken = session?.refreshToken;
              if (refreshToken == null || refreshToken.isEmpty) {
                return;
              }
              final account = AccountModel(
                userId: state.user.id,
                email: state.user.email,
                refreshToken: refreshToken,
                accessToken: session?.accessToken,
                username: state.user.username,
              );
              await context.read<AccountManager>().addOrUpdateAccount(account);
            }
          },
          child: BlocProvider<FeedBloc>(
            create: (context) => FeedBloc(
              _feedRepository,
              widget.localReactionsStorage,
            ),
            child: BlocListener<AuthBloc, AuthState>(
              listenWhen: (prev, curr) =>
                  curr is AuthAuthenticated && (prev is! AuthAuthenticated || prev.user.id != curr.user.id),
              listener: (context, state) {
                if (state is AuthAuthenticated) {
                  context.read<FeedBloc>().add(FeedLoaded(currentUserId: state.user.id));
                }
              },
              child: MaterialApp.router(
                title: 'tmr_tau',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                routerConfig: _appRouter.router,
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}
