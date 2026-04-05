import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Favorites for DM sticker picker: `e:` + emoji or `u:` + image URL.
class ChatStickerFavoritesStorage extends ChangeNotifier {
  ChatStickerFavoritesStorage(this._prefs);

  final SharedPreferences _prefs;
  String _activeUserId = '';

  void setActiveUserId(String? userId) {
    _activeUserId = userId?.trim() ?? '';
  }

  String get _key => _activeUserId.isEmpty
      ? 'chat_sticker_fav__nosession_'
      : 'chat_sticker_fav_uid_${_activeUserId}_';

  List<String> get rawEntries => _prefs.getStringList(_key) ?? [];

  static String tokenEmoji(String emoji) => 'e:$emoji';

  static String tokenImageUrl(String url) => 'u:$url';

  bool isFavoriteToken(String token) => rawEntries.contains(token);

  Future<void> toggleToken(String token) async {
    final next = [...rawEntries];
    if (next.contains(token)) {
      next.remove(token);
    } else {
      next.add(token);
    }
    await _prefs.setStringList(_key, next);
    notifyListeners();
  }

  Future<void> removeToken(String token) async {
    final next = rawEntries.where((e) => e != token).toList();
    if (next.length == rawEntries.length) return;
    await _prefs.setStringList(_key, next);
    notifyListeners();
  }
}
