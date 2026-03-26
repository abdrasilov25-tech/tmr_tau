import 'package:flutter_test/flutter_test.dart';
import 'package:tmr_tau/features/auth/domain/entities/app_user.dart';
import 'package:tmr_tau/features/auth/presentation/bloc/auth_bloc.dart';

void main() {
  const user = AppUser(
    id: 'u1',
    email: 'a@b.com',
    name: 'N',
  );

  group('AuthAuthenticated', () {
    test('fromSessionOnly участвует в равенстве — два emit с одним user не схлопываются вслепую',
        () {
      const a = AuthAuthenticated(user, fromSessionOnly: true);
      const b = AuthAuthenticated(user, fromSessionOnly: false);
      expect(a, isNot(equals(b)));
      expect(a.props, [user, true]);
      expect(b.props, [user, false]);
    });
  });
}
