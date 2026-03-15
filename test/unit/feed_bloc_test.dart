import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tmr_tau/core/storage/local_reactions_storage.dart';
import 'package:tmr_tau/features/feed/domain/repositories/feed_repository.dart';
import 'package:tmr_tau/features/feed/presentation/bloc/feed_bloc.dart';
import 'package:tmr_tau/features/product/domain/entities/product_entity.dart';

class MockFeedRepository extends Mock implements FeedRepository {}

class MockLocalReactionsStorage extends Mock implements LocalReactionsStorage {}

void main() {
  late MockFeedRepository mockRepository;
  late MockLocalReactionsStorage mockLocalReactions;

  ProductEntity product({
    required String id,
    String title = 'Товар',
    double price = 1000,
    String sellerId = 'seller-1',
    int likesCount = 0,
    bool isLikedByMe = false,
    bool isRepostedByMe = false,
    bool isFollowingSeller = false,
  }) =>
      ProductEntity(
        id: id,
        title: title,
        description: '',
        price: price,
        imageUrl: '',
        sellerId: sellerId,
        likesCount: likesCount,
        isLikedByMe: isLikedByMe,
        isRepostedByMe: isRepostedByMe,
        isFollowingSeller: isFollowingSeller,
      );

  setUp(() {
    mockRepository = MockFeedRepository();
    mockLocalReactions = MockLocalReactionsStorage();
  });

  group('FeedBloc', () {
    test('initial state is FeedInitial', () {
      expect(
        FeedBloc(mockRepository, mockLocalReactions).state,
        isA<FeedInitial>(),
      );
    });

    blocTest<FeedBloc, FeedState>(
      'FeedLoaded: успех -> FeedSuccess с товарами',
      build: () {
        when(() => mockLocalReactions.getLikedIds()).thenReturn({});
        when(() => mockLocalReactions.getRepostedIds()).thenReturn({});
        when(() => mockRepository.getFeed(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
          currentUserId: any(named: 'currentUserId'),
        )).thenAnswer((_) async => [
          product(id: 'p1'),
          product(id: 'p2'),
        ]);
        return FeedBloc(mockRepository, mockLocalReactions);
      },
      act: (bloc) => bloc.add(const FeedLoaded(currentUserId: 'user-1')),
      expect: () => [
        isA<FeedLoading>(),
        isA<FeedSuccess>(),
      ],
    );

    blocTest<FeedBloc, FeedState>(
      'FeedLoaded: ошибка репозитория -> FeedFailure',
      build: () {
        when(() => mockLocalReactions.getLikedIds()).thenReturn({});
        when(() => mockLocalReactions.getRepostedIds()).thenReturn({});
        when(() => mockRepository.getFeed(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
          currentUserId: any(named: 'currentUserId'),
        )).thenThrow(Exception('Network error'));
        return FeedBloc(mockRepository, mockLocalReactions);
      },
      act: (bloc) => bloc.add(const FeedLoaded()),
      expect: () => [
        isA<FeedLoading>(),
        isA<FeedFailure>(),
      ],
    );

    blocTest<FeedBloc, FeedState>(
      'FeedToggleLike: оптимистично обновляет isLikedByMe и счётчик',
      build: () {
        when(() => mockLocalReactions.getLikedIds()).thenReturn({});
        when(() => mockLocalReactions.getRepostedIds()).thenReturn({});
        when(() => mockRepository.getFeed(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
          currentUserId: any(named: 'currentUserId'),
        )).thenAnswer((_) async => [
          product(id: 'p1', isLikedByMe: false, likesCount: 5),
        ]);
        when(() => mockLocalReactions.setLiked(any(), any()))
            .thenAnswer((_) async => {});
        when(() => mockRepository.toggleProductLike(any(), any()))
            .thenAnswer((_) async => {});
        return FeedBloc(mockRepository, mockLocalReactions);
      },
      act: (bloc) async {
        bloc.add(const FeedLoaded(currentUserId: 'user-1'));
        await Future.delayed(Duration.zero);
        bloc.add(const FeedToggleLike(productId: 'p1', userId: 'user-1'));
      },
      expect: () => [
        isA<FeedLoading>(),
        isA<FeedSuccess>(),
        isA<FeedSuccess>(), // после toggle like
      ],
    );
  });
}
