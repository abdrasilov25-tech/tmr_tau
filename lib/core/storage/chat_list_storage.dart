import 'package:shared_preferences/shared_preferences.dart';

/// Локальное состояние списка чатов: архив и время последнего прочтения (для «непрочитанное»).
class ChatListStorage {
  ChatListStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _archivedKey = 'tmr_tau_chat_archived_ids';
  static const _readPrefix = 'tmr_tau_chat_read_';

  Set<String> getArchivedPeerIds() {
    final list = _prefs.getStringList(_archivedKey);
    return list != null ? list.toSet() : {};
  }

  Future<void> setArchived(String peerId, bool archived) async {
    final set = getArchivedPeerIds();
    if (archived) {
      set.add(peerId);
    } else {
      set.remove(peerId);
    }
    await _prefs.setStringList(_archivedKey, set.toList());
  }

  DateTime? getLastReadAt(String peerId) {
    final millis = _prefs.getInt(_readPrefix + peerId);
    return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  Future<void> setLastReadAt(String peerId, DateTime at) async {
    await _prefs.setInt(_readPrefix + peerId, at.millisecondsSinceEpoch);
  }

  /// Полностью очищает локальное состояние чатов (архив/непрочитанное).
  Future<void> clearAll() async {
    await _prefs.remove(_archivedKey);
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_readPrefix)) {
        await _prefs.remove(key);
      }
    }
  }
}
