import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/storage/chat_list_storage.dart';
import 'core/storage/local_reactions_storage.dart';

bool _supabaseInitialized = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  // Не логируем URL и ключи даже в debug — не попадут в логи/краши
  assert(() {
    debugPrint('Supabase config loaded (URL/keys not logged)');
    return true;
  }());

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    _supabaseInitialized = true;
  } catch (e, st) {
    debugPrint('Supabase init failed: $e $st');
  }

  final prefs = await SharedPreferences.getInstance();
  final localReactions = LocalReactionsStorage(prefs);
  final chatListStorage = ChatListStorage(prefs);

  runApp(TmrTauApp(
    supabaseUrl: supabaseUrl,
    supabaseAnonKey: supabaseAnonKey,
    supabaseInitialized: _supabaseInitialized,
    localReactionsStorage: localReactions,
    chatListStorage: chatListStorage,
  ));
}
