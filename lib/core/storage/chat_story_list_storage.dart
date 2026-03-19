import 'package:shared_preferences/shared_preferences.dart';

/// Локальное состояние просмотра сторис в разделе «Мои чаты».
///
/// Храним последнее время просмотра сторис для каждого собеседника `peerId`,
/// чтобы рисовать «красное кольцо» при появлении новых активных сторис.
class ChatStoryListStorage {
  ChatStoryListStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _seenPrefix = 'tmr_tau_chat_story_seen_';

  DateTime? getLastSeenAt(String peerId) {
    final millis = _prefs.getInt(_seenPrefix + peerId);
    return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  Future<void> setLastSeenAt(String peerId, DateTime at) async {
    await _prefs.setInt(_seenPrefix + peerId, at.millisecondsSinceEpoch);
  }

  Future<void> clearAll() async {
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_seenPrefix)) {
        await _prefs.remove(key);
      }
    }
  }
}

