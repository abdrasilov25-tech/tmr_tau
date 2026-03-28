import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/user_list_skeleton.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/seller_profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';

class FollowersPage extends StatefulWidget {
  const FollowersPage({super.key});

  @override
  State<FollowersPage> createState() => _FollowersPageState();
}

class _FollowersPageState extends State<FollowersPage> {
  late Future<List<SellerProfileEntity>> _future;

  void _reloadFuture(String uid) {
    setState(() {
      _future = context.read<ProfileRepository>().getFollowersUsers(uid);
    });
  }

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final uid = authState.user.id;
      _future = context.read<ProfileRepository>().getFollowersUsers(uid);
    } else {
      _future = Future.value(const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Подписчики')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Войдите, чтобы видеть подписчиков'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.push('/login'),
                child: const Text('Войти'),
              ),
            ],
          ),
        ),
      );
    }

    final myId = authState.user.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Подписчики')),
      body: BlocListener<AuthBloc, AuthState>(
        listenWhen: (prev, curr) =>
            curr is AuthAuthenticated &&
            (prev is! AuthAuthenticated || prev.user.id != curr.user.id),
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            _reloadFuture(state.user.id);
          }
        },
        child: FutureBuilder<List<SellerProfileEntity>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const UserListSkeleton();
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Не удалось загрузить подписчиков'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => _reloadFuture(myId),
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              );
            }
            final list = snapshot.data ?? const [];
            if (list.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_outline,
                        size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      'На вас пока никто не подписался',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final u = list[index];
                final showFollowBack = !u.isFollowingByMe;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Material(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      leading: CachedAvatar(
                        imageUrl: u.avatarUrl,
                        radius: 24,
                        fallbackText: u.name,
                      ),
                      title: Text(
                        u.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: _followersSubtitle(context, u),
                      trailing: showFollowBack
                          ? FilledButton(
                              onPressed: () async {
                                try {
                                  await context
                                      .read<ProfileRepository>()
                                      .toggleFollow(myId, u.id);
                                  if (!context.mounted) return;
                                  _reloadFuture(myId);
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Не удалось подписаться: $e'),
                                    ),
                                  );
                                }
                              },
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text('Подписаться в ответ'),
                            )
                          : FilledButton.tonal(
                              onPressed: () => context.push(
                                '/chat/${u.id}?name=${Uri.encodeComponent(u.name)}',
                              ),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text('Сообщение'),
                            ),
                      onTap: () => context.push('/profile/${u.id}'),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget? _followersSubtitle(BuildContext context, SellerProfileEntity u) {
    final bio = u.bio?.trim();
    final hasBio = bio != null && bio.isNotEmpty;
    if (!u.isFollowingByMe) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasBio)
            Text(
              bio,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          if (hasBio) const SizedBox(height: 2),
          Text(
            'Подписан на вас',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    if (hasBio) {
      return Text(
        bio,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return null;
  }
}
