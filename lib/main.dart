import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';

bool _supabaseInitialized = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  debugPrint('SUPABASE_URL: $supabaseUrl');
  debugPrint(
    'SUPABASE_ANON_KEY is set: ${supabaseAnonKey.isNotEmpty ? 'YES' : 'NO'}',
  );

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    _supabaseInitialized = true;
  } catch (e, st) {
    debugPrint('Supabase init failed: $e $st');
  }

  runApp(TmrTauApp(
    supabaseUrl: supabaseUrl,
    supabaseAnonKey: supabaseAnonKey,
    supabaseInitialized: _supabaseInitialized,
  ));
}
