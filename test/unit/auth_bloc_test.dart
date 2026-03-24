import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tmr_tau/core/storage/multi_account_storage.dart';
import 'package:tmr_tau/features/auth/domain/entities/app_user.dart';
import 'package:tmr_tau/features/auth/domain/repositories/auth_repository.dart';
import 'package:tmr_tau/features/auth/presentation/bloc/auth_bloc.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockMultiAccountStorage extends Mock implements MultiAccountStorage {}

void main() {
  late MockAuthRepository mockAuthRepository;
  late MockMultiAccountStorage mockMultiAccountStorage;

  const testUser = AppUser(
    id: 'user-1',
    email: 'test@test.com',
    name: 'Test User',
  );

  setUpAll(() {
    registerFallbackValue(
      const SavedAccount(id: 'fallback', email: 'fallback@local'),
    );
  });

  setUp(() {
    mockAuthRepository = MockAuthRepository();
    mockMultiAccountStorage = MockMultiAccountStorage();
    when(() => mockMultiAccountStorage.setLastActiveAccountId(any()))
        .thenAnswer((_) async {});
    when(() => mockMultiAccountStorage.addAccount(any()))
        .thenAnswer((_) async {});
    when(() => mockMultiAccountStorage.removeAccount(any()))
        .thenAnswer((_) async {});
  });

  group('AuthBloc', () {
    test('initial state is AuthInitial', () {
      expect(
        AuthBloc(mockAuthRepository, mockMultiAccountStorage).state,
        isA<AuthInitial>(),
      );
    });

    blocTest<AuthBloc, AuthState>(
      'AuthCheckRequested: нет пользователя -> AuthUnauthenticated',
      build: () {
        when(() => mockAuthRepository.getCurrentUserOnce())
            .thenAnswer((_) async => null);
        return AuthBloc(mockAuthRepository, mockMultiAccountStorage);
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthUnauthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthCheckRequested: есть пользователь -> AuthAuthenticated',
      build: () {
        when(() => mockAuthRepository.getCurrentUserOnce())
            .thenAnswer((_) async => testUser);
        when(() => mockAuthRepository.currentUser).thenReturn(testUser);
        return AuthBloc(mockAuthRepository, mockMultiAccountStorage);
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthCheckRequested: ошибка репозитория -> AuthUnauthenticated',
      build: () {
        when(() => mockAuthRepository.getCurrentUserOnce())
            .thenThrow(Exception('network'));
        return AuthBloc(mockAuthRepository, mockMultiAccountStorage);
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthUnauthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthSignInRequested: успех -> AuthAuthenticated',
      build: () {
        when(() => mockAuthRepository.signInWithEmail(any(), any()))
            .thenAnswer((_) async => {});
        when(() => mockAuthRepository.currentUser).thenReturn(testUser);
        return AuthBloc(mockAuthRepository, mockMultiAccountStorage);
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
        return AuthBloc(mockAuthRepository, mockMultiAccountStorage);
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
        return AuthBloc(mockAuthRepository, mockMultiAccountStorage);
      },
      act: (bloc) => bloc.add(const AuthSignOutRequested()),
      expect: () => [isA<AuthUnauthenticated>()],
    );
  });
}
