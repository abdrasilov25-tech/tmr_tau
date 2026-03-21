import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/widgets/app_error_view.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../domain/entities/login_history_entity.dart';
import '../../state/settings_cubit.dart';

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
                          FutureBuilder(
                            future: repo.getMyLoginHistory(
                              userId: userId,
                              limit: 10,
                            ),
                            builder: (context,
                                AsyncSnapshot<List<LoginHistoryEntity>> snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(child: AppLoading());
                              }
                              if (snapshot.hasError) {
                                return AppErrorView(
                                  message: snapshot.error.toString(),
                                  onRetry: () => setState(() {}),
                                );
                              }
                              final items =
                                  snapshot.data ?? const <LoginHistoryEntity>[];
                              if (items.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    'Пока нет сохраненных данных о входах.',
                                  ),
                                );
                              }
                              return Column(
                                children: items
                                    .map((e) => _LoginHistoryRow(
                                          loggedInAt: e.loggedInAt,
                                          ipAddress: e.ipAddress,
                                        ))
                                    .toList(growable: false),
                              );
                            },
                          ),
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

class _LoginHistoryRow extends StatelessWidget {
  const _LoginHistoryRow({
    required this.loggedInAt,
    this.ipAddress,
  });

  final DateTime loggedInAt;
  final String? ipAddress;

  @override
  Widget build(BuildContext context) {
    final dt = '${loggedInAt.day.toString().padLeft(2, '0')}.${loggedInAt.month.toString().padLeft(2, '0')}.${loggedInAt.year}';
    final hasIp = ipAddress != null && ipAddress!.isNotEmpty;
    final ip = hasIp ? ' • ${ipAddress!}' : '';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text('Вход: $dt'),
      subtitle: ip.isEmpty ? null : Text(ip),
    );
  }
}

