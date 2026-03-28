import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/accounts/account_repository.dart';
import 'core/storage/chat_list_storage.dart';
import 'core/storage/chat_story_list_storage.dart';
import 'core/storage/local_reactions_storage.dart';
import 'core/storage/multi_account_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Future<bool> _initializeSupabase(String url, String anonKey) async {
  if (url.isEmpty || anonKey.isEmpty) return false;
  try {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      debug: false,
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
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.maximumSize = 200;
  imageCache.maximumSizeBytes = 120 * 1024 * 1024;

  await dotenv.load(fileName: '.env');
  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  // Не логируем URL и ключи даже в debug — не попадут в логи/краши
  assert(() {
    debugPrint('Supabase config loaded (URL/keys not logged)');
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
  if (supabaseOk) {
    final sessionUid = Supabase.instance.client.auth.currentUser?.id;
    chatListStorage.setActiveAccountId(sessionUid);
    chatStoryListStorage.setActiveAccountId(sessionUid);
    await chatListStorage.clearLegacyGlobalKeys();
    await chatStoryListStorage.clearLegacyGlobalKeys();
  }
  const secureStorage = FlutterSecureStorage();
  final multiAccountStorage = MultiAccountStorage(prefs, secureStorage);
  final accountRepository = AccountRepositoryImpl(prefs);

  runApp(TmrTauApp(
    supabaseUrl: supabaseUrl,
    supabaseAnonKey: supabaseAnonKey,
    supabaseInitialized: supabaseOk,
    localReactionsStorage: localReactions,
    chatListStorage: chatListStorage,
    chatStoryListStorage: chatStoryListStorage,
    multiAccountStorage: multiAccountStorage,
    accountRepository: accountRepository,
  ));
}
