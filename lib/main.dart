import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';

bool _supabaseInitialized = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
    );
    _supabaseInitialized = true;
  } catch (e, st) {
    debugPrint('Supabase init failed: $e $st');
  }

  // Handle OAuth callback
  if (_supabaseInitialized) {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        // User signed in via OAuth
        debugPrint('User signed in via OAuth');
      }
    });
  }

  runApp(TmrTauApp(
    supabaseUrl: _supabaseUrl,
    supabaseAnonKey: _supabaseAnonKey,
    supabaseInitialized: _supabaseInitialized,
  ));
}

// Supabase: Project URL и anon key (Project Settings → API)
const String _supabaseUrl = 'https://mukxbmcrwxqfbuhxoltd.supabase.co';
const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im11a3hibWNyd3hxZmJ1aHhvbHRkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI4Nzc5NjksImV4cCI6MjA4ODQ1Mzk2OX0.28iNTcELc8BBsz6l2pTEn3mt-AQn6V_rGVqMbw5H3Gg';
