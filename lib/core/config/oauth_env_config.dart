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

  /// URL, который Google должен разрешить для **Web** OAuth client (не путать с [redirectTo] приложения).
  /// Документация Supabase: Authorization → Providers → Google.
  static String? get supabaseAuthV1CallbackUrl {
    final url = (dotenv.env['SUPABASE_URL'] ?? '').trim();
    if (url.isEmpty) return null;
    final base = url.replaceAll(RegExp(r'/+$'), '');
    return '$base/auth/v1/callback';
  }

  /// Для приложения достаточно client ID (iOS + Web). Client Secret задаётся
  /// в Supabase Dashboard (Google provider), в клиент его передавать не нужно.
  static bool get hasGoogleOAuthEnv =>
      googleIosClientId.isNotEmpty && googleWebClientId.isNotEmpty;
}
