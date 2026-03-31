import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global mute state for in-app video playback.
///
/// true  -> muted
/// false -> sound enabled
class GlobalVideoAudioState {
  GlobalVideoAudioState._();

  static final GlobalVideoAudioState instance = GlobalVideoAudioState._();
  static const String _prefsKeyMuted = 'global_video_muted';

  final ValueNotifier<bool> isMuted = ValueNotifier<bool>(true);
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    isMuted.value = prefs.getBool(_prefsKeyMuted) ?? true;
    _loaded = true;
  }

  Future<void> setMuted(bool muted) async {
    isMuted.value = muted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyMuted, muted);
  }

  Future<void> toggle() => setMuted(!isMuted.value);
}
