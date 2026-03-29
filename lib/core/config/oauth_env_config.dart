import 'package:flutter_dotenv/flutter_dotenv.dart';

class OAuthEnvConfig {
  static String get googleIosClientId =>
      (dotenv.env['GOOGLE_IOS_CLIENT_ID'] ?? '').trim();

  static String get googleWebClientId =>
      (dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '').trim();

  static String get googleWebClientSecret =>
      (dotenv.env['GOOGLE_WEB_CLIENT_SECRET'] ?? '').trim();

  static String get redirectTo =>
      (dotenv.env['OAUTH_REDIRECT_TO'] ?? 'tmrtau://auth/callback').trim();

  /// Для приложения достаточно client ID (iOS + Web). Client Secret задаётся
  /// в Supabase Dashboard (Google provider), в клиент его передавать не нужно.
  static bool get hasGoogleOAuthEnv =>
      googleIosClientId.isNotEmpty && googleWebClientId.isNotEmpty;
}
