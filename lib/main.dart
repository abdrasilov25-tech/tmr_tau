import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'app.dart';
import 'core/accounts/account_repository.dart';
import 'core/storage/chat_list_storage.dart';
import 'core/storage/chat_story_list_storage.dart';
import 'core/storage/local_reactions_storage.dart';
import 'core/storage/multi_account_storage.dart';
import 'features/chat/data/chat_streak_storage.dart';
import 'features/chat/data/chat_pets_storage.dart';
import 'features/chat/data/chat_sticker_favorites_storage.dart';
import 'core/config/oauth_env_config.dart';
import 'core/feedback/feedback_manager.dart';
import 'core/feedback/feedback_preferences_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

String _supabaseProjectRefFromUrl(String url) {
  if (url.isEmpty) return 'empty';
  try {
    final host = Uri.parse(url).host;
    if (host.isEmpty) return 'invalid_host';
    return host.split('.').first;
  } catch (e) {
    debugPrint('$e');
    return 'invalid_url';
  }
}

Future<bool> _initializeSupabase(String url, String anonKey) async {
  if (url.isEmpty || anonKey.isEmpty) return false;
  try {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      debug: kDebugMode,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUri: true,
      ),
    );
    return true;
  } catch (e, st) {
    debugPrint('Supabase init failed: $e $st');
    return false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Меньше повторных декодирований при возврате на вкладки / свайпах по ленте.
  // ~100 записей / 72 MB — ориентир для релиза (2+ GB RAM).
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.maximumSize = 100;
  imageCache.maximumSizeBytes = 72 * 1024 * 1024;

  // .env не бандлим в assets: локально — файл в корне + optional load;
  // CI/релиз — --dart-define=... или --dart-define-from-file=.env
  const defUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  const defAnon = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  await dotenv.load(
    fileName: '.env',
    isOptional: true,
    mergeWith: {
      if (defUrl.isNotEmpty) 'SUPABASE_URL': defUrl,
      if (defAnon.isNotEmpty) 'SUPABASE_ANON_KEY': defAnon,
    },
  );
  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  final supabaseProjectRef = _supabaseProjectRefFromUrl(supabaseUrl);

  // Не логируем URL и ключи даже в debug — не попадут в логи/краши
  assert(() {
    debugPrint('Supabase config loaded (URL/keys not logged)');
    debugPrint('Supabase project ref: $supabaseProjectRef');
    debugPrint(
      'OAuth env loaded (google keys present: ${OAuthEnvConfig.hasGoogleOAuthEnv})',
    );
    return true;
  }());

  /// Параллельно: Supabase и SharedPreferences — быстрее первый кадр после `runApp`.
  final startup = await Future.wait<Object?>([
    _initializeSupabase(supabaseUrl, supabaseAnonKey),
    SharedPreferences.getInstance(),
  ]);
  final supabaseOk = startup[0] == true;
  final prefs = startup[1]! as SharedPreferences;
  final localReactions = LocalReactionsStorage(prefs);
  final chatListStorage = ChatListStorage(prefs);
  final chatStoryListStorage = ChatStoryListStorage(prefs);
  final chatStreakStorage = ChatStreakStorage(prefs);
  final chatPetsStorage = ChatPetsStorage(prefs);
  final chatStickerFavoritesStorage = ChatStickerFavoritesStorage(prefs);
  if (supabaseOk) {
    final sessionUid = Supabase.instance.client.auth.currentUser?.id;
    chatListStorage.setActiveAccountId(sessionUid);
    chatStoryListStorage.setActiveAccountId(sessionUid);
    chatStreakStorage.setActiveUserId(sessionUid);
    chatPetsStorage.setActiveUserId(sessionUid);
    chatStickerFavoritesStorage.setActiveUserId(sessionUid);
    await chatListStorage.clearLegacyGlobalKeys();
    await chatStoryListStorage.clearLegacyGlobalKeys();
  }
  final feedbackPrefs = FeedbackPreferencesStorage(prefs);
  FeedbackManager.init(feedbackPrefs);

  const secureStorage = FlutterSecureStorage();
  final multiAccountStorage = MultiAccountStorage(prefs, secureStorage);
  final accountRepository = AccountRepositoryImpl(prefs);

  runApp(TmrTauApp(
    feedbackPreferencesStorage: feedbackPrefs,
    supabaseUrl: supabaseUrl,
    supabaseAnonKey: supabaseAnonKey,
    supabaseInitialized: supabaseOk,
    localReactionsStorage: localReactions,
    chatListStorage: chatListStorage,
    chatStoryListStorage: chatStoryListStorage,
    chatStreakStorage: chatStreakStorage,
    chatPetsStorage: chatPetsStorage,
    chatStickerFavoritesStorage: chatStickerFavoritesStorage,
    multiAccountStorage: multiAccountStorage,
    accountRepository: accountRepository,
  ));
}
