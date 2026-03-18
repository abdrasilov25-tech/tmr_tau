import 'package:shared_preferences/shared_preferences.dart';

/// Локальное сохранение лайков и репостов товаров (при нажатии сохраняются сразу).
class LocalReactionsStorage {
  LocalReactionsStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _likedIdsKey = 'tmr_tau_liked_product_ids';
  static const _repostedIdsKey = 'tmr_tau_reposted_product_ids';
  static const _loginThemeIndexKey = 'tmr_tau_login_theme_index';
  static const _customThemeImagePathKey = 'tmr_tau_custom_theme_image_path';

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

  /// Полностью очищает локальные лайки/репосты (например, при переключении аккаунта).
  Future<void> clearReactions() async {
    await _prefs.remove(_likedIdsKey);
    await _prefs.remove(_repostedIdsKey);
  }

  /// Индекс темы (0–6: 0–5 пресеты, 6 — своя из галереи). По умолчанию 0.
  int getLoginThemeIndex() {
    return _prefs.getInt(_loginThemeIndexKey) ?? 0;
  }

  Future<void> setLoginThemeIndex(int index) async {
    await _prefs.setInt(_loginThemeIndexKey, index.clamp(0, 6));
  }

  /// Путь к файлу своей темы (фон из галереи). null — не задана.
  String? getCustomThemeImagePath() {
    return _prefs.getString(_customThemeImagePathKey);
  }

  Future<void> setCustomThemeImagePath(String? path) async {
    if (path == null || path.isEmpty) {
      await _prefs.remove(_customThemeImagePathKey);
    } else {
      await _prefs.setString(_customThemeImagePathKey, path);
    }
  }
}
