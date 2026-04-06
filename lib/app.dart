import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tmr_tau/l10n/app_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'core/accounts/account_manager.dart';
import 'core/accounts/account_model.dart';
import 'core/accounts/account_repository.dart';
import 'core/accounts/session_restorer.dart';
import 'core/storage/chat_list_storage.dart';
import 'core/storage/chat_story_list_storage.dart';
import 'core/storage/local_reactions_storage.dart';
import 'core/storage/multi_account_storage.dart';
import 'features/chat/data/chat_streak_storage.dart';
import 'features/chat/data/chat_pets_storage.dart';
import 'features/chat/data/chat_sticker_favorites_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/domain/theme_repository.dart';
import 'core/theme/data/theme_repository_impl.dart';
import 'core/theme/theme_index_notifier.dart';
import 'core/auth/oauth_foreground_signal.dart';
import 'core/router/app_router.dart';
import 'core/navigation/search_tab_activation_controller.dart';
import 'core/services/geo_service.dart';
import 'core/network/connectivity_host.dart';
import 'features/auth/data/datasources/auth_remote_datasource.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/domain/repositories/auth_repository.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/chat/presentation/chat_unread_badge_controller.dart';
import 'features/comments/data/repositories/comments_repository_impl.dart';
import 'features/comments/domain/repositories/comments_repository.dart';
import 'features/feed/data/repositories/feed_repository_impl.dart';
import 'features/feed/domain/repositories/feed_repository.dart';
import 'features/feed/presentation/bloc/feed_bloc.dart';
import 'features/news/presentation/bloc/news_bloc.dart';
import 'features/notifications/data/repositories/notifications_repository_impl.dart';
import 'features/notifications/domain/repositories/notifications_repository.dart';
import 'features/notifications/presentation/notification_activity_peek_bus.dart';
import 'features/notifications/presentation/notification_tab_badge_controller.dart';
import 'features/post/data/repositories/post_repository_impl.dart';
import 'features/post/domain/repositories/post_repository.dart';
import 'features/product/data/repositories/categories_repository_impl.dart';
import 'features/product/data/repositories/product_repository_impl.dart';
import 'features/product/domain/repositories/categories_repository.dart';
import 'features/product/domain/repositories/product_repository.dart';
import 'features/product/domain/repositories/product_monetization_repository.dart';
import 'features/product/data/repositories/product_monetization_repository_impl.dart';
import 'features/product/data/services/payment_service.dart';
import 'features/product/presentation/bloc/payment_cubit.dart';
import 'features/profile/data/repositories/profile_repository_impl.dart';
import 'features/profile/domain/repositories/profile_repository.dart';
import 'features/stories/data/datasources/itunes_music_remote_datasource.dart';
import 'features/stories/data/repositories/stories_repository_impl.dart';
import 'features/stories/data/repositories/story_music_search_repository_impl.dart';
import 'features/stories/domain/repositories/stories_repository.dart';
import 'features/stories/domain/repositories/story_music_search_repository.dart';
import 'features/settings/data/repositories/settings_repository_impl.dart';
import 'features/settings/domain/repositories/settings_repository.dart';
import 'features/map/data/datasources/map_remote_datasource.dart';
import 'features/map/data/repositories/map_repository_impl.dart';
import 'features/map/domain/repositories/map_repository.dart';
import 'features/orders/data/repositories/orders_repository_impl.dart';
import 'features/orders/domain/repositories/orders_repository.dart';
import 'features/live_battle/data/repositories/live_battle_repository_impl.dart';
import 'features/live_battle/domain/repositories/live_battle_repository.dart';
import 'features/live_streaming/data/repositories/live_streaming_repository_impl.dart';
import 'features/live_streaming/domain/repositories/live_streaming_repository.dart';
import 'features/tap_game/data/tap_game_local_hall_repository_impl.dart';
import 'features/tap_game/data/tap_game_repository_impl.dart';
import 'features/tap_game/domain/repositories/tap_game_local_hall_repository.dart';
import 'features/tap_game/domain/repositories/tap_game_repository.dart';
import 'core/feedback/feedback_preferences_storage.dart';
import 'core/constants/legal_urls.dart';
import 'core/deep_link/deep_link_coordinator.dart';
import 'core/push/fcm_supabase_coordinator.dart';

/// Чаты: до ~500 сообщений + группы; уведомления: отдельный запрос. Не конкурируют с первой
/// отрисовкой ленты на «Публикациях».
void _scheduleDeferredTabBadgeRefresh(BuildContext context) {
  Future<void>.delayed(const Duration(milliseconds: 500), () {
    if (!context.mounted) return;
    unawaited(context.read<ChatUnreadBadgeController>().refresh());
    unawaited(context.read<NotificationTabBadgeController>().refresh());
  });
}

class TmrTauApp extends StatefulWidget {
  const TmrTauApp({
    super.key,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    this.supabaseInitialized = true,
    required this.localReactionsStorage,
    required this.chatListStorage,
    required this.chatStoryListStorage,
    required this.chatStreakStorage,
    required this.chatPetsStorage,
    required this.chatStickerFavoritesStorage,
    required this.multiAccountStorage,
    required this.accountRepository,
    required this.feedbackPreferencesStorage,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;
  final bool supabaseInitialized;
  final LocalReactionsStorage localReactionsStorage;
  final FeedbackPreferencesStorage feedbackPreferencesStorage;
  final ChatListStorage chatListStorage;
  final ChatStoryListStorage chatStoryListStorage;
  final ChatStreakStorage chatStreakStorage;
  final ChatPetsStorage chatPetsStorage;
  final ChatStickerFavoritesStorage chatStickerFavoritesStorage;
  final MultiAccountStorage multiAccountStorage;
  final AccountRepository accountRepository;

  @override
  State<TmrTauApp> createState() => _TmrTauAppState();
}

class _TmrTauAppState extends State<TmrTauApp> with WidgetsBindingObserver {
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
  late final StoryMusicSearchRepository _storyMusicSearchRepository;
  late final NotificationsRepository _notificationsRepository;
  late final PostRepository _postRepository;
  late final SettingsRepository _settingsRepository;
  late final MapRepository _mapRepository;
  late final OrdersRepository _ordersRepository;
  late final LiveBattleRepository _liveBattleRepository;
  late final LiveStreamingRepository _liveStreamingRepository;
  late final TapGameRepository _tapGameRepository;
  late final AppRouter _appRouter;
  late final GeoService _geoService;
  late final SearchTabActivationController _searchTabActivation;
  late final AccountManager _accountManager;
  late final ThemeRepository _themeRepository;
  late final ThemeIndexNotifier _themeIndexNotifier;
  ChatUnreadBadgeController? _chatUnreadBadgeController;
  NotificationTabBadgeController? _notificationTabBadgeController;
  NotificationActivityPeekBus? _notificationActivityPeekBus;
  DeepLinkCoordinator? _deepLinkCoordinator;
  FcmSupabaseCoordinator? _fcmSupabaseCoordinator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.supabaseInitialized) {
      return;
    }
    _themeRepository = ThemeRepositoryImpl(widget.localReactionsStorage);
    _themeIndexNotifier = ThemeIndexNotifier(_themeRepository);
    _chatUnreadBadgeController =
        ChatUnreadBadgeController(chatListStorage: widget.chatListStorage);
    _notificationActivityPeekBus = NotificationActivityPeekBus();
    _client = supa.Supabase.instance.client;
    _fcmSupabaseCoordinator = FcmSupabaseCoordinator(_client);
    final authDataSource = AuthRemoteDataSourceImpl(_client);
    _authRepository = AuthRepositoryImpl(
      authDataSource,
      _client,
      beforeRemoteSignOut:
          _fcmSupabaseCoordinator!.clearCurrentDeviceTokenBeforeSignOut,
    );
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
    _storyMusicSearchRepository = StoryMusicSearchRepositoryImpl(
      ItunesMusicRemoteDataSource(),
    );
    _notificationsRepository = NotificationsRepositoryImpl(_client);
    _notificationTabBadgeController = NotificationTabBadgeController(
      notificationsRepository: _notificationsRepository,
    );
    _postRepository = PostRepositoryImpl(_client);
    _mapRepository = MapRepositoryImpl(MapRemoteDataSourceImpl(_client));
    _ordersRepository = OrdersRepositoryImpl(_client);
    _liveBattleRepository = LiveBattleRepositoryImpl(_client);
    _liveStreamingRepository = LiveStreamingRepositoryImpl(_client);
    _tapGameRepository = TapGameRepositoryImpl(_client);
    _geoService = const GeoService();
    _searchTabActivation = SearchTabActivationController();
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
      mapRepository: _mapRepository,
      searchTabActivation: _searchTabActivation,
    );
    _deepLinkCoordinator = DeepLinkCoordinator(
      router: _appRouter.router,
      httpsHosts: LegalUrls.deepLinkHosts,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_deepLinkCoordinator?.init());
      _fcmSupabaseCoordinator?.start();
    });
  }

  /// Предыдущее состояние жизненного цикла (для OAuth: iOS часто не шлёт [paused]
  /// при in-app Safari, но шлёт [inactive] при уходе во внешний браузер / шите).
  AppLifecycleState? _previousAppLifecycle;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final prev = _previousAppLifecycle;
    _previousAppLifecycle = state;
    if (state == AppLifecycleState.resumed &&
        prev != null &&
        prev != AppLifecycleState.resumed) {
      OAuthForegroundSignal.instance.notifyForegroundAfterBackground();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deepLinkCoordinator?.dispose();
    _fcmSupabaseCoordinator?.dispose();
    _chatUnreadBadgeController?.dispose();
    _notificationTabBadgeController?.dispose();
    _notificationActivityPeekBus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.supabaseInitialized) {
      return MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        localeListResolutionCallback: (locales, supported) {
          if (locales == null || locales.isEmpty) {
            return const Locale('ru');
          }
          for (final locale in locales) {
            for (final s in supported) {
              if (s.languageCode == locale.languageCode) {
                return s;
              }
            }
          }
          return const Locale('ru');
        },
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
        ChangeNotifierProvider<ChatUnreadBadgeController>.value(
          value: _chatUnreadBadgeController!,
        ),
        ChangeNotifierProvider<NotificationTabBadgeController>.value(
          value: _notificationTabBadgeController!,
        ),
        RepositoryProvider<ChatStoryListStorage>.value(
          value: widget.chatStoryListStorage,
        ),
        RepositoryProvider<ChatStreakStorage>.value(
          value: widget.chatStreakStorage,
        ),
        RepositoryProvider<ChatPetsStorage>.value(
          value: widget.chatPetsStorage,
        ),
        ChangeNotifierProvider<ChatStickerFavoritesStorage>.value(
          value: widget.chatStickerFavoritesStorage,
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
        RepositoryProvider<StoryMusicSearchRepository>.value(
          value: _storyMusicSearchRepository,
        ),
        RepositoryProvider<NotificationsRepository>.value(
          value: _notificationsRepository,
        ),
        RepositoryProvider<NotificationActivityPeekBus>.value(
          value: _notificationActivityPeekBus!,
        ),
        RepositoryProvider<PostRepository>.value(value: _postRepository),
        RepositoryProvider<SettingsRepository>.value(
          value: _settingsRepository,
        ),
        RepositoryProvider<MapRepository>.value(value: _mapRepository),
        RepositoryProvider<OrdersRepository>.value(value: _ordersRepository),
        RepositoryProvider<LiveBattleRepository>.value(
          value: _liveBattleRepository,
        ),
        RepositoryProvider<LiveStreamingRepository>.value(
          value: _liveStreamingRepository,
        ),
        RepositoryProvider<TapGameRepository>.value(value: _tapGameRepository),
        RepositoryProvider<TapGameLocalHallRepository>.value(
          value: TapGameLocalHallRepositoryImpl(),
        ),
        RepositoryProvider<FeedbackPreferencesStorage>.value(
          value: widget.feedbackPreferencesStorage,
        ),
        RepositoryProvider<GeoService>.value(value: _geoService),
        ChangeNotifierProvider<SearchTabActivationController>.value(
          value: _searchTabActivation,
        ),
      ],
      child: BlocProvider(
        create: (context) => AuthBloc(
          _authRepository,
          widget.multiAccountStorage,
        )..add(const AuthCheckRequested()),
        child: BlocProvider(
          create: (context) => PaymentCubit(context.read<PaymentService>()),
          child: BlocListener<AuthBloc, AuthState>(
            listenWhen: (prev, curr) {
              if (curr is! AuthAuthenticated) return false;
              if (prev is! AuthAuthenticated) return true;
              return prev.user.id != curr.user.id;
            },
            listener: (context, state) async {
              if (state is AuthAuthenticated) {
                final paymentCubit = context.read<PaymentCubit>();
                widget.chatListStorage.setActiveAccountId(state.user.id);
                widget.chatStoryListStorage.setActiveAccountId(state.user.id);
                widget.chatStreakStorage.setActiveUserId(state.user.id);
                widget.chatPetsStorage.setActiveUserId(state.user.id);
                widget.chatStickerFavoritesStorage
                    .setActiveUserId(state.user.id);
                // Лайки/репосты в ленте — общий кэш до пользователя; чаты изолированы по accountId в storage.
                await widget.localReactionsStorage.clearReactions();
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
                if (context.mounted) {
                  _scheduleDeferredTabBadgeRefresh(context);
                  unawaited(paymentCubit.initStore());
                }
              }
            },
            child: BlocProvider<NewsBloc>(
              create: (context) => NewsBloc(
                context.read<PostRepository>(),
                context.read<ProfileRepository>(),
              ),
              child: BlocProvider<FeedBloc>(
                create: (context) => FeedBloc(
                  _feedRepository,
                  widget.localReactionsStorage,
                ),
                child: BlocListener<AuthBloc, AuthState>(
                  listenWhen: (prev, curr) {
                    if (curr is! AuthAuthenticated) return false;
                    if (prev is! AuthAuthenticated) return true;
                    return prev.user.id != curr.user.id;
                  },
                  listener: (context, state) {
                    if (state is AuthAuthenticated) {
                      // Лента товаров [FeedBloc] и новости [NewsBloc] грузятся при первом
                      // открытии соответствующих экранов — не при каждом входе в приложение.
                      _scheduleDeferredTabBadgeRefresh(context);
                    }
                  },
                  child: BlocListener<AuthBloc, AuthState>(
                    listenWhen: (prev, curr) =>
                        curr is AuthUnauthenticated || curr is AuthError,
                    listener: (context, state) {
                      widget.chatListStorage.setActiveAccountId(null);
                      widget.chatStoryListStorage.setActiveAccountId(null);
                      widget.chatStreakStorage.setActiveUserId(null);
                      widget.chatPetsStorage.setActiveUserId(null);
                      widget.chatStickerFavoritesStorage
                          .setActiveUserId(null);
                      context.read<ChatUnreadBadgeController>().clear();
                      context.read<NotificationTabBadgeController>().clear();
                      context.read<NewsBloc>().add(const NewsCleared());
                      context.read<FeedRepository>().invalidateFeedCache();
                      context.read<SearchTabActivationController>().reset();
                      context.read<PaymentCubit>().resetForLogout();
                    },
                    child: BlocListener<AuthBloc, AuthState>(
                      listenWhen: (prev, curr) =>
                          curr is AuthUnauthenticated &&
                          prev is AuthAuthenticated,
                      listener: (context, state) {
                        // Сразу экран входа, без заглушки на вкладке «Профиль».
                        _appRouter.router.go('/login');
                      },
                      child: MaterialApp.router(
                        onGenerateTitle: (context) =>
                            AppLocalizations.of(context)!.appTitle,
                        localizationsDelegates:
                            AppLocalizations.localizationsDelegates,
                        supportedLocales: AppLocalizations.supportedLocales,
                        localeListResolutionCallback: (locales, supported) {
                          if (locales == null || locales.isEmpty) {
                            return const Locale('ru');
                          }
                          for (final locale in locales) {
                            for (final s in supported) {
                              if (s.languageCode == locale.languageCode) {
                                return s;
                              }
                            }
                          }
                          return const Locale('ru');
                        },
                        debugShowCheckedModeBanner: false,
                        theme: AppTheme.light,
                        routerConfig: _appRouter.router,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}
