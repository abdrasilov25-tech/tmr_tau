import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await FirebaseMessaging.instance.setAutoInitEnabled(true);
  final settings = await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );
  assert(() {
    debugPrint('FCM permission: ${settings.authorizationStatus}');
    return true;
  }());

  FirebaseAnalytics.instance.logAppOpen();
}
