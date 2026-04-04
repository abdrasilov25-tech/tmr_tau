import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Agora Video SDK: https://console.agora.io/
///
/// **App ID** — обязателен в `.env` ([AgoraLiveConfig.appId]).
///
/// **Токен** ([token]): если пусто, приложение запрашивает токен у Edge Function
/// `agora-rtc-token` (секреты `AGORA_APP_ID` + `AGORA_APP_CERTIFICATE` в Supabase).
/// Либо вставьте временный токен из консоли Agora в `AGORA_TOKEN`.
/// Если в консоли Agora **отключён** App Certificate — можно оставить токен пустым.
class AgoraLiveConfig {
  AgoraLiveConfig._();

  static String get appId => (dotenv.env['AGORA_APP_ID'] ?? '').trim();

  static String get token => (dotenv.env['AGORA_TOKEN'] ?? '').trim();

  static bool get isConfigured => appId.isNotEmpty;
}
