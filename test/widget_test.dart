import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmr_tau/app.dart';

void main() {
  group('TmrTauApp', () {
    testWidgets(
        'показывает экран настройки Supabase, когда Supabase не инициализирован',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        TmrTauApp(
          supabaseUrl: 'https://test.supabase.co',
          supabaseAnonKey: 'test-key',
          supabaseInitialized: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Supabase'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });
  });
}
