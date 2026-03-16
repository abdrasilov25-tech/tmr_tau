import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'account_model.dart';

abstract class AccountRepository {
  Future<List<AccountModel>> getAccounts();
  Future<AccountModel?> getAccountByUserId(String userId);
  Future<void> saveAccount(AccountModel account);
  Future<void> removeAccount(String userId);
}

class AccountRepositoryImpl implements AccountRepository {
  AccountRepositoryImpl(this._prefs);

  final SharedPreferences _prefs;

  static const _accountsKey = 'tmr_tau_token_accounts';

  @override
  Future<List<AccountModel>> getAccounts() async {
    final raw = _prefs.getString(_accountsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => AccountModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<AccountModel?> getAccountByUserId(String userId) async {
    final accounts = await getAccounts();
    for (final a in accounts) {
      if (a.userId == userId) return a;
    }
    return null;
  }

  @override
  Future<void> saveAccount(AccountModel account) async {
    final accounts = await getAccounts();
    final without = accounts.where((a) => a.userId != account.userId).toList();
    without.add(account);
    final encoded =
        jsonEncode(without.map((a) => a.toJson()).toList(growable: false));
    await _prefs.setString(_accountsKey, encoded);
  }

  @override
  Future<void> removeAccount(String userId) async {
    final accounts = await getAccounts();
    final without = accounts.where((a) => a.userId != userId).toList();
    final encoded =
        jsonEncode(without.map((a) => a.toJson()).toList(growable: false));
    await _prefs.setString(_accountsKey, encoded);
  }
}

