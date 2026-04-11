import 'package:shared_preferences/shared_preferences.dart';

/// Локальный флаг «смотреть приложение без аккаунта» (сессии Supabase нет).
class GuestSessionStorage {
  GuestSessionStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'tmr_tau_guest_browsing_v1';

  bool get isGuestBrowsing => _prefs.getBool(_key) ?? false;

  Future<void> setGuestBrowsing(bool value) => _prefs.setBool(_key, value);
}
