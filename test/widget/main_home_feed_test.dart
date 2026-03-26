import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tmr_tau/core/storage/multi_account_storage.dart';
import 'package:tmr_tau/features/auth/domain/entities/app_user.dart';
import 'package:tmr_tau/features/auth/domain/repositories/auth_repository.dart';
import 'package:tmr_tau/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:tmr_tau/features/home/presentation/pages/main_home_page.dart';
import 'package:tmr_tau/features/notifications/domain/repositories/notifications_repository.dart';
import 'package:tmr_tau/features/notifications/presentation/notification_activity_peek_bus.dart';
import 'package:tmr_tau/features/post/domain/entities/post_entity.dart';
import 'package:tmr_tau/features/post/domain/entities/publication_feed_page_result.dart';
import 'package:tmr_tau/features/post/domain/repositories/post_repository.dart';
import 'package:tmr_tau/features/profile/domain/repositories/profile_repository.dart';
import 'package:tmr_tau/features/stories/domain/entities/story_group_entity.dart';
import 'package:tmr_tau/features/stories/domain/repositories/stories_repository.dart';

class MockPostRepository extends Mock implements PostRepository {}

class MockProfileRepository extends Mock implements ProfileRepository {}

class MockStoriesRepository extends Mock implements StoriesRepository {}

class MockNotificationsRepository extends Mock implements NotificationsRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

class MockMultiAccountStorage extends Mock implements MultiAccountStorage {}

void main() {
  late MockPostRepository postRepo;
  late MockProfileRepository profileRepo;
  late MockStoriesRepository storiesRepo;
  late MockNotificationsRepository notificationsRepo;
  late MockAuthRepository authRepo;
  late MockMultiAccountStorage multiStorage;
  late NotificationActivityPeekBus peekBus;

  final samplePost = PostEntity(
    id: 'post-feed-1',
    userId: 'author-1',
    kind: 'publication',
    caption: 'Тестовая подпись в ленте виджет-теста',
    userName: 'Автор теста',
    createdAt: DateTime(2024, 7, 15),
  );

  setUpAll(() {
    registerFallbackValue(
      const SavedAccount(id: 'fb', email: 'fb@local'),
    );
  });

  setUp(() {
    postRepo = MockPostRepository();
    profileRepo = MockProfileRepository();
    storiesRepo = MockStoriesRepository();
    notificationsRepo = MockNotificationsRepository();
    authRepo = MockAuthRepository();
    multiStorage = MockMultiAccountStorage();
    peekBus = NotificationActivityPeekBus();

    when(() => multiStorage.setLastActiveAccountId(any())).thenAnswer((_) async {});

    when(() => profileRepo.getFollowingUsers(any()))
        .thenAnswer((_) async => []);

    when(() => authRepo.userFromCurrentSession()).thenReturn(null);
    when(() => authRepo.fetchUserProfileFromRemote(any()))
        .thenAnswer((_) async => null);

    when(() => storiesRepo.getStoriesGroupedByUser())
        .thenAnswer((_) async => <StoryGroupEntity>[]);
    when(() => storiesRepo.getViewedStoryIds(any()))
        .thenAnswer((_) async => <String>{});

    when(
      () => postRepo.recordPublicationFeedImpression(
        postId: any(named: 'postId'),
        watchedMsDelta: any(named: 'watchedMsDelta'),
        completed: any(named: 'completed'),
      ),
    ).thenAnswer((_) async {});

    when(
      () => postRepo.getPublicationsFeedSubscriptions(
        currentUserId: any(named: 'currentUserId'),
        followingUserIds: any(named: 'followingUserIds'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer(
      (_) async => const PublicationFeedPageResult(posts: [], nextOffset: 0),
    );
  });

  tearDown(() {
    peekBus.dispose();
  });

  /// [GoRouter] нужен, чтобы `context.push` в карточке (комментарий и т.д.) не падал в тестах.
  Future<void> pumpFeed(
    WidgetTester tester, {
    required AuthBloc authBloc,
  }) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const MainHomePage(),
        ),
        GoRoute(
          path: '/notifications',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('stub notifications'))),
        ),
        GoRoute(
          path: '/post/:id',
          builder: (context, state) => Scaffold(
            body: Center(child: Text('stub post ${state.pathParameters['id']}')),
          ),
        ),
        GoRoute(
          path: '/add-story',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('stub add-story'))),
        ),
        GoRoute(
          path: '/add-publication',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('stub add-publication'))),
        ),
        GoRoute(
          path: '/add-news',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('stub add-news'))),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<PostRepository>.value(value: postRepo),
          RepositoryProvider<ProfileRepository>.value(value: profileRepo),
          RepositoryProvider<StoriesRepository>.value(value: storiesRepo),
          RepositoryProvider<NotificationsRepository>.value(
            value: notificationsRepo,
          ),
          RepositoryProvider<NotificationActivityPeekBus>.value(value: peekBus),
        ],
        child: BlocProvider<AuthBloc>.value(
          value: authBloc,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'лента рекомендаций: после загрузки видна подпись публикации',
    (tester) async {
      when(
        () => postRepo.getPublicationsFeedRecommendations(
          currentUserId: null,
          followingUserIds: const <String>[],
          limit: 10,
          discoveryDbOffset: 0,
        ),
      ).thenAnswer(
        (_) async => PublicationFeedPageResult(
          posts: [samplePost],
          nextOffset: 1,
        ),
      );

      final authBloc = AuthBloc(authRepo, multiStorage);
      await pumpFeed(tester, authBloc: authBloc);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Тестовая подпись'), findsOneWidget);
      expect(find.text('Рекомендации'), findsOneWidget);
      expect(find.text('Подписки'), findsOneWidget);

      authBloc.close();
    },
  );

  testWidgets(
    'лента рекомендаций: пустой ответ — текст-заглушка',
    (tester) async {
      when(
        () => postRepo.getPublicationsFeedRecommendations(
          currentUserId: null,
          followingUserIds: const <String>[],
          limit: 10,
          discoveryDbOffset: 0,
        ),
      ).thenAnswer(
        (_) async => const PublicationFeedPageResult(posts: [], nextOffset: 0),
      );

      final authBloc = AuthBloc(authRepo, multiStorage);
      await pumpFeed(tester, authBloc: authBloc);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('Пока нет публикаций в рекомендациях.'),
        findsOneWidget,
      );

      authBloc.close();
    },
  );

  testWidgets(
    'вкладка «Подписки» без авторизации — подсказка войти',
    (tester) async {
      when(
        () => postRepo.getPublicationsFeedRecommendations(
          currentUserId: null,
          followingUserIds: const <String>[],
          limit: 10,
          discoveryDbOffset: 0,
        ),
      ).thenAnswer(
        (_) async => PublicationFeedPageResult(
          posts: [samplePost],
          nextOffset: 1,
        ),
      );

      final authBloc = AuthBloc(authRepo, multiStorage);
      await pumpFeed(tester, authBloc: authBloc);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Подписки'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('Войдите, чтобы видеть публикации подписок.'),
        findsOneWidget,
      );

      authBloc.close();
    },
  );

  testWidgets(
    'после AuthCheckRequested подпись остаётся на экране',
    (tester) async {
      const user = AppUser(
        id: 'user-widget',
        email: 'w@test.com',
        name: 'W',
      );

      when(() => authRepo.userFromCurrentSession()).thenReturn(user);
      when(() => authRepo.fetchUserProfileFromRemote(any()))
          .thenAnswer((_) async => user);

      when(
        () => postRepo.getPublicationsFeedRecommendations(
          currentUserId: any(named: 'currentUserId'),
          followingUserIds: any(named: 'followingUserIds'),
          limit: 10,
          discoveryDbOffset: 0,
        ),
      ).thenAnswer(
        (_) async => PublicationFeedPageResult(
          posts: [samplePost],
          nextOffset: 1,
        ),
      );

      when(() => notificationsRepo.getUnreadCount('user-widget'))
          .thenAnswer((_) async => 0);

      final authBloc = AuthBloc(authRepo, multiStorage);
      await pumpFeed(tester, authBloc: authBloc);
      authBloc.add(const AuthCheckRequested());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.textContaining('Тестовая подпись'), findsOneWidget);

      authBloc.close();
    },
  );

  testWidgets(
    'тап по иконке лайка вызывает PostRepository.toggleLike',
    (tester) async {
      const user = AppUser(
        id: 'user-widget',
        email: 'w@test.com',
        name: 'W',
      );

      final post = samplePost.copyWith(likesCount: 3, isLikedByMe: false);

      when(() => authRepo.userFromCurrentSession()).thenReturn(user);
      when(() => authRepo.fetchUserProfileFromRemote(any()))
          .thenAnswer((_) async => user);

      when(
        () => postRepo.getPublicationsFeedRecommendations(
          currentUserId: any(named: 'currentUserId'),
          followingUserIds: any(named: 'followingUserIds'),
          limit: 10,
          discoveryDbOffset: 0,
        ),
      ).thenAnswer(
        (_) async => PublicationFeedPageResult(
          posts: [post],
          nextOffset: 1,
        ),
      );

      when(() => notificationsRepo.getUnreadCount('user-widget'))
          .thenAnswer((_) async => 0);

      when(() => postRepo.toggleLike('post-feed-1', 'user-widget'))
          .thenAnswer((_) async {});

      when(
        () => postRepo.getPostById(
          any(),
          currentUserId: any(named: 'currentUserId'),
        ),
      ).thenAnswer(
        (_) async => post.copyWith(isLikedByMe: true, likesCount: 4),
      );

      final authBloc = AuthBloc(authRepo, multiStorage);
      await pumpFeed(tester, authBloc: authBloc);
      authBloc.add(const AuthCheckRequested());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      verify(
        () => postRepo.toggleLike('post-feed-1', 'user-widget'),
      ).called(1);

      authBloc.close();
    },
  );
}

