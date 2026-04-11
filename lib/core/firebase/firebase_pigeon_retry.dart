import 'package:flutter/services.dart';

/// Временный сбой Pigeon: `throw _createConnectionError(...)` → [PlatformException]
/// с `code == channel-error`, пока нативный side ещё не готов (гонка при старте).
bool _isTransientFirebaseChannelFailure(Object e) {
  if (e is PlatformException) {
    return e.code == 'channel-error' ||
        (e.message?.contains('Unable to establish connection on channel') ??
            false);
  }
  final s = e.toString();
  return s.contains('channel-error') ||
      s.contains('Unable to establish connection on channel');
}

/// Повтор вызова при «channel-error» (Firebase Core / Messaging / Analytics через Pigeon).
Future<T> firebasePigeonRetry<T>(
  Future<T> Function() action, {
  int maxAttempts = 8,
}) async {
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await action();
    } catch (e, st) {
      if (!_isTransientFirebaseChannelFailure(e) || attempt == maxAttempts) {
        Error.throwWithStackTrace(e, st);
      }
      final ms = (50 * attempt).clamp(20, 400);
      await Future<void>.delayed(Duration(milliseconds: ms));
    }
  }
  throw StateError('firebasePigeonRetry: unreachable');
}
