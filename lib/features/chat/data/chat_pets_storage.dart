import 'package:shared_preferences/shared_preferences.dart';

/// Stores owned pets and the active pet per DM chat.
/// Keys are scoped per user to support multi-account.
class ChatPetsStorage {
  ChatPetsStorage(this._prefs);

  final SharedPreferences _prefs;
  String _activeUserId = '';

  void setActiveUserId(String? userId) {
    _activeUserId = userId?.trim() ?? '';
  }

  String get _base => _activeUserId.isEmpty
      ? 'chat_pets__nosession_'
      : 'chat_pets_uid_${_activeUserId}_';

  String get _ownedKey => '${_base}owned';
  String _activePetKey(String peerId) => '${_base}active_$peerId';

  /// Returns all pet IDs owned by the current user.
  Set<String> getOwnedPets() =>
      (_prefs.getStringList(_ownedKey) ?? []).toSet();

  bool ownsPet(String petId) => getOwnedPets().contains(petId);

  Future<void> addOwnedPet(String petId) async {
    final owned = getOwnedPets();
    if (owned.add(petId)) {
      await _prefs.setStringList(_ownedKey, owned.toList());
    }
  }

  /// The active pet ID displayed in the DM with [peerId], or null.
  String? getActivePet(String peerId) =>
      _prefs.getString(_activePetKey(peerId));

  Future<void> setActivePet(String peerId, String petId) async {
    await _prefs.setString(_activePetKey(peerId), petId);
  }

  Future<void> clearActivePet(String peerId) async {
    await _prefs.remove(_activePetKey(peerId));
  }
}
