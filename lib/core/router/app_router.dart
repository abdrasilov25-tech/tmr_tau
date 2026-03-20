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
import '../../features/feed/presentation/pages/feed_page.dart';
import '../../features/feed/presentation/pages/search_page.dart';
import '../../features/news/presentation/pages/news_feed_page.dart';
import '../../features/notifications/presentation/pages/notifications_activity_page.dart';
import '../../features/notifications/domain/repositories/notifications_repository.dart';
import '../../features/post/domain/entities/post_entity.dart';
import '../../features/comments/domain/repositories/comments_repository.dart';
import '../../features/post/domain/repositories/post_repository.dart';
import '../../features/product/domain/entities/product_entity.dart';
import '../../features/post/presentation/pages/add_post_page.dart';
import '../../features/post/presentation/pages/edit_post_page.dart';
import '../../features/post/presentation/pages/post_detail_page.dart';
import '../../features/post_reports/presentation/screens/my_reports_page.dart';
import '../../features/post_reports/presentation/screens/report_post_page.dart';
import '../../features/product/presentation/pages/add_product_page.dart';
import '../../features/product/presentation/pages/edit_product_page.dart';
import '../../features/product/presentation/pages/product_detail_page.dart';
import '../../features/profile/presentation/pages/my_profile_page.dart';
import '../../features/profile/presentation/pages/seller_profile_page.dart';
import '../../features/profile/presentation/pages/following_page.dart';
import '../../features/profile/presentation/pages/followers_page.dart';
import '../../features/profile/presentation/pages/edit_profile_page.dart';
import '../../features/cart/presentation/pages/cart_page.dart';
import '../../features/chat/presentation/pages/chat_page.dart';
import '../../features/chat/presentation/pages/chats_page.dart';
import '../../features/orders/presentation/pages/orders_page.dart';
import '../../features/home/presentation/pages/main_home_page.dart';
import '../../features/feed/domain/repositories/feed_repository.dart';
import '../../features/profile/domain/repositories/profile_repository.dart';
import '../../features/stories/presentation/pages/add_story_page.dart';
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

class AppRouter {
  AppRouter({
    required this.feedRepository,
    required this.productRepository,
    required this.profileRepository,
    required this.notificationsRepository,
    required this.postRepository,
    required this.commentsRepository,
  });

  final FeedRepository feedRepository;
  final dynamic productRepository;
  final ProfileRepository profileRepository;
  final NotificationsRepository notificationsRepository;
  final PostRepository postRepository;
  final CommentsRepository commentsRepository;

  late final GoRouter router = GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) {
          final extra = state.extra;
          final map = extra is Map<String, dynamic> ? extra : null;
          final addAccountMode = map != null && map['addAccount'] == true;
          final initialEmail =
              map != null && map['email'] is String ? map['email'] as String : null;
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
          final code = state.uri.queryParameters['code'] ??
              state.uri.queryParameters['auth_code'];
          return _AuthCallbackPage(authCode: code);
        },
      ),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) {
          final product = state.extra as ProductEntity?;
          if (product == null) {
            return const Scaffold(
              body: Center(child: Text('Товар не найден')),
            );
          }
          return ProductDetailPage(
            product: product,
            commentsRepository: commentsRepository,
            productRepository: productRepository,
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
        path: '/add-story',
        builder: (context, state) {
          final isVideo = state.uri.queryParameters['video'] == '1';
          return AddStoryPage(isVideoMode: isVideo);
        },
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
          final post = state.extra as PostEntity?;
          if (post != null) {
            return PostDetailPage(
              post: post,
              postRepository: postRepository,
            );
          }
          final id = state.pathParameters['id']!;
          return FutureBuilder<PostEntity?>(
            future: postRepository.getPostById(id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              final fetched = snapshot.data;
              if (fetched == null) {
                return const Scaffold(
                  body: Center(child: Text('Новость не найдена')),
                );
              }
              return PostDetailPage(
                post: fetched,
                postRepository: postRepository,
              );
            },
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
            builder: (context, state) =>
                const StoryControlsPage(),
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
          GoRoute(
            path: 'faq',
            builder: (context, state) => const FaqPage(),
          ),
          GoRoute(
            path: 'terms',
            builder: (context, state) => const TermsPage(),
          ),
          GoRoute(
            path: 'privacy-policy',
            builder: (context, state) => const PrivacyPolicyPage(),
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
      GoRoute(
        path: '/cart',
        builder: (context, state) => const CartPage(),
      ),
      GoRoute(
        path: '/orders',
        builder: (context, state) => const OrdersPage(),
      ),
      GoRoute(
        path: '/home-main',
        builder: (context, state) => const MainHomePage(),
      ),
      GoRoute(
        path: '/chat/:peerId',
        builder: (context, state) {
          final peerId = state.pathParameters['peerId']!;
          final peerName = state.uri.queryParameters['name'] ?? 'Продавец';
          final markRead = state.uri.queryParameters['markRead'] != '0';
          return ChatPage(peerId: peerId, peerName: peerName, markReadOnOpen: markRead);
        },
      ),
      GoRoute(
        path: '/chats',
        builder: (context, state) => const ChatsPage(),
      ),
      GoRoute(
        path: '/favorites',
        builder: (context, state) => FavoritesScreen(
          productRepository: productRepository,
        ),
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
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'add',
                    builder: (context, state) => const AddProductPage(),
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
                      final parsed = tabParam == null ? null : int.tryParse(tabParam);
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
      child: const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _MainShell extends StatelessWidget {
  const _MainShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.read<ThemeIndexNotifier>();
    return ListenableBuilder(
      listenable: themeNotifier.listenable,
      builder: (context, _) {
        final decoration = themeDecoration(
          themeNotifier.value,
          themeNotifier.customImagePath,
        );
        return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(decoration: decoration),
          navigationShell,
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) {
            // Меняем только активную ветку shell-роута.
            navigationShell.goBranch(index);
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          indicatorColor: Colors.transparent,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, size: 26),
              selectedIcon: Icon(Icons.home_rounded, size: 26),
              label: 'Публикации',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_outlined, size: 26),
              selectedIcon: Icon(Icons.search_rounded, size: 26),
              label: 'Поиск',
            ),
            NavigationDestination(
              icon: Icon(Icons.add_circle_outline, size: 28),
              selectedIcon: Icon(Icons.add_circle_rounded, size: 28),
              label: 'Добавить',
            ),
            NavigationDestination(
              icon: Icon(Icons.article_outlined, size: 26),
              selectedIcon: Icon(Icons.article_rounded, size: 26),
              label: 'Новости',
            ),
            NavigationDestination(
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
