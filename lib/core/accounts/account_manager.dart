import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'account_model.dart';
import 'account_repository.dart';
import 'session_restorer.dart';

class AccountManager {
  AccountManager(this._repository, this._sessionRestorer);

  final AccountRepository _repository;
  final SessionRestorer _sessionRestorer;

  AccountModel? _activeAccount;

  AccountModel? get activeAccount => _activeAccount;

  Future<List<AccountModel>> loadAccounts() {
    return _repository.getAccounts();
  }

  Future<void> addOrUpdateAccount(AccountModel account) async {
    await _repository.saveAccount(account);
    _activeAccount = account;
  }

  Future<void> removeAccount(String userId) async {
    await _repository.removeAccount(userId);
    if (_activeAccount?.userId == userId) {
      _activeAccount = null;
    }
  }

  Future<void> switchAccount(AccountModel account) async {
    try {
      await _sessionRestorer.restoreSession(account);
      _activeAccount = account;
    } on supa.AuthApiException catch (e) {
      // Если refresh token больше не валиден, удаляем аккаунт локально
      final code = e.code ?? '';
      final message = e.message.toLowerCase();
      final isInvalidRefreshToken =
          code == 'refresh_token_not_found' ||
          message.contains('invalid refresh token');
      if (isInvalidRefreshToken) {
        await _repository.removeAccount(account.userId);
        if (_activeAccount?.userId == account.userId) {
          _activeAccount = null;
        }
      }
      // Остальные ошибки не пробрасываем вверх, чтобы не ронять приложение.
    }
  }
}

