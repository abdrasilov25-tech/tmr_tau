import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../firebase_options.dart';
import 'firebase_pigeon_retry.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await firebasePigeonRetry(
      () => Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ),
    );
  } catch (e, st) {
    debugPrint('[FCM background] Firebase.initializeApp: $e\n$st');
  }
}

/// Инициализация Firebase (Crashlytics, Analytics, FCM). Безопасно no-op при заглушке.
Future<void> initAppFirebase() async {
  if (kIsWeb) return;
  if (DefaultFirebaseOptions.android.projectId == kFirebasePlaceholderProjectId) {
    assert(() {
      debugPrint(
        'Firebase: заглушка projectId. Выполните: dart pub global activate '
        'flutterfire_cli && flutterfire configure',
      );
      return true;
    }());
    return;
  }

  // Короткая пауза: нативные плагины иногда регистрируют Pigeon чуть позже первого кадра.
  await Future<void>.delayed(const Duration(milliseconds: 32));

  try {
    await firebasePigeonRetry(
      () => Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ),
    );

    await firebasePigeonRetry(
      () => FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode),
    );

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    try {
      FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler);
    } catch (e, st) {
      debugPrint('[FCM] onBackgroundMessage registration: $e\n$st');
    }

    await firebasePigeonRetry(
      () => FirebaseMessaging.instance.setAutoInitEnabled(true),
    );
    try {
      final settings = await firebasePigeonRetry(
        () => FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        ),
      );
      assert(() {
        debugPrint('FCM permission: ${settings.authorizationStatus}');
        return true;
      }());
    } on PlatformException catch (e, st) {
      debugPrint('[FCM] requestPermission PlatformException: $e\n$st');
    }

    try {
      await firebasePigeonRetry(
        () => FirebaseAnalytics.instance.logAppOpen(),
      );
    } catch (e, st) {
      debugPrint('[Analytics] logAppOpen: $e\n$st');
    }
  } on PlatformException catch (e, st) {
    debugPrint('[Firebase] init PlatformException: $e\n$st');
  } catch (e, st) {
    debugPrint('[Firebase] init: $e\n$st');
  }
}
