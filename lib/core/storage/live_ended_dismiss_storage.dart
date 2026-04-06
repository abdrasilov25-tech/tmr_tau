import 'package:shared_preferences/shared_preferences.dart';

/// Локально скрытые завершённые эфиры (строка в списке «Мои эфиры»), без удаления из БД.
class LiveEndedDismissStorage {
  LiveEndedDismissStorage(this._prefs);

  final SharedPreferences _prefs;

  static String _key(String userId) =>
      'tmr_tau_live_ended_dismiss_${userId.trim()}';

  Set<String> dismissedRoomIds(String userId) {
    final raw = _prefs.getString(_key(userId)) ?? '';
    if (raw.isEmpty) return {};
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  Future<void> dismissRoom(String userId, String roomId) async {
    final id = roomId.trim();
    if (id.isEmpty) return;
    final set = dismissedRoomIds(userId)..add(id);
    await _prefs.setString(_key(userId), set.join(','));
  }
}
