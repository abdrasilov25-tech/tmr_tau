import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/widgets/app_error_view.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../state/settings_cubit.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Уведомления')),
        body: const Center(child: Text('Войдите, чтобы настроить уведомления')),
      );
    }

    return BlocProvider(
      create: (c) {
        final repo = SettingsRepositoryImpl(Supabase.instance.client);
        return SettingsCubit(repo, userId: userId)..load();
      },
      child: Scaffold(
        backgroundColor: ThemedContentSurface.scaffold,
        appBar: AppBar(
          title: const Text('Уведомления'),
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
              final s = state.settings;
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SwitchListTile(
                          title: const Text('Push-уведомления'),
                          subtitle: const Text(
                            'Оповещения о действиях и новых событиях',
                          ),
                          value: s.pushNotificationsEnabled,
                          onChanged: state.isSaving
                              ? null
                              : (v) => context
                                  .read<SettingsCubit>()
                                  .update(pushNotificationsEnabled: v),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: const Text('Email-уведомления'),
                          subtitle: const Text(
                            'Подтверждения и уведомления на email',
                          ),
                          value: s.emailNotificationsEnabled,
                          onChanged: state.isSaving
                              ? null
                              : (v) => context
                                  .read<SettingsCubit>()
                                  .update(emailNotificationsEnabled: v),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: const Text('Внутри приложения'),
                          subtitle: const Text(
                            'Уведомления внутри ленты и профиля',
                          ),
                          value: s.inAppNotificationsEnabled,
                          onChanged: state.isSaving
                              ? null
                              : (v) => context.read<SettingsCubit>().update(
                                    inAppNotificationsEnabled: v,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.list_alt_outlined),
                      title: const Text('Настройки типа уведомлений'),
                      subtitle: const Text(
                        'Список типов уведомлений (заготовка UI)',
                      ),
                      onTap: () {
                        // В этой версии настройки хранятся общими переключателями.
                        // При необходимости можно расширить модель уведомлений.
                      },
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

