import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tmr_tau/app.dart';
import 'package:tmr_tau/core/storage/local_reactions_storage.dart';

void main() {
  late LocalReactionsStorage localReactionsStorage;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    localReactionsStorage = LocalReactionsStorage(prefs);
  });

  group('TmrTauApp', () {
    testWidgets(
        'показывает экран настройки Supabase, когда Supabase не инициализирован',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        TmrTauApp(
          supabaseUrl: 'https://test.supabase.co',
          supabaseAnonKey: 'test-key',
          supabaseInitialized: false,
          localReactionsStorage: localReactionsStorage,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Supabase'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });
  });
}
