import 'dart:io' show Platform;

/// Платформа для записи FCM-токена (без `dart:io` на web).
String pushPlatformLabel() {
  if (Platform.isIOS) return 'ios';
  if (Platform.isAndroid) return 'android';
  return 'other';
}
