import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tmr_tau/core/auth/guest_session_storage.dart';
import 'package:tmr_tau/core/storage/multi_account_storage.dart';
import 'package:tmr_tau/features/auth/domain/entities/app_user.dart';
import 'package:tmr_tau/features/auth/domain/repositories/auth_repository.dart';
import 'package:tmr_tau/features/auth/presentation/bloc/auth_bloc.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockMultiAccountStorage extends Mock implements MultiAccountStorage {}

void main() {
  late MockAuthRepository mockAuthRepository;
  late MockMultiAccountStorage mockMultiAccountStorage;
  late GuestSessionStorage guestSessionStorage;

  const stubUser = AppUser(
    id: 'user-1',
    email: 'test@test.com',
    name: 'Stub',
  );

  const fullUser = AppUser(
    id: 'user-1',
    email: 'test@test.com',
    name: 'From DB',
    followersCount: 7,
  );

  setUpAll(() {
    registerFallbackValue(
      const SavedAccount(id: 'fallback', email: 'fallback@local'),
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    guestSessionStorage = GuestSessionStorage(prefs);
    mockAuthRepository = MockAuthRepository();
    mockMultiAccountStorage = MockMultiAccountStorage();
    when(() => mockMultiAccountStorage.setLastActiveAccountId(any()))
        .thenAnswer((_) async {});
    when(() => mockMultiAccountStorage.addAccount(any()))
        .thenAnswer((_) async {});
    when(() => mockMultiAccountStorage.removeAccount(any()))
        .thenAnswer((_) async {});
    when(() => mockAuthRepository.fetchUserProfileFromRemote(any()))
        .thenAnswer((_) async => null);
  });

  group('AuthBloc', () {
    test('initial state is AuthInitial', () {
      expect(
        AuthBloc(mockAuthRepository, mockMultiAccountStorage, guestSessionStorage)
            .state,
        isA<AuthInitial>(),
      );
    });

    blocTest<AuthBloc, AuthState>(
      'AuthCheckRequested: нет сессии -> AuthUnauthenticated (без AuthLoading)',
      build: () {
        when(() => mockAuthRepository.userFromCurrentSession())
            .thenReturn(null);
        return AuthBloc(
          mockAuthRepository,
          mockMultiAccountStorage,
          guestSessionStorage,
        );
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [isA<AuthUnauthenticated>()],
    );

    test('AuthCheckRequested: нет сессии, гость -> AuthBrowsingAsGuest',
        () async {
      SharedPreferences.setMockInitialValues(
        {'tmr_tau_guest_browsing_v1': true},
      );
      final prefs = await SharedPreferences.getInstance();
      when(() => mockAuthRepository.userFromCurrentSession())
          .thenReturn(null);
      final bloc = AuthBloc(
        mockAuthRepository,
        mockMultiAccountStorage,
        GuestSessionStorage(prefs),
      );
      final expectDone = expectLater(
        bloc.stream,
        emitsInOrder(<Matcher>[isA<AuthBrowsingAsGuest>()]),
      );
      bloc.add(const AuthCheckRequested());
      await expectDone;
      await bloc.close();
    });

    blocTest<AuthBloc, AuthState>(
      'AuthContinueAsGuestRequested -> AuthBrowsingAsGuest',
      build: () => AuthBloc(
        mockAuthRepository,
        mockMultiAccountStorage,
        guestSessionStorage,
      ),
      act: (bloc) => bloc.add(const AuthContinueAsGuestRequested()),
      expect: () => [isA<AuthBrowsingAsGuest>()],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthCheckRequested: сессия есть, профиль с сервера не пришёл -> только stub',
      build: () {
        when(() => mockAuthRepository.userFromCurrentSession())
            .thenReturn(stubUser);
        when(() => mockAuthRepository.fetchUserProfileFromRemote('user-1'))
            .thenAnswer((_) async => null);
        return AuthBloc(
          mockAuthRepository,
          mockMultiAccountStorage,
          guestSessionStorage,
        );
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [
        const AuthAuthenticated(stubUser, fromSessionOnly: true),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthCheckRequested: сессия + профиль с сервера -> stub затем полный пользователь',
      build: () {
        when(() => mockAuthRepository.userFromCurrentSession())
            .thenReturn(stubUser);
        when(() => mockAuthRepository.fetchUserProfileFromRemote('user-1'))
            .thenAnswer((_) async => fullUser);
        return AuthBloc(
          mockAuthRepository,
          mockMultiAccountStorage,
          guestSessionStorage,
        );
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [
        const AuthAuthenticated(stubUser, fromSessionOnly: true),
        const AuthAuthenticated(fullUser, fromSessionOnly: false),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthCheckRequested: после загрузки профиля сессии уже нет -> второй emit не делаем',
      build: () {
        var sessionProbe = 0;
        when(() => mockAuthRepository.userFromCurrentSession())
            .thenAnswer((_) {
          sessionProbe++;
          return sessionProbe == 1 ? stubUser : null;
        });
        when(() => mockAuthRepository.fetchUserProfileFromRemote('user-1'))
            .thenAnswer((_) async => fullUser);
        return AuthBloc(
          mockAuthRepository,
          mockMultiAccountStorage,
          guestSessionStorage,
        );
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [
        const AuthAuthenticated(stubUser, fromSessionOnly: true),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthSignInRequested: успех -> AuthAuthenticated',
      build: () {
        when(() => mockAuthRepository.signInWithEmail(any(), any()))
            .thenAnswer((_) async => {});
        when(() => mockAuthRepository.currentUser).thenReturn(stubUser);
        return AuthBloc(
          mockAuthRepository,
          mockMultiAccountStorage,
          guestSessionStorage,
        );
      },
      act: (bloc) => bloc.add(const AuthSignInRequested(
        email: 'a@b.com',
        password: 'pass',
      )),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthSignInRequested: неверный логин -> AuthError с сообщением',
      build: () {
        when(() => mockAuthRepository.signInWithEmail(any(), any()))
            .thenThrow(Exception('Invalid login credentials'));
        return AuthBloc(
          mockAuthRepository,
          mockMultiAccountStorage,
          guestSessionStorage,
        );
      },
      act: (bloc) => bloc.add(const AuthSignInRequested(
        email: 'a@b.com',
        password: 'wrong',
      )),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthError>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthSignOutRequested -> AuthUnauthenticated',
      build: () {
        when(() => mockAuthRepository.signOut()).thenAnswer((_) async => {});
        return AuthBloc(
          mockAuthRepository,
          mockMultiAccountStorage,
          guestSessionStorage,
        );
      },
      act: (bloc) => bloc.add(const AuthSignOutRequested()),
      expect: () => [isA<AuthUnauthenticated>()],
    );
  });
}
