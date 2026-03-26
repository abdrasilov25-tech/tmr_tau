import 'package:shared_preferences/shared_preferences.dart';

/// Локальное состояние списка чатов: архив и время последнего прочтения (для «непрочитанное»).
class ChatListStorage {
  ChatListStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _archivedKey = 'tmr_tau_chat_archived_ids';
  static const _readPrefix = 'tmr_tau_chat_read_';
  static const _dialogPrefix = 'tmr_tau_chat_dialog_';
  static const _acceptedPrefix = 'tmr_tau_chat_accepted_';
  static const _hiddenMessagesPrefix = 'tmr_tau_chat_hidden_messages_';

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

  /// Время, когда последний раз показывали диалог «принять сообщение» для этого собеседника.
  DateTime? getLastDialogShownAt(String peerId) {
    final millis = _prefs.getInt(_dialogPrefix + peerId);
    return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  Future<void> setLastDialogShownAt(String peerId, DateTime at) async {
    await _prefs.setInt(_dialogPrefix + peerId, at.millisecondsSinceEpoch);
  }

  /// Был ли для собеседника уже выбран вариант "Принять".
  bool isAccepted(String peerId) {
    return _prefs.getBool(_acceptedPrefix + peerId) ?? false;
  }

  Future<void> setAccepted(String peerId, bool value) async {
    await _prefs.setBool(_acceptedPrefix + peerId, value);
  }

  /// Очищает локальное состояние конкретного чата (чтобы удалённый чат не "возвращался" из локальных флагов).
  Future<void> clearPeerState(String peerId) async {
    final archived = getArchivedPeerIds();
    if (archived.remove(peerId)) {
      await _prefs.setStringList(_archivedKey, archived.toList());
    }
    await _prefs.remove(_readPrefix + peerId);
    await _prefs.remove(_dialogPrefix + peerId);
    await _prefs.remove(_acceptedPrefix + peerId);
    await _prefs.remove(_hiddenMessagesPrefix + peerId);
  }

  Set<String> getHiddenMessageIds(String peerId) {
    final list = _prefs.getStringList(_hiddenMessagesPrefix + peerId);
    return list != null ? list.toSet() : <String>{};
  }

  Future<void> addHiddenMessageIds(String peerId, Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final current = getHiddenMessageIds(peerId);
    current.addAll(ids.where((e) => e.isNotEmpty));
    await _prefs.setStringList(_hiddenMessagesPrefix + peerId, current.toList());
  }

  /// Полностью очищает локальное состояние чатов (архив/непрочитанное).
  Future<void> clearAll() async {
    await _prefs.remove(_archivedKey);
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_readPrefix) || key.startsWith(_dialogPrefix)) {
        await _prefs.remove(key);
      }
      if (key.startsWith(_acceptedPrefix)) {
        await _prefs.remove(key);
      }
    }
  }
}
