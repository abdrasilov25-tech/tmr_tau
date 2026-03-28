import 'package:shared_preferences/shared_preferences.dart';

/// Локальное состояние просмотра сторис в разделе «Мои чаты».
///
/// Храним последнее время просмотра сторис для каждого собеседника `peerId`,
/// чтобы рисовать «красное кольцо» при появлении новых активных сторис.
/// Ключи изолированы по аккаунту ([setActiveAccountId]).
class ChatStoryListStorage {
  ChatStoryListStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _legacySeenPrefix = 'tmr_tau_chat_story_seen_';

  String _activeAccountId = '';

  void setActiveAccountId(String? userId) {
    _activeAccountId = userId?.trim() ?? '';
  }

  String get _base => _activeAccountId.isEmpty
      ? 'tmr_tau_chat_story__nosession_'
      : 'tmr_tau_chat_story_uid_${_activeAccountId}_';

  String _seenKey(String peerId) => '${_base}seen_$peerId';

  DateTime? getLastSeenAt(String peerId) {
    final millis = _prefs.getInt(_seenKey(peerId));
    return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  Future<void> setLastSeenAt(String peerId, DateTime at) async {
    if (_activeAccountId.isEmpty) return;
    await _prefs.setInt(_seenKey(peerId), at.millisecondsSinceEpoch);
  }

  Future<void> clearAllForActiveAccount() async {
    if (_activeAccountId.isEmpty) return;
    final prefix = _base;
    final keys = _prefs.getKeys().toList(growable: false);
    for (final key in keys) {
      if (key.startsWith(prefix)) {
        await _prefs.remove(key);
      }
    }
  }

  Future<void> clearLegacyGlobalKeys() async {
    final keys = _prefs.getKeys().toList(growable: false);
    for (final key in keys) {
      if (key.startsWith(_legacySeenPrefix)) {
        await _prefs.remove(key);
      }
    }
  }
}
