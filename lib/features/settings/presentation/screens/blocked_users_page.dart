import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_error_view.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../domain/entities/blocked_user_entity.dart';
import '../../state/blocked_users_cubit.dart';

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent - pos.pixels <= 300) {
      context.read<BlockedUsersCubit>().loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Заблокированные')),
        body: const Center(child: Text('Войдите, чтобы управлять блокировками')),
      );
    }

    return BlocProvider<BlockedUsersCubit>(
      create: (c) {
        final repo = SettingsRepositoryImpl(Supabase.instance.client);
        return BlockedUsersCubit(repo, blockerId: userId)..loadInitial();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Заблокированные пользователи'),
          centerTitle: true,
        ),
        body: BlocBuilder<BlockedUsersCubit, BlockedUsersState>(
          builder: (context, state) {
            if (state is BlockedUsersLoading || state is BlockedUsersInitial) {
              return const Center(child: AppLoading());
            }
            if (state is BlockedUsersFailure) {
              return AppErrorView(
                message: state.message,
                onRetry: () => context.read<BlockedUsersCubit>().loadInitial(),
              );
            }
            if (state is BlockedUsersSuccess) {
              final items = state.items;
              if (items.isEmpty) {
                return const Center(child: Text('Список пуст'));
              }

              final showBottomLoader =
                  state.isLoadingMore && state.hasMore;

              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: items.length + (showBottomLoader ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= items.length) {
                    return const _BottomLoader();
                  }
                  final item = items[index];
                  return _BlockedUserTile(
                    item: item,
                    isUnblocking: state.unblockingUserId == item.blockedUserId,
                    onUnblock: () =>
                        context.read<BlockedUsersCubit>().unblock(item.blockedUserId),
                  );
                },
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

class _BottomLoader extends StatelessWidget {
  const _BottomLoader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator())),
    );
  }
}

class _BlockedUserTile extends StatelessWidget {
  const _BlockedUserTile({
    required this.item,
    required this.onUnblock,
    required this.isUnblocking,
  });

  final BlockedUserEntity item;
  final VoidCallback onUnblock;
  final bool isUnblocking;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CachedAvatar(
          imageUrl: item.blockedUserAvatarUrl,
          fallbackText: item.blockedUserName ?? 'Пользователь',
          radius: 20,
        ),
        title: Text(item.blockedUserName ?? 'Пользователь'),
        subtitle: Text(
          'Блокировка: ${_formatDate(item.blockedAt)}',
        ),
        trailing: isUnblocking
            ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2))
            : FilledButton.tonal(
                onPressed: onUnblock,
                child: const Text('Разблокировать'),
              ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d.$m';
  }
}

