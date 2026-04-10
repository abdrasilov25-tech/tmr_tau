import 'package:flutter/foundation.dart';

/// Runtime flags for development sessions.
final class DevRuntimeFlags {
  DevRuntimeFlags._();

  /// Lightweight mode for local debug sessions.
  ///
  /// Enabled by default in debug to reduce CPU/thermal load:
  /// - skip periodic badge refreshes on startup/login
  /// - skip FCM coordinator auto-start
  /// - skip IAP store warm-up
  ///
  /// Disable when needed:
  /// `flutter run --dart-define=DEV_LIGHT_MODE=false`
  static final bool lightMode =
      kDebugMode && const bool.fromEnvironment('DEV_LIGHT_MODE', defaultValue: true);
}
