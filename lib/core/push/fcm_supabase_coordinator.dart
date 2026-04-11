import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/supabase_constants.dart';
import '../firebase/firebase_pigeon_retry.dart';
import '../../firebase_options.dart';
import 'push_platform.dart';

/// Регистрация FCM-токена в Supabase: две подписки, снимаются в [dispose].
///
/// Нет тяжёлых колбеков на пользователя: один upsert/delete, дедуп по памяти (две строки),
/// защита от параллельного [sync].
final class FcmSupabaseCoordinator {
  FcmSupabaseCoordinator(this._client);

  final SupabaseClient _client;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<String>? _tokenRefreshSub;

  bool _running = false;
  bool _syncBusy = false;
  String? _lastPushedKey;

  bool get _useFirebase =>
      !kIsWeb &&
      DefaultFirebaseOptions.android.projectId != kFirebasePlaceholderProjectId;

  void start() {
    if (!_useFirebase || _running) {
      return;
    }
    _running = true;

    _authSub = _client.auth.onAuthStateChange.listen(
      _onAuthState,
      onError: (Object e, StackTrace st) =>
          debugPrint('FCM auth listener: $e'),
    );

    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      (_) => unawaited(syncTokenBestEffort()),
      onError: (Object e, StackTrace st) =>
          debugPrint('FCM token refresh: $e'),
    );

    unawaited(syncTokenBestEffort());
  }

  void _onAuthState(AuthState data) {
    if (data.session != null) {
      unawaited(syncTokenBestEffort());
    }
  }

  /// Вызывать из [AuthRepositoryImpl.signOut] до сброса сессии — иначе RLS delete не сработает.
  Future<void> clearCurrentDeviceTokenBeforeSignOut() async {
    if (!_useFirebase) return;
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final token = await firebasePigeonRetry(
        () => FirebaseMessaging.instance.getToken(),
      );
      if (token == null || token.isEmpty) return;
      await _client
          .from(SupabaseConstants.userPushTokensTable)
          .delete()
          .eq('user_id', uid)
          .eq('fcm_token', token);
      if (_lastPushedKey == '$uid|$token') {
        _lastPushedKey = null;
      }
    } catch (e, st) {
      assert(() {
        debugPrint('FCM clear token: $e $st');
        return true;
      }());
    }
  }

  Future<void> syncTokenBestEffort() async {
    if (!_useFirebase || _syncBusy) return;
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;

    _syncBusy = true;
    try {
      final token = await firebasePigeonRetry(
        () => FirebaseMessaging.instance.getToken(),
      );
      if (token == null || token.isEmpty) return;

      final key = '$uid|$token';
      if (_lastPushedKey == key) return;

      final platform = pushPlatformLabel();
      await _client.from(SupabaseConstants.userPushTokensTable).upsert(
            {
              'user_id': uid,
              'fcm_token': token,
              'platform': platform,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            onConflict: 'user_id,fcm_token',
          );

      _lastPushedKey = key;
    } catch (e, st) {
      assert(() {
        debugPrint('FCM sync: $e $st');
        return true;
      }());
    } finally {
      _syncBusy = false;
    }
  }

  void dispose() {
    unawaited(_authSub?.cancel());
    unawaited(_tokenRefreshSub?.cancel());
    _authSub = null;
    _tokenRefreshSub = null;
    _running = false;
    _lastPushedKey = null;
  }
}
