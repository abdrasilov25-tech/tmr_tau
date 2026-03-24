import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/repositories/settings_repository.dart';

/// Запрос на удаление через тикет поддержки — без отдельного бэкенд-конфига.
class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  bool _loading = false;

  Future<void> _submit() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    final user = authState.user;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loading = true);
    try {
      await context.read<SettingsRepository>().createSupportTicket(
            userId: user.id,
            title: 'Удаление аккаунта',
            description:
                'Прошу удалить мой аккаунт и связанные данные.\n'
                'User ID: ${user.id}\n'
                'Email: ${user.email}\n'
                'Имя: ${user.name ?? '—'}',
          );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Запрос отправлен. Мы обработаем его после проверки.',
          ),
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось отправить: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Удаление аккаунта')),
        body: const Center(child: Text('Войдите в аккаунт')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Удаление аккаунта')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Удаление аккаунта',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            'Мы создадим обращение в поддержку с вашим идентификатором. '
            'После обработки запроса данные будут удалены в соответствии с правилами сервиса.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Отправить запрос на удаление'),
          ),
        ],
      ),
    );
  }
}
