import 'package:shared_preferences/shared_preferences.dart';

/// Persists user preferences for sounds and haptics in SharedPreferences.
class FeedbackPreferencesStorage {
  FeedbackPreferencesStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _soundsKey = 'tmr_tau_feedback_sounds_enabled';
  static const _hapticsKey = 'tmr_tau_feedback_haptics_enabled';

  bool get soundsEnabled => _prefs.getBool(_soundsKey) ?? true;
  bool get hapticsEnabled => _prefs.getBool(_hapticsKey) ?? true;

  Future<void> setSoundsEnabled(bool value) =>
      _prefs.setBool(_soundsKey, value);

  Future<void> setHapticsEnabled(bool value) =>
      _prefs.setBool(_hapticsKey, value);
}
