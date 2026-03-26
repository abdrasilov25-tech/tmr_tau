import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tmr_tau/features/news/presentation/bloc/news_bloc.dart';
import 'package:tmr_tau/features/post/domain/entities/post_entity.dart';
import 'package:tmr_tau/features/post/domain/repositories/post_repository.dart';

class MockPostRepository extends Mock implements PostRepository {}

void main() {
  late MockPostRepository mockRepo;
  final t0 = DateTime(2024, 6, 1);

  PostEntity post({
    required String id,
    String kind = 'news',
    int likes = 0,
    bool liked = false,
    int reposts = 0,
    bool reposted = false,
  }) =>
      PostEntity(
        id: id,
        userId: 'author',
        kind: kind,
        createdAt: t0,
        likesCount: likes,
        isLikedByMe: liked,
        repostsCount: reposts,
        isRepostedByMe: reposted,
      );

  setUp(() {
    mockRepo = MockPostRepository();
  });

  group('NewsBloc', () {
    test('initial state is NewsInitial', () {
      expect(NewsBloc(mockRepo).state, isA<NewsInitial>());
    });

    blocTest<NewsBloc, NewsState>(
      'NewsLoaded: оставляет только kind == news',
      build: () {
        when(
          () => mockRepo.getNewsPosts(
            limit: 20,
            offset: 0,
            currentUserId: 'u1',
          ),
        ).thenAnswer(
          (_) async => [
            post(id: 'n1', kind: 'news'),
            post(id: 'p1', kind: 'publication'),
            post(id: 'n2', kind: 'NEWS'),
          ],
        );
        return NewsBloc(mockRepo);
      },
      act: (b) => b.add(const NewsLoaded(currentUserId: 'u1')),
      expect: () => [
        isA<NewsLoading>(),
        isA<NewsSuccess>().having(
          (NewsSuccess s) => s.posts.map((e) => e.id).toList(),
          'ids',
          ['n1', 'n2'],
        ),
      ],
    );

    blocTest<NewsBloc, NewsState>(
      'NewsLoaded: ошибка -> NewsFailure',
      build: () {
        when(
          () => mockRepo.getNewsPosts(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            currentUserId: any(named: 'currentUserId'),
          ),
        ).thenThrow(Exception('network'));
        return NewsBloc(mockRepo);
      },
      act: (b) => b.add(const NewsLoaded()),
      expect: () => [
        isA<NewsLoading>(),
        isA<NewsFailure>(),
      ],
    );

    blocTest<NewsBloc, NewsState>(
      'NewsLoadMore добавляет посты и сбрасывает isLoadingMore при ошибке',
      build: () {
        when(
          () => mockRepo.getNewsPosts(
            limit: 20,
            offset: 0,
            currentUserId: 'u',
          ),
        ).thenAnswer((_) async => List.generate(20, (i) => post(id: 'a$i')));
        when(
          () => mockRepo.getNewsPosts(
            limit: 20,
            offset: 20,
            currentUserId: null,
          ),
        ).thenThrow(Exception('fail'));
        return NewsBloc(mockRepo);
      },
      act: (b) async {
        b.add(const NewsLoaded(currentUserId: 'u'));
        await b.stream.firstWhere((s) => s is NewsSuccess);
        b.add(NewsLoadMore());
      },
      expect: () => [
        isA<NewsLoading>(),
        isA<NewsSuccess>()
            .having((NewsSuccess s) => s.posts.length, 'len', 20),
        isA<NewsSuccess>()
            .having((NewsSuccess s) => s.isLoadingMore, 'loadingMore', true),
        isA<NewsSuccess>().having(
          (NewsSuccess s) => s.isLoadingMore,
          'loadingMore',
          false,
        ),
      ],
    );

    blocTest<NewsBloc, NewsState>(
      'NewsToggleLike: оптимистично, при ошибке откат',
      build: () {
        when(
          () => mockRepo.getNewsPosts(
            limit: 20,
            offset: 0,
            currentUserId: null,
          ),
        ).thenAnswer((_) async => [post(id: 'x', likes: 3, liked: false)]);
        when(() => mockRepo.toggleLike('x', 'u1')).thenThrow(Exception('e'));
        return NewsBloc(mockRepo);
      },
      act: (b) async {
        b.add(const NewsLoaded());
        await b.stream.firstWhere((s) => s is NewsSuccess);
        b.add(const NewsToggleLike(postId: 'x', userId: 'u1'));
      },
      expect: () => [
        isA<NewsLoading>(),
        isA<NewsSuccess>().having(
          (NewsSuccess s) => s.posts.first.isLikedByMe,
          'до лайка',
          false,
        ),
        isA<NewsSuccess>().having(
          (NewsSuccess s) => s.posts.first.isLikedByMe,
          'оптимистично',
          true,
        ),
        isA<NewsSuccess>().having(
          (NewsSuccess s) => s.posts.first.isLikedByMe,
          'откат',
          false,
        ),
      ],
    );

    blocTest<NewsBloc, NewsState>(
      'NewsToggleRepost: после успеха меняет счётчик',
      build: () {
        when(
          () => mockRepo.getNewsPosts(
            limit: 20,
            offset: 0,
            currentUserId: null,
          ),
        ).thenAnswer((_) async => [post(id: 'x', reposts: 1, reposted: false)]);
        when(() => mockRepo.toggleRepost('x', 'u1')).thenAnswer((_) async {});
        return NewsBloc(mockRepo);
      },
      act: (b) async {
        b.add(const NewsLoaded());
        await b.stream.firstWhere((s) => s is NewsSuccess);
        b.add(const NewsToggleRepost(postId: 'x', userId: 'u1'));
      },
      expect: () => [
        isA<NewsLoading>(),
        isA<NewsSuccess>(),
        isA<NewsSuccess>().having(
          (NewsSuccess s) => s.posts.first.isRepostedByMe,
          'reposted',
          true,
        ),
      ],
    );
  });
}
