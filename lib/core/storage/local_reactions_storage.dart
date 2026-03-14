import 'package:shared_preferences/shared_preferences.dart';

/// Локальное сохранение лайков и репостов товаров (при нажатии сохраняются сразу).
class LocalReactionsStorage {
  LocalReactionsStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _likedIdsKey = 'tmr_tau_liked_product_ids';
  static const _repostedIdsKey = 'tmr_tau_reposted_product_ids';
  static const _loginThemeIndexKey = 'tmr_tau_login_theme_index';

  Set<String> getLikedIds() {
    final list = _prefs.getStringList(_likedIdsKey);
    return list != null ? list.toSet() : {};
  }

  Set<String> getRepostedIds() {
    final list = _prefs.getStringList(_repostedIdsKey);
    return list != null ? list.toSet() : {};
  }

  Future<void> setLiked(String productId, bool liked) async {
    final set = getLikedIds();
    if (liked) {
      set.add(productId);
    } else {
      set.remove(productId);
    }
    await _prefs.setStringList(_likedIdsKey, set.toList());
  }

  Future<void> setReposted(String productId, bool reposted) async {
    final set = getRepostedIds();
    if (reposted) {
      set.add(productId);
    } else {
      set.remove(productId);
    }
    await _prefs.setStringList(_repostedIdsKey, set.toList());
  }

  /// Индекс темы экрана входа (0–5). По умолчанию 0.
  int getLoginThemeIndex() {
    return _prefs.getInt(_loginThemeIndexKey) ?? 0;
  }

  Future<void> setLoginThemeIndex(int index) async {
    await _prefs.setInt(_loginThemeIndexKey, index.clamp(0, 5));
  }
}
