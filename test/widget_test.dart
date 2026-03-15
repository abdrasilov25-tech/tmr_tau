import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tmr_tau/app.dart';
import 'package:tmr_tau/core/storage/chat_list_storage.dart';
import 'package:tmr_tau/core/storage/local_reactions_storage.dart';
import 'package:tmr_tau/core/storage/multi_account_storage.dart';

void main() {
  late LocalReactionsStorage localReactionsStorage;
  late ChatListStorage chatListStorage;
  late MultiAccountStorage multiAccountStorage;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    localReactionsStorage = LocalReactionsStorage(prefs);
    chatListStorage = ChatListStorage(prefs);
    multiAccountStorage = MultiAccountStorage(prefs, const FlutterSecureStorage());
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
          chatListStorage: chatListStorage,
          multiAccountStorage: multiAccountStorage,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Supabase'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });
  });
}
