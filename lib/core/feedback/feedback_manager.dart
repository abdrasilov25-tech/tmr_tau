import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'feedback_preferences_storage.dart';

/// Centralized manager for UI sound effects and haptic feedback.
///
/// Initialise once in main.dart via [FeedbackManager.init].
/// Then call from anywhere: [FeedbackManager.instance].
///
/// Sound files (optional, <300ms):
///   assets/sounds/success.mp3
///   assets/sounds/error.mp3
///   assets/sounds/message_sent.mp3
///   assets/sounds/message_received.mp3
///
/// If files are absent the method silently skips playback —
/// haptics still fire.
class FeedbackManager {
  FeedbackManager._(this._prefs);

  static FeedbackManager? _instance;

  /// Must be called once after [SharedPreferences.getInstance].
  static void init(FeedbackPreferencesStorage prefs) {
    _instance ??= FeedbackManager._(prefs);
  }

  static FeedbackManager get instance {
    assert(_instance != null,
        'FeedbackManager.init() must be called before using instance');
    return _instance!;
  }

  final FeedbackPreferencesStorage _prefs;

  // Single player — prevents overlapping sounds.
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Light tap haptic + system click sound.
  Future<void> buttonTap() async {
    await _haptic(() => HapticFeedback.lightImpact());
    await _systemClick();
  }

  /// Success haptic (medium impact) + success sound.
  Future<void> success() async {
    await _haptic(() => HapticFeedback.mediumImpact());
    await _playAsset('sounds/success.wav');
  }

  /// Error haptic (heavy impact) + error sound.
  Future<void> error() async {
    await _haptic(() => HapticFeedback.heavyImpact());
    await _playAsset('sounds/error.wav');
  }

  /// Medium impact haptic + whoosh sound for outgoing messages.
  Future<void> messageSent() async {
    await _haptic(() => HapticFeedback.mediumImpact());
    await _playAsset('sounds/message_sent.wav');
  }

  /// Light impact haptic + pop sound for incoming messages.
  /// Call only when the chat screen is visible.
  Future<void> messageReceived() async {
    await _haptic(() => HapticFeedback.lightImpact());
    await _playAsset('sounds/message_received.wav');
  }

  /// Short ping when new activity lands in the in-app notifications list or peek bar.
  Future<void> notificationActivity() async {
    await _haptic(() => HapticFeedback.lightImpact());
    await _playAsset('sounds/message_received.wav');
  }

  /// Heavy impact + dramatic boom — Battle section entry.
  Future<void> battleEntry() async {
    await _haptic(() => HapticFeedback.heavyImpact());
    await _playAsset('sounds/wow_battle.wav');
  }

  /// Medium impact + magical arpeggio — Shop section entry.
  Future<void> shopEntry() async {
    await _haptic(() => HapticFeedback.mediumImpact());
    await _playAsset('sounds/wow_shop.wav');
  }

  /// Medium impact + coin jingle — Wallet section entry.
  Future<void> walletEntry() async {
    await _haptic(() => HapticFeedback.mediumImpact());
    await _playAsset('sounds/wow_wallet.wav');
  }

  // ─── Private helpers ───────────────────────────────────────────────────────

  Future<void> _haptic(Future<void> Function() fn) async {
    if (!_prefs.hapticsEnabled) return;
    try {
      await fn();
    } catch (e) {
      // Haptics not supported on this device — ignore.
    }
  }

  /// Plays the native system click sound (no audio file required).
  Future<void> _systemClick() async {
    if (!_prefs.soundsEnabled) return;
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (e) { debugPrint('$e'); }
  }

  /// Plays an asset sound file. Silently skips if the file is absent.
  Future<void> _playAsset(String assetPath) async {
    if (!_prefs.soundsEnabled) return;
    if (_isPlaying) return; // Prevent overlapping sounds.
    try {
      _isPlaying = true;
      await _player.play(AssetSource(assetPath));
      _player.onPlayerComplete.first.then((_) => _isPlaying = false);
    } catch (e) {
      // Asset not found or audio session error — ignore silently.
      _isPlaying = false;
    }
  }
}
