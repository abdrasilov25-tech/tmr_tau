import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import '../../core/theme/theme_decoration_helper.dart';
import '../../core/theme/theme_index_notifier.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/auth/presentation/pages/splash_page.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/feed/presentation/pages/favorites_screen.dart';
import '../../features/feed/presentation/pages/search_page.dart';
import '../../features/news/presentation/pages/news_feed_page.dart';
import '../../features/news/presentation/pages/nearby_feed_page.dart';
import '../../features/notifications/presentation/pages/notifications_activity_page.dart';
import '../../features/notifications/domain/repositories/notifications_repository.dart';
import '../../features/notifications/presentation/notification_activity_peek_bus.dart';
import '../../features/post/domain/entities/post_entity.dart';
import '../../features/comments/domain/repositories/comments_repository.dart';
import '../../features/post/domain/repositories/post_repository.dart';
import '../../features/product/domain/entities/product_entity.dart';
import '../../features/post/presentation/pages/add_post_page.dart';
import '../../features/post/presentation/pages/edit_post_page.dart';
import '../../features/post/presentation/pages/post_detail_page.dart';
import '../../features/post/presentation/widgets/post_detail_route_page.dart';
import '../../features/post/presentation/pages/saved_publications_page.dart';
import '../../features/post_reports/presentation/screens/my_reports_page.dart';
import '../../features/post_reports/presentation/screens/report_post_page.dart';
import '../../features/product/presentation/pages/add_product_page.dart';
import '../../features/product/presentation/pages/edit_product_page.dart';
import '../../features/product/presentation/pages/product_detail_page.dart';
import '../../features/product/presentation/pages/qarmet_wallet_page.dart';
import '../../features/product/presentation/pages/premium_purchase_page.dart';
import '../../features/profile/presentation/pages/my_profile_page.dart';
import '../../features/profile/presentation/pages/seller_profile_page.dart';
import '../../features/profile/presentation/pages/following_page.dart';
import '../../features/profile/presentation/pages/followers_page.dart';
import '../../features/profile/presentation/pages/edit_profile_page.dart';
import '../../features/cart/presentation/pages/cart_page.dart';
import '../../features/chat/presentation/pages/chat_page.dart';
import '../../features/chat/presentation/pages/chats_page.dart';
import '../../features/chat/presentation/chat_unread_badge_controller.dart';
import '../../features/notifications/presentation/notification_tab_badge_controller.dart';
import '../../features/chat/presentation/pages/group_chat_page.dart';
import '../../features/chat/presentation/pages/channel_page.dart';
import '../../features/chat/presentation/pages/group_chat_info_page.dart';
import '../../features/orders/presentation/pages/orders_page.dart';
import '../../features/home/presentation/pages/main_home_page.dart';
import '../../features/home/presentation/pages/publication_discover_search_page.dart';
import '../../features/feed/domain/repositories/feed_repository.dart';
import '../../features/profile/domain/repositories/profile_repository.dart';
import '../../features/stories/presentation/pages/add_story_page.dart';
import '../../features/stories/presentation/pages/story_camera_page.dart';
import '../../features/stories/presentation/pages/live_stream_page.dart';
import '../../features/live_battle/presentation/pages/live_battle_page.dart';
import '../../features/live_battle/presentation/pages/live_battle_lobby_page.dart';
import '../../features/live_battle/presentation/pages/live_battle_history_page.dart';
import '../../features/stories/presentation/pages/story_viewer_page.dart';
import '../../features/stories/presentation/pages/story_viewer_args.dart';
import '../../features/settings/presentation/screens/settings_page.dart';
import '../../features/settings/presentation/screens/blocked_users_page.dart';
import '../../features/settings/presentation/screens/activity_status_page.dart';
import '../../features/settings/presentation/screens/story_controls_page.dart';
import '../../features/settings/presentation/screens/post_visibility_page.dart';
import '../../features/settings/presentation/screens/notifications_page.dart';
import '../../features/settings/presentation/screens/security_page.dart';
import '../../features/settings/presentation/screens/change_password_page.dart';
import '../../features/settings/presentation/screens/connected_accounts_page.dart';
import '../../features/settings/presentation/screens/report_problem_page.dart';
import '../../features/settings/presentation/screens/faq_page.dart';
import '../../features/settings/presentation/screens/terms_page.dart';
import '../../features/settings/presentation/screens/privacy_policy_page.dart';
import '../../features/settings/presentation/screens/delete_account_page.dart';
import '../../features/settings/domain/repositories/settings_repository.dart';
import '../../features/map/domain/repositories/map_repository.dart';
import '../../features/map/domain/usecases/get_nearby_products.dart';
import '../../features/map/presentation/bloc/map_bloc.dart';
import '../../features/map/presentation/pages/map_page.dart';
import '../navigation/search_tab_activation_controller.dart';

/// Deep link `tmrtau://auth/callback?...` в Dart — это [host]=auth и [path]=/callback,
/// а не путь `/auth/callback`. Приводим к маршруту GoRouter.
String? _normalizeTmrtauOAuthLocation(GoRouterState state) {
  final uri = state.uri;
  if (uri.scheme != 'tmrtau') return null;

  if (uri.host == 'auth' &&
      (uri.path == '/callback' || uri.path == 'callback')) {
    final q = uri.query;
    return q.isEmpty ? '/auth/callback' : '/auth/callback?$q';
  }

  if (uri.host.isEmpty && uri.path == '/auth/callback') {
    final q = uri.query;
    return q.isEmpty ? '/auth/callback' : '/auth/callback?$q';
  }

  return null;
}

Widget _shellNavCountBadge({required String label, required Widget icon}) {
  final show = label.isNotEmpty;
  return Badge(
    isLabelVisible: show,
    backgroundColor: const Color(0xFF2563EB),
    textColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    label: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
    child: icon,
  );
}

class AppRouter {
  AppRouter({
    required this.feedRepository,
    required this.productRepository,
    required this.profileRepository,
    required this.notificationsRepository,
    required this.postRepository,
    required this.commentsRepository,
    required this.settingsRepository,
    required this.mapRepository,
    required this.searchTabActivation,
  });

  final FeedRepository feedRepository;
  final dynamic productRepository;
  final ProfileRepository profileRepository;
  final NotificationsRepository notificationsRepository;
  final PostRepository postRepository;
  final CommentsRepository commentsRepository;
  final SettingsRepository settingsRepository;
  final MapRepository mapRepository;
  final SearchTabActivationController searchTabActivation;

  late final GoRouter router = GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final oauthPath = _normalizeTmrtauOAuthLocation(state);
      if (oauthPath != null) {
        return oauthPath;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashPage()),
      GoRoute(
        path: '/login',
        builder: (context, state) {
          final extra = state.extra;
          final map = extra is Map<String, dynamic> ? extra : null;
          final addAccountMode = map != null && map['addAccount'] == true;
          final initialEmail = map != null && map['email'] is String
              ? map['email'] as String
              : null;
          return LoginPage(
            addAccountMode: addAccountMode,
            initialEmail: initialEmail,
          );
        },
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/auth/callback',
        builder: (context, state) {
          final code =
              state.uri.queryParameters['code'] ??
              state.uri.queryParameters['auth_code'];
          return _AuthCallbackPage(authCode: code);
        },
      ),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) {
          final product = state.extra as ProductEntity?;
          if (product == null) {
            return const Scaffold(body: Center(child: Text('Товар не найден')));
          }
          final mention = state.uri.queryParameters['mention'];
          return ProductDetailPage(
            product: product,
            commentsRepository: commentsRepository,
            productRepository: productRepository,
            mentionPrefix: mention,
          );
        },
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) {
              final product = state.extra as ProductEntity?;
              final id = state.pathParameters['id']!;
              if (product == null) {
                return Scaffold(
                  appBar: AppBar(),
                  body: const Center(child: Text('Товар не найден')),
                );
              }
              return EditProductPage(productId: id, product: product);
            },
          ),
        ],
      ),
      GoRoute(
        // Prevent conflict with `/profile/settings`.
        // We allow only UUID-like values for the `:id` parameter.
        path: '/profile/:id([0-9a-fA-F\\-]{36})',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return SellerProfilePage(sellerId: id);
        },
      ),
      GoRoute(
        path: '/add-product',
        builder: (context, state) => const AddProductPage(),
      ),
      GoRoute(
        path: '/qarmet-wallet',
        builder: (context, state) => const QarmetWalletPage(),
      ),
      GoRoute(
        path: '/nearby',
        builder: (context, state) => const NearbyFeedPage(),
      ),
      GoRoute(
        path: '/premium',
        builder: (context, state) => const PremiumPurchasePage(),
      ),
      GoRoute(
        path: '/story-camera',
        builder: (context, state) => const StoryCameraPage(),
      ),
      GoRoute(
        path: '/add-story',
        builder: (context, state) {
          final isVideo = state.uri.queryParameters['video'] == '1';
          final extra = state.extra;
          File? preloadedFile;
          bool preloadedIsVideo = false;
          if (extra is StoryCameraResult) {
            preloadedFile = extra.file;
            preloadedIsVideo = extra.isVideo;
          }
          return AddStoryPage(
            isVideoMode: preloadedIsVideo || isVideo,
            preloadedFile: preloadedFile,
          );
        },
      ),
      GoRoute(
        path: '/live',
        builder: (context, state) => const LiveStreamPage(),
      ),
      GoRoute(
        path: '/live-battle/:battleId',
        builder: (context, state) {
          final battleId = state.pathParameters['battleId']!;
          return LiveBattlePage(battleId: battleId);
        },
      ),
      GoRoute(
        path: '/live-battle-lobby',
        builder: (context, state) => const LiveBattleLobbyPage(),
      ),
      GoRoute(
        path: '/live-battle-history',
        builder: (context, state) => const LiveBattleHistoryPage(),
      ),
      GoRoute(
        path: '/stories',
        builder: (context, state) {
          final args = state.extra as StoryViewerArgs?;
          if (args == null || args.groups.isEmpty) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: Text(
                  'Нет историй',
                  style: TextStyle(color: Colors.grey.shade400),
                ),
              ),
            );
          }
          return StoryViewerPage(
            groups: args.groups,
            initialGroupIndex: args.initialGroupIndex,
          );
        },
      ),
      GoRoute(
        path: '/post/:id',
        builder: (context, state) {
          final replyTo = state.uri.queryParameters['replyTo'];
          final post = state.extra as PostEntity?;
          if (post != null) {
            return PostDetailPage(
              post: post,
              postRepository: postRepository,
              replyToCommentId: replyTo,
            );
          }
          final id = state.pathParameters['id']!;
          return PostDetailRoutePage(
            postId: id,
            postRepository: postRepository,
            replyToCommentId: replyTo,
          );
        },
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) {
              final post = state.extra as PostEntity?;
              if (post == null) {
                return Scaffold(
                  appBar: AppBar(),
                  body: const Center(child: Text('Новость не найдена')),
                );
              }
              return EditPostPage(post: post);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/report-post/:postId',
        builder: (context, state) {
          final postId = state.pathParameters['postId']!;
          return ReportPostPage(postId: postId);
        },
      ),
      GoRoute(
        path: '/my-reports',
        builder: (context, state) => const MyReportsPage(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsActivityPage(),
      ),
      GoRoute(
        path: '/profile/settings',
        builder: (context, state) => const SettingsPage(),
        routes: [
          GoRoute(
            path: 'change-password',
            builder: (context, state) => const ChangePasswordPage(),
          ),
          GoRoute(
            path: 'connected-accounts',
            builder: (context, state) => const ConnectedAccountsPage(),
          ),
          GoRoute(
            path: 'blocked-users',
            builder: (context, state) => const BlockedUsersPage(),
          ),
          GoRoute(
            path: 'activity-status',
            builder: (context, state) => const ActivityStatusPage(),
          ),
          GoRoute(
            path: 'story-controls',
            builder: (context, state) => const StoryControlsPage(),
          ),
          GoRoute(
            path: 'post-visibility',
            builder: (context, state) => const PostVisibilityPage(),
          ),
          GoRoute(
            path: 'notifications',
            builder: (context, state) => const NotificationsPage(),
          ),
          GoRoute(
            path: 'security',
            builder: (context, state) => const SecurityPage(),
          ),
          GoRoute(
            path: 'report-problem',
            builder: (context, state) => const ReportProblemPage(),
          ),
          GoRoute(path: 'faq', builder: (context, state) => const FaqPage()),
          GoRoute(
            path: 'terms',
            builder: (context, state) => const TermsPage(),
          ),
          GoRoute(
            path: 'privacy-policy',
            builder: (context, state) => const PrivacyPolicyPage(),
          ),
          GoRoute(
            path: 'delete-account',
            builder: (context, state) => const DeleteAccountPage(),
          ),
        ],
      ),
      GoRoute(
        path: '/add-news',
        builder: (context, state) => const AddPostPage(kind: 'news'),
      ),
      GoRoute(
        path: '/add-publication',
        builder: (context, state) {
          final initialVideo = state.uri.queryParameters['video'] == '1';
          return AddPostPage(
            kind: 'publication',
            initialVideoMode: initialVideo,
          );
        },
      ),
      GoRoute(path: '/cart', builder: (context, state) => const CartPage()),
      GoRoute(path: '/orders', builder: (context, state) => const OrdersPage()),
      GoRoute(
        path: '/home-main',
        builder: (context, state) => const MainHomePage(),
      ),
      GoRoute(
        path: '/discover-publications',
        builder: (context, state) => const PublicationDiscoverSearchPage(),
      ),
      GoRoute(
        path: '/chat/:peerId',
        builder: (context, state) {
          final peerId = state.pathParameters['peerId']!;
          final peerName = state.uri.queryParameters['name'] ?? 'Продавец';
          final markRead = state.uri.queryParameters['markRead'] != '0';
          return ChatPage(
            peerId: peerId,
            peerName: peerName,
            markReadOnOpen: markRead,
          );
        },
      ),
      GoRoute(path: '/chats', builder: (context, state) => const ChatsPage()),
      GoRoute(
        path: '/chat-group/:groupId',
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          final groupName =
              state.uri.queryParameters['name'] ?? 'Групповой чат';
          final officialCityChat =
              state.uri.queryParameters['city'] == '1';
          return GroupChatPage(
            groupId: groupId,
            groupName: groupName,
            officialCityChat: officialCityChat,
          );
        },
      ),
      GoRoute(
        path: '/chat-group/:groupId/info',
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          final officialCityChat =
              state.uri.queryParameters['city'] == '1';
          return GroupChatInfoPage(
            groupId: groupId,
            officialCityChatHint: officialCityChat,
          );
        },
      ),
      GoRoute(
        path: '/channel/:channelId',
        builder: (context, state) {
          final channelId = state.pathParameters['channelId']!;
          final title = state.uri.queryParameters['title'] ?? 'Мой канал';
          return ChannelPage(channelId: channelId, title: title);
        },
      ),
      GoRoute(
        path: '/favorites',
        builder: (context, state) =>
            FavoritesScreen(productRepository: productRepository),
      ),
      GoRoute(
        path: '/saved-publications',
        builder: (context, state) => const SavedPublicationsPage(),
      ),
      GoRoute(
        path: '/following',
        builder: (context, state) => const FollowingPage(),
      ),
      GoRoute(
        path: '/followers',
        builder: (context, state) => const FollowersPage(),
      ),
      GoRoute(
        path: '/edit-profile',
        builder: (context, state) => const EditProfilePage(),
      ),
      GoRoute(
        path: '/home',
        redirect: (context, state) {
          final path = state.uri.path;
          if (path == '/home' || path == '/home/') return '/home/feed';
          return null;
        },
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) => _MainShell(
              navigationShell: navigationShell,
              searchTabActivation: searchTabActivation,
            ),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'feed',
                    builder: (context, state) => const MainHomePage(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'search',
                    builder: (context, state) => SearchPage(
                      productRepository: productRepository,
                      settingsRepository: settingsRepository,
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'map',
                    builder: (context, state) =>
                        _MapBranchHost(mapRepository: mapRepository),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'chats',
                    builder: (context, state) => const ChatsPage(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'news',
                    builder: (context, state) => const NewsFeedPage(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'profile',
                    builder: (context, state) {
                      final tabParam = state.uri.queryParameters['tab'];
                      final parsed = tabParam == null
                          ? null
                          : int.tryParse(tabParam);
                      return MyProfilePage(initialTabIndex: parsed);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _AuthCallbackPage extends StatefulWidget {
  const _AuthCallbackPage({required this.authCode});

  final String? authCode;

  @override
  State<_AuthCallbackPage> createState() => _AuthCallbackPageState();
}

class _AuthCallbackPageState extends State<_AuthCallbackPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _exchangeAndCheck());
  }

  Future<void> _exchangeAndCheck() async {
    final code = widget.authCode;
    if (code != null && code.isNotEmpty) {
      try {
        await supa.Supabase.instance.client.auth.exchangeCodeForSession(code);
      } catch (_) {
        // Если обмен кода не удался — просто продолжаем до проверки AuthBloc.
      }
    }
    if (!mounted) return;
    context.read<AuthBloc>().add(const AuthCheckRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          context.go('/home/feed');
        }
        if (state is AuthUnauthenticated || state is AuthError) {
          context.go('/login');
        }
      },
      child: const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

/// Один [MapBloc] на вкладку «Рядом»: не пересоздаём при перерисовке shell (тема и т.д.).
class _MapBranchHost extends StatefulWidget {
  const _MapBranchHost({required this.mapRepository});

  final MapRepository mapRepository;

  @override
  State<_MapBranchHost> createState() => _MapBranchHostState();
}

class _MapBranchHostState extends State<_MapBranchHost>
    with AutomaticKeepAliveClientMixin {
  MapBloc? _bloc;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bloc ??= MapBloc(GetNearbyProducts(widget.mapRepository));
  }

  @override
  void dispose() {
    _bloc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocProvider.value(value: _bloc!, child: const MapPage());
  }
}

class _MainShell extends StatefulWidget {
  const _MainShell({
    required this.navigationShell,
    required this.searchTabActivation,
  });

  final StatefulNavigationShell navigationShell;
  final SearchTabActivationController searchTabActivation;

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell>
    with SingleTickerProviderStateMixin {
  late AnimationController _branchAnim;

  @override
  void initState() {
    super.initState();
    _branchAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..value = 1;
  }

  @override
  void didUpdateWidget(covariant _MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationShell.currentIndex !=
        widget.navigationShell.currentIndex) {
      _branchAnim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _branchAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.read<ThemeIndexNotifier>();
    final chatUnread = context.read<ChatUnreadBadgeController>();
    final notificationTabs = context.read<NotificationTabBadgeController>();
    return ListenableBuilder(
      listenable: Listenable.merge([
        themeNotifier.listenable,
        chatUnread,
        notificationTabs,
      ]),
      builder: (context, _) {
        final decoration = themeDecoration(
          themeNotifier.value,
          themeNotifier.customImagePath,
        );
        final chatsBadge = chatUnread.badgeShortLabel;
        final publicationsBadge = notificationTabs.publicationsBadgeLabel;
        final newsBadge = notificationTabs.newsBadgeLabel;
        final fade = CurvedAnimation(
          parent: _branchAnim,
          curve: Curves.easeOutCubic,
        );
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Container(decoration: decoration),
              FadeTransition(
                opacity: fade,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.012),
                    end: Offset.zero,
                  ).animate(fade),
                  child: widget.navigationShell,
                ),
              ),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: NavigationBar(
              selectedIndex: widget.navigationShell.currentIndex,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              height: 56,
              onDestinationSelected: (index) {
                widget.navigationShell.goBranch(index);
                if (index == 1) {
                  widget.searchTabActivation.markSearchTabSelected();
                }
                if (index == 0) {
                  context
                      .read<NotificationActivityPeekBus>()
                      .pulsePublicationsTab();
                }
                if (index == 3) {
                  context.read<ChatUnreadBadgeController>().refresh();
                }
                if (index == 0 || index == 4) {
                  unawaited(
                    context.read<NotificationTabBadgeController>().refresh(),
                  );
                }
              },
              backgroundColor: Colors.transparent,
              elevation: 0,
              indicatorColor: Colors.transparent,
              destinations: [
                NavigationDestination(
                  icon: _shellNavCountBadge(
                    label: publicationsBadge,
                    icon: const Icon(Icons.home_outlined, size: 26),
                  ),
                  selectedIcon: _shellNavCountBadge(
                    label: publicationsBadge,
                    icon: const Icon(Icons.home_rounded, size: 26),
                  ),
                  label: 'Публикации',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.search_outlined, size: 26),
                  selectedIcon: Icon(Icons.search_rounded, size: 26),
                  label: 'Поиск',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.map_outlined, size: 26),
                  selectedIcon: Icon(Icons.map_rounded, size: 26),
                  label: 'Рядом',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: chatsBadge.isNotEmpty,
                    backgroundColor: const Color(0xFF2563EB),
                    textColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    label: Text(
                      chatsBadge,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Icon(Icons.chat_bubble_outline_rounded, size: 26),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: chatsBadge.isNotEmpty,
                    backgroundColor: const Color(0xFF2563EB),
                    textColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    label: Text(
                      chatsBadge,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Icon(Icons.chat_rounded, size: 26),
                  ),
                  label: 'Чаты',
                ),
                NavigationDestination(
                  icon: _shellNavCountBadge(
                    label: newsBadge,
                    icon: const Icon(Icons.article_outlined, size: 26),
                  ),
                  selectedIcon: _shellNavCountBadge(
                    label: newsBadge,
                    icon: const Icon(Icons.article_rounded, size: 26),
                  ),
                  label: 'Новости',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded, size: 26),
                  selectedIcon: Icon(Icons.person_rounded, size: 26),
                  label: 'Профиль',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
