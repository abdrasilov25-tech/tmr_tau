import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/widgets/app_error_view.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../state/settings_cubit.dart';

class PostVisibilityPage extends StatelessWidget {
  const PostVisibilityPage({super.key});

  static const String _public = 'public';
  static const String _followers = 'followers';
  static const String _onlyMe = 'only_me';

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Видимость постов')),
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
          title: const Text('Видимость постов'),
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
              final selected = state.settings.postVisibility;
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: RadioGroup<String>(
                        groupValue: selected,
                        onChanged: state.isSaving
                            ? (_) {}
                            : (v) {
                                final value = v ?? _followers;
                                context
                                    .read<SettingsCubit>()
                                    .update(postVisibility: value);
                              },
                        child: Column(
                          children: [
                            _RadioRow(
                              title: 'Публично',
                              value: _public,
                              onTap: state.isSaving
                                  ? null
                                  : () => context.read<SettingsCubit>().update(
                                        postVisibility: _public,
                                      ),
                            ),
                            _RadioRow(
                              title: 'Только подписчики',
                              value: _followers,
                              onTap: state.isSaving
                                  ? null
                                  : () => context.read<SettingsCubit>().update(
                                        postVisibility: _followers,
                                      ),
                            ),
                            _RadioRow(
                              title: 'Только я',
                              value: _onlyMe,
                              onTap: state.isSaving
                                  ? null
                                  : () => context.read<SettingsCubit>().update(
                                        postVisibility: _onlyMe,
                                      ),
                            ),
                          ],
                        ),
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

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.title,
    required this.value,
    this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Radio<String>(value: value),
      title: Text(title),
      onTap: onTap,
    );
  }
}

