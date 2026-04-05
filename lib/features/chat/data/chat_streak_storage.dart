import 'package:shared_preferences/shared_preferences.dart';

/// Tracks consecutive-day messaging streaks per peer DM.
/// Keys are scoped to the active user so multi-account works correctly.
class ChatStreakStorage {
  ChatStreakStorage(this._prefs);

  final SharedPreferences _prefs;
  String _activeUserId = '';

  void setActiveUserId(String? userId) {
    _activeUserId = userId?.trim() ?? '';
  }

  String get _base => _activeUserId.isEmpty
      ? 'chat_streak__nosession_'
      : 'chat_streak_uid_${_activeUserId}_';

  String _dateKey(String peerId) => '${_base}date_$peerId';
  String _countKey(String peerId) => '${_base}count_$peerId';

  /// Current streak in days for the given peer.
  int getStreak(String peerId) => _prefs.getInt(_countKey(peerId)) ?? 0;

  /// True if the user has earned the free Серийчик (streak >= 3).
  bool hasEarnedFreePet(String peerId) => getStreak(peerId) >= 3;

  /// Record messaging activity for today with [peerId].
  /// Returns the updated streak count.
  Future<int> recordActivity(String peerId) async {
    final today = _todayStr();
    final lastDate = _prefs.getString(_dateKey(peerId));

    // Already recorded today — return current streak without change.
    if (lastDate == today) return getStreak(peerId);

    int newStreak;
    if (lastDate == null) {
      newStreak = 1;
    } else {
      final last = DateTime.tryParse(lastDate);
      if (last == null) {
        newStreak = 1;
      } else {
        final now = DateTime.now();
        final todayDate = DateTime(now.year, now.month, now.day);
        final lastDateOnly = DateTime(last.year, last.month, last.day);
        final diff = todayDate.difference(lastDateOnly).inDays;
        if (diff == 1) {
          newStreak = getStreak(peerId) + 1;
        } else if (diff == 0) {
          // Same day (shouldn't happen after the guard above, but be safe)
          return getStreak(peerId);
        } else {
          // Streak broken
          newStreak = 1;
        }
      }
    }

    await _prefs.setString(_dateKey(peerId), today);
    await _prefs.setInt(_countKey(peerId), newStreak);
    return newStreak;
  }

  static String _todayStr() {
    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
