import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmr_tau/core/widgets/app_error_view.dart';

void main() {
  group('AppErrorView', () {
    testWidgets('показывает сообщение об ошибке', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppErrorView(message: 'Ошибка загрузки'),
          ),
        ),
      );

      expect(find.text('Ошибка загрузки'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('показывает кнопку Повторить когда передан onRetry',
        (WidgetTester tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppErrorView(
              message: 'Ошибка',
              onRetry: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Повторить'), findsOneWidget);
      await tester.tap(find.text('Повторить'));
      await tester.pump();
      expect(tapped, true);
    });

    testWidgets('не показывает кнопку Повторить когда onRetry null',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppErrorView(message: 'Ошибка'),
          ),
        ),
      );

      expect(find.text('Повторить'), findsNothing);
    });
  });
}
