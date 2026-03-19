import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/widgets/app_error_view.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../state/settings_cubit.dart';

class ActivityStatusPage extends StatelessWidget {
  const ActivityStatusPage({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Статус активности')),
        body: const Center(child: Text('Войдите, чтобы управлять настройками')),
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
          title: const Text('Статус активности'),
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
                      title: const Text('Показывать статус активности'),
                      subtitle: Text(
                        state.settings.activityStatusEnabled
                            ? 'Ваш статус будет виден другим пользователям.'
                            : 'Статус будет скрыт.',
                      ),
                      value: state.settings.activityStatusEnabled,
                      onChanged: state.isSaving
                          ? null
                          : (v) => context
                              .read<SettingsCubit>()
                              .update(activityStatusEnabled: v),
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

