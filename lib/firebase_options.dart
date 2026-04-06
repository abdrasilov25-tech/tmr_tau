// Замените на файл из `flutterfire configure` — пока стоит безопасная заглушка.
// Пока projectId == tmrtau-dev-placeholder, [initAppFirebase] не подключает Firebase.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Служебный маркер в репозитории; заменяется реальным projectId после FlutterFire.
const String kFirebasePlaceholderProjectId = 'tmrtau-dev-placeholder';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Firebase для Web не настроен');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('$defaultTargetPlatform не поддержан');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyPlaceholderNotARealKey0000000000000',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: kFirebasePlaceholderProjectId,
    storageBucket: 'tmrtau-dev-placeholder.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyPlaceholderNotARealKey0000000000000',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: kFirebasePlaceholderProjectId,
    storageBucket: 'tmrtau-dev-placeholder.appspot.com',
    iosBundleId: 'com.tmrtau.app',
  );
}
