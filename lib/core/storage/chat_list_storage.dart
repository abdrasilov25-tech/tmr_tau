import 'package:shared_preferences/shared_preferences.dart';

/// Локальное состояние списка чатов: архив и время последнего прочтения (для «непрочитанное»).
///
/// Ключи изолированы по [setActiveAccountId], чтобы на одном устройстве несколько аккаунтов
/// не делили одни и те же отметки прочтения / архив / запросы.
class ChatListStorage {
  ChatListStorage(this._prefs);

  final SharedPreferences _prefs;

  /// Текущий пользователь Supabase; пусто — не пишем состояние чужих аккаунтов в общий префикс.
  String _activeAccountId = '';

  static const _legacyArchivedKey = 'tmr_tau_chat_archived_ids';

  void setActiveAccountId(String? userId) {
    _activeAccountId = userId?.trim() ?? '';
  }

  String get _base => _activeAccountId.isEmpty
      ? 'tmr_tau_chat__nosession_'
      : 'tmr_tau_chat_uid_${_activeAccountId}_';

  String get _archivedKey => '${_base}archived_ids';
  String _readKey(String peerId) => '${_base}read_$peerId';
  String _dialogKey(String peerId) => '${_base}dialog_$peerId';
  String _acceptedKey(String peerId) => '${_base}accepted_$peerId';
  String _declinedKey(String peerId) => '${_base}declined_$peerId';
  String _declinedMsgEpochKey(String peerId) => '${_base}declined_msg_$peerId';
  String _hiddenMessagesKey(String peerId) => '${_base}hidden_messages_$peerId';

  String _cityChatRulesKey(String groupId) =>
      '${_base}city_rules_seen_${groupId.trim()}';

  /// Id для префиксов read/accepted/…: у тредов `direct:uuid` это часть после `:`.
  String _prefsPeerIdFromThreadKey(String storageKeyOrPeerId) {
    final i = storageKeyOrPeerId.indexOf(':');
    if (i <= 0 || i >= storageKeyOrPeerId.length - 1) {
      return storageKeyOrPeerId;
    }
    return storageKeyOrPeerId.substring(i + 1);
  }

  Set<String> getArchivedPeerIds() {
    final list = _prefs.getStringList(_archivedKey);
    return list != null ? list.toSet() : {};
  }

  Future<void> setArchived(String storageKey, bool archived) async {
    final set = getArchivedPeerIds();
    if (archived) {
      set.add(storageKey);
    } else {
      set.remove(storageKey);
    }
    await _prefs.setStringList(_archivedKey, set.toList());
  }

  DateTime? getLastReadAt(String peerId) {
    final millis = _prefs.getInt(_readKey(peerId));
    return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  Future<void> setLastReadAt(String peerId, DateTime at) async {
    if (_activeAccountId.isEmpty) return;
    await _prefs.setInt(_readKey(peerId), at.millisecondsSinceEpoch);
  }

  DateTime? getLastDialogShownAt(String peerId) {
    final millis = _prefs.getInt(_dialogKey(peerId));
    return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  Future<void> setLastDialogShownAt(String peerId, DateTime at) async {
    if (_activeAccountId.isEmpty) return;
    await _prefs.setInt(_dialogKey(peerId), at.millisecondsSinceEpoch);
  }

  bool isAccepted(String peerId) {
    return _prefs.getBool(_acceptedKey(peerId)) ?? false;
  }

  Future<void> setAccepted(String peerId, bool value) async {
    if (_activeAccountId.isEmpty) return;
    await _prefs.setBool(_acceptedKey(peerId), value);
  }

  /// Отметка «правила городского чата показаны» (локально на устройстве, по группе).
  bool hasSeenCityChatRules(String groupId) {
    return _prefs.getBool(_cityChatRulesKey(groupId)) ?? false;
  }

  Future<void> setSeenCityChatRules(String groupId) async {
    if (_activeAccountId.isEmpty) return;
    await _prefs.setBool(_cityChatRulesKey(groupId), true);
  }

  bool isDeclined(String peerId) {
    return _prefs.getBool(_declinedKey(peerId)) ?? false;
  }

  Future<void> setDeclined(
    String peerId,
    bool value, {
    int? lastMessageEpochMs,
  }) async {
    if (_activeAccountId.isEmpty) return;
    if (value) {
      await _prefs.setBool(_declinedKey(peerId), true);
      if (lastMessageEpochMs != null) {
        await _prefs.setInt(_declinedMsgEpochKey(peerId), lastMessageEpochMs);
      }
    } else {
      await _prefs.remove(_declinedKey(peerId));
      await _prefs.remove(_declinedMsgEpochKey(peerId));
    }
  }

  bool declinedHidesRequest(String peerId, DateTime threadLastMessageAt) {
    if (!isDeclined(peerId)) return false;
    final snap = _prefs.getInt(_declinedMsgEpochKey(peerId));
    if (snap == null) return true;
    return threadLastMessageAt.millisecondsSinceEpoch <= snap;
  }

  /// [conversationStorageKey] — как в списке (`direct:peerId`, `group:…`); совпадает с ключом архива.
  Future<void> clearPeerState(String conversationStorageKey) async {
    if (_activeAccountId.isEmpty) return;
    final prefsPeer = _prefsPeerIdFromThreadKey(conversationStorageKey);
    final archived = getArchivedPeerIds();
    if (archived.remove(conversationStorageKey)) {
      await _prefs.setStringList(_archivedKey, archived.toList());
    }
    await _prefs.remove(_readKey(prefsPeer));
    await _prefs.remove(_dialogKey(prefsPeer));
    await _prefs.remove(_acceptedKey(prefsPeer));
    await _prefs.remove(_declinedKey(prefsPeer));
    await _prefs.remove(_declinedMsgEpochKey(prefsPeer));
    await _prefs.remove(_hiddenMessagesKey(prefsPeer));
  }

  Set<String> getHiddenMessageIds(String peerId) {
    final list = _prefs.getStringList(_hiddenMessagesKey(peerId));
    return list != null ? list.toSet() : <String>{};
  }

  Future<void> addHiddenMessageIds(String peerId, Iterable<String> ids) async {
    if (_activeAccountId.isEmpty) return;
    if (ids.isEmpty) return;
    final current = getHiddenMessageIds(peerId);
    current.addAll(ids.where((e) => e.isNotEmpty));
    await _prefs.setStringList(_hiddenMessagesKey(peerId), current.toList());
  }

  /// Сброс всех ключей текущего аккаунта (например при выходе).
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

  /// Удаляет глобальные (до мультиаккаунтных) ключи из старых версий приложения.
  Future<void> clearLegacyGlobalKeys() async {
    await _prefs.remove(_legacyArchivedKey);
    const legacyPrefixes = <String>[
      'tmr_tau_chat_read_',
      'tmr_tau_chat_dialog_',
      'tmr_tau_chat_accepted_',
      'tmr_tau_chat_declined_',
      'tmr_tau_chat_declined_msg_',
      'tmr_tau_chat_hidden_messages_',
    ];
    final keys = _prefs.getKeys().toList(growable: false);
    for (final key in keys) {
      for (final p in legacyPrefixes) {
        if (key.startsWith(p)) {
          await _prefs.remove(key);
          break;
        }
      }
    }
  }
}
