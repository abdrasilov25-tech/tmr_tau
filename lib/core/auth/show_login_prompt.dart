import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Диалог и переход на экран входа (гостевой режим и неавторизованные действия).
Future<void> showLoginRequiredDialog(
  BuildContext context, {
  String message = 'Войдите в аккаунт, чтобы выполнить это действие.',
}) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Нужен вход'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Войти'),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) {
    await context.push('/login');
  }
}
