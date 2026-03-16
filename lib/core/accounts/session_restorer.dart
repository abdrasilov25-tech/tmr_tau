import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'account_model.dart';

class SessionRestorer {
  SessionRestorer(this._client);

  final supa.SupabaseClient _client;

  /// Переключает Supabase-сессию на указанный аккаунт, используя refresh token.
  Future<void> restoreSession(AccountModel account) async {
    final refreshToken = account.refreshToken;
    if (refreshToken.isEmpty) {
      return;
    }
    await _client.auth.setSession(refreshToken);
  }
}

