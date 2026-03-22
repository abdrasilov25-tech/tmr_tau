import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/widgets/app_error_view.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../state/settings_cubit.dart';
import '../widgets/login_history_block.dart';

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  bool _isClearing = false;

  Future<void> _clearSessions(
    BuildContext context,
    SettingsRepositoryImpl repo,
    String userId,
  ) async {
    if (_isClearing) return;
    setState(() => _isClearing = true);
    try {
      await repo.clearSessionsAndLogout(userId: userId);
      if (!context.mounted) return;
      context.go('/login');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось очистить сессии: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isClearing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Безопасность')),
        body: const Center(child: Text('Войдите, чтобы управлять безопасностью')),
      );
    }

    final repo = SettingsRepositoryImpl(Supabase.instance.client);

    return BlocProvider(
      create: (c) {
        return SettingsCubit(repo, userId: userId)..load();
      },
      child: Scaffold(
        backgroundColor: ThemedContentSurface.scaffold,
        appBar: AppBar(
          title: const Text('Безопасность'),
          centerTitle: true,
        ),
        body: BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, state) {
            if (state is SettingsLoading || state is SettingsInitial) {
              return const Center(child: AppLoading());
            }
            if (state is SettingsFailure) {
              return AppErrorView(
                message: state.message,
                onRetry: () => context.read<SettingsCubit>().load(),
              );
            }
            if (state is SettingsSuccess) {
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: SwitchListTile(
                      title: const Text('Двухфакторная аутентификация (2FA)'),
                      subtitle: const Text(
                        'В этой версии хранится как пользовательская настройка.',
                      ),
                      value: state.settings.twoFactorEnabled,
                      onChanged: state.isSaving
                          ? null
                          : (v) => context
                              .read<SettingsCubit>()
                              .update(twoFactorEnabled: v),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'История входов',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          LoginHistoryBlock(userId: userId),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Сессии',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _isClearing
                                ? null
                                : () =>
                                    _clearSessions(context, repo, userId),
                            icon: const Icon(Icons.logout_outlined),
                            label: _isClearing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: AppLoading(),
                                  )
                                : const Text('Выйти из всех сессий'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

