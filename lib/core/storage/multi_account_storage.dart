import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сохранённый аккаунт для быстрого переключения (как в Instagram).
class SavedAccount {
  const SavedAccount({
    required this.id,
    required this.email,
    this.name,
    this.avatarUrl,
  });

  final String id;
  final String email;
  final String? name;
  final String? avatarUrl;

  String get displayName => (name != null && name!.isNotEmpty) ? name! : email;

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'avatarUrl': avatarUrl,
      };

  static SavedAccount fromJson(Map<String, dynamic> json) {
    return SavedAccount(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

/// Хранит список аккаунтов и пароли для переключения (пароли только для email-входа).
class MultiAccountStorage {
  MultiAccountStorage(this._prefs, this._secure);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  static const _accountsKey = 'tmr_tau_saved_accounts';
  /// Один ключ: карта email -> пароль (как в Instagram — все аккаунты локально).
  static const _passwordsMapKey = 'tmr_tau_passwords_map';
  static const _passwordKeyPrefix = 'tmr_tau_acc_pwd_';
  static const _passwordPrefsPrefix = 'tmr_tau_acc_pwd_prefs_';
  static const _passwordPrefsEmailPrefix = 'tmr_tau_acc_pwd_email_';

  List<SavedAccount> getAccounts() {
    final json = _prefs.getString(_accountsKey);
    if (json == null) return [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => SavedAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addAccount(SavedAccount account, {String? password}) async {
    final list = getAccounts();
    final without = list.where((a) => a.id != account.id).toList();
    without.add(account);
    await _prefs.setString(_accountsKey, jsonEncode(without.map((e) => e.toJson()).toList()));
    if (password != null && password.isNotEmpty) {
      await _savePassword(account.id, password);
      _savePasswordByEmail(account.email, password);
    }
  }

  static String _normId(String id) => id.trim().toLowerCase();
  static String _normEmail(String email) => email.trim().toLowerCase();

  Map<String, String> _getPasswordsMap() {
    final raw = _prefs.getString(_passwordsMapKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  void _setPasswordsMap(Map<String, String> map) {
    _prefs.setString(_passwordsMapKey, jsonEncode(map));
  }

  Future<void> _savePassword(String userId, String password) async {
    final key = _normId(userId);
    try {
      await _secure.write(key: _passwordKeyPrefix + key, value: password);
      _prefs.remove(_passwordPrefsPrefix + key);
    } catch (_) {
      _prefs.setString(_passwordPrefsPrefix + key, password);
    }
  }

  void _savePasswordByEmail(String email, String password) {
    final key = _normEmail(email);
    _prefs.setString(_passwordPrefsEmailPrefix + key, password);
    final map = _getPasswordsMap();
    map[key] = password;
    _setPasswordsMap(map);
  }

  Future<void> removeAccount(String userId) async {
    final key = _normId(userId);
    final accounts = getAccounts();
    String? email;
    for (final a in accounts) {
      if (a.id == userId) { email = a.email; break; }
    }
    final list = accounts.where((a) => a.id != userId).toList();
    await _prefs.setString(_accountsKey, jsonEncode(list.map((e) => e.toJson()).toList()));
    try {
      await _secure.delete(key: _passwordKeyPrefix + key);
    } catch (_) {}
    _prefs.remove(_passwordPrefsPrefix + key);
    if (email != null && email.isNotEmpty) {
      final normEmail = _normEmail(email);
      _prefs.remove(_passwordPrefsEmailPrefix + normEmail);
      final map = _getPasswordsMap();
      map.remove(normEmail);
      _setPasswordsMap(map);
    }
  }

  /// Сначала карта по email (главный источник), затем отдельные ключи, затем secure storage.
  Future<String?> getPassword(String userId, {String? email}) async {
    if (email != null && email.isNotEmpty) {
      final map = _getPasswordsMap();
      final v = map[_normEmail(email)];
      if (v != null && v.isNotEmpty) return v;
      final v2 = _prefs.getString(_passwordPrefsEmailPrefix + _normEmail(email));
      if (v2 != null && v2.isNotEmpty) return v2;
    }
    final key = _normId(userId);
    for (final k in [key, userId]) {
      final v = _prefs.getString(_passwordPrefsPrefix + k);
      if (v != null && v.isNotEmpty) return v;
    }
    try {
      for (final k in [key, userId]) {
        final v = await _secure.read(key: _passwordKeyPrefix + k);
        if (v != null && v.isNotEmpty) return v;
      }
    } catch (_) {}
    return null;
  }

  /// Только сохранить пароль (вызов при каждом успешном входе по email/паролю).
  Future<void> setPassword(String userId, String password) async {
    if (password.isEmpty) return;
    await _savePassword(userId, password);
  }

  /// Сразу пишет пароль в SharedPreferences (карта + отдельные ключи), чтобы переключение по тапу находило пароль.
  void savePasswordImmediate(String userId, String email, String password) {
    if (password.isEmpty) return;
    final normEmail = _normEmail(email);
    final idKey = _normId(userId);
    _prefs.setString(_passwordPrefsPrefix + idKey, password);
    _prefs.setString(_passwordPrefsEmailPrefix + normEmail, password);
    final map = _getPasswordsMap();
    map[normEmail] = password;
    _setPasswordsMap(map);
  }
}
