import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
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
import 'features/product/data/repositories/product_repository_impl.dart';
import 'features/product/domain/repositories/product_repository.dart';
import 'features/profile/data/repositories/profile_repository_impl.dart';
import 'features/profile/domain/repositories/profile_repository.dart';
import 'features/stories/data/repositories/stories_repository_impl.dart';
import 'features/stories/domain/repositories/stories_repository.dart';

class TmrTauApp extends StatefulWidget {
  const TmrTauApp({
    super.key,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    this.supabaseInitialized = true,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;
  final bool supabaseInitialized;

  @override
  State<TmrTauApp> createState() => _TmrTauAppState();
}

class _TmrTauAppState extends State<TmrTauApp> {
  late final SupabaseClient _client;
  late final AuthRepository _authRepository;
  late final ProductRepository _productRepository;
  late final FeedRepository _feedRepository;
  late final ProfileRepository _profileRepository;
  late final CommentsRepository _commentsRepository;
  late final StoriesRepository _storiesRepository;
  late final NotificationsRepository _notificationsRepository;
  late final PostRepository _postRepository;
  late final AppRouter _appRouter;

  @override
  void initState() {
    super.initState();
    if (!widget.supabaseInitialized) {
      return;
    }
    _client = Supabase.instance.client;
    final authDataSource = AuthRemoteDataSourceImpl(_client);
    _authRepository = AuthRepositoryImpl(authDataSource, _client);
    _productRepository = ProductRepositoryImpl(_client);
    _profileRepository = ProfileRepositoryImpl(_client);
    _feedRepository = FeedRepositoryImpl(_productRepository, _profileRepository);
    _commentsRepository = CommentsRepositoryImpl(_client);
    _storiesRepository = StoriesRepositoryImpl(_client);
    _notificationsRepository = NotificationsRepositoryImpl(_client);
    _postRepository = PostRepositoryImpl(_client);
    _appRouter = AppRouter(
      feedRepository: _feedRepository,
      productRepository: _productRepository,
      profileRepository: _profileRepository,
      notificationsRepository: _notificationsRepository,
      postRepository: _postRepository,
    );
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
                    'Supabase не настроен. Укажите SUPABASE_URL и SUPABASE_ANON_KEY в main.dart',
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
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>.value(value: _authRepository),
        RepositoryProvider<FeedRepository>.value(value: _feedRepository),
        RepositoryProvider<ProductRepository>.value(value: _productRepository),
        RepositoryProvider<ProfileRepository>.value(value: _profileRepository),
        RepositoryProvider<CommentsRepository>.value(value: _commentsRepository),
        RepositoryProvider<StoriesRepository>.value(value: _storiesRepository),
        RepositoryProvider<NotificationsRepository>.value(
            value: _notificationsRepository),
        RepositoryProvider<PostRepository>.value(value: _postRepository),
      ],
      child: BlocProvider(
        create: (context) => AuthBloc(_authRepository)..add(const AuthCheckRequested()),
        child: BlocProvider(
          create: (context) => FeedBloc(_feedRepository),
          child: MaterialApp.router(
          title: 'tmr_tau',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          routerConfig: _appRouter.router,
        ),
          ),
      ),
    );
  }
}
