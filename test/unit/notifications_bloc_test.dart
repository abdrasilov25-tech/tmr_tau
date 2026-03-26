import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tmr_tau/features/notifications/domain/entities/notification_entity.dart';
import 'package:tmr_tau/features/notifications/domain/repositories/notifications_repository.dart';
import 'package:tmr_tau/features/notifications/presentation/bloc/notifications_bloc.dart';

class MockNotificationsRepository extends Mock implements NotificationsRepository {}

void main() {
  late MockNotificationsRepository mockRepo;

  NotificationEntity note({
    required String id,
    DateTime? readAt,
  }) =>
      NotificationEntity(
        id: id,
        userId: 'u1',
        type: 'like',
        createdAt: DateTime(2024, 1, 1),
        readAt: readAt,
      );

  setUp(() {
    mockRepo = MockNotificationsRepository();
    when(() => mockRepo.markAsRead(any(), any())).thenAnswer((_) async {});
    when(() => mockRepo.markAllAsRead(any())).thenAnswer((_) async {});
  });

  group('NotificationsBloc', () {
    test('initial state', () {
      expect(
        NotificationsBloc(mockRepo, 'u1').state,
        isA<NotificationsInitial>(),
      );
    });

    blocTest<NotificationsBloc, NotificationsState>(
      'NotificationsRequested: успех с данными',
      build: () {
        when(
          () => mockRepo.getNotifications(
            'u1',
            limit: 100,
            offset: 0,
          ),
        ).thenAnswer((_) async => [note(id: 'n1')]);
        return NotificationsBloc(mockRepo, 'u1');
      },
      act: (b) => b.add(NotificationsRequested()),
      expect: () => [
        isA<NotificationsLoading>(),
        isA<NotificationsLoaded>().having(
          (NotificationsLoaded s) => s.notifications.length,
          'count',
          1,
        ),
      ],
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'NotificationsRequested: ошибка',
      build: () {
        when(
          () => mockRepo.getNotifications(
            'u1',
            limit: 100,
            offset: 0,
          ),
        ).thenThrow(Exception('db'));
        return NotificationsBloc(mockRepo, 'u1');
      },
      act: (b) => b.add(NotificationsRequested()),
      expect: () => [
        isA<NotificationsLoading>(),
        isA<NotificationsFailure>(),
      ],
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'NotificationsMarkRead помечает прочитанным',
      build: () {
        when(
          () => mockRepo.getNotifications(
            'u1',
            limit: 100,
            offset: 0,
          ),
        ).thenAnswer(
          (_) async => [
            note(id: 'n1', readAt: null),
          ],
        );
        return NotificationsBloc(mockRepo, 'u1');
      },
      act: (b) async {
        b.add(NotificationsRequested());
        await b.stream.firstWhere((s) => s is NotificationsLoaded);
        b.add(const NotificationsMarkRead('n1'));
      },
      expect: () => [
        isA<NotificationsLoading>(),
        isA<NotificationsLoaded>().having(
          (NotificationsLoaded s) => !s.notifications.first.isRead,
          'сначала непрочитано',
          true,
        ),
        isA<NotificationsLoaded>().having(
          (NotificationsLoaded s) => s.notifications.first.isRead,
          'после mark read',
          true,
        ),
      ],
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'NotificationsMarkAllRead вызывает повторную загрузку',
      build: () {
        var calls = 0;
        when(
          () => mockRepo.getNotifications(
            'u1',
            limit: 100,
            offset: 0,
          ),
        ).thenAnswer((_) async {
          calls++;
          return calls == 1
              ? [note(id: 'a')]
              : <NotificationEntity>[];
        });
        return NotificationsBloc(mockRepo, 'u1');
      },
      act: (b) async {
        b.add(NotificationsRequested());
        await b.stream.firstWhere((s) => s is NotificationsLoaded);
        b.add(NotificationsMarkAllRead());
        await b.stream.firstWhere((s) {
          return s is NotificationsLoaded && s.notifications.isEmpty;
        });
      },
      expect: () => [
        isA<NotificationsLoading>(),
        isA<NotificationsLoaded>().having(
          (NotificationsLoaded s) => s.notifications.length,
          'first load',
          1,
        ),
        isA<NotificationsLoading>(),
        isA<NotificationsLoaded>().having(
          (NotificationsLoaded s) => s.notifications.length,
          'after mark all',
          0,
        ),
      ],
    );
  });
}
