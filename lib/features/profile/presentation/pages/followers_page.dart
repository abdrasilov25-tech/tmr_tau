import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/user_list_skeleton.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/seller_profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';

class _FollowersData {
  final List<SellerProfileEntity> followers;
  final Set<String> myFollowingIds;

  const _FollowersData({required this.followers, required this.myFollowingIds});
}

class FollowersPage extends StatefulWidget {
  const FollowersPage({super.key});

  @override
  State<FollowersPage> createState() => _FollowersPageState();
}

class _FollowersPageState extends State<FollowersPage> {
  late Future<_FollowersData> _future;
  String? _myId;

  Future<_FollowersData> _load(String uid) async {
    final repo = context.read<ProfileRepository>();
    final followersFuture = repo.getFollowersUsers(uid);
    final followingFuture = Supabase.instance.client
        .from(SupabaseConstants.followersTable)
        .select('following_id')
        .eq('follower_id', uid);
    final results = await Future.wait<Object?>([
      followersFuture,
      followingFuture,
    ]);
    final followers = results[0]! as List<SellerProfileEntity>;
    final myFollowingIds = (results[1]! as List)
        .map((e) => (e as Map)['following_id'] as String)
        .toSet();
    return _FollowersData(followers: followers, myFollowingIds: myFollowingIds);
  }

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _myId = authState.user.id;
      _future = _load(_myId!);
    } else {
      _future = Future.value(
        const _FollowersData(followers: [], myFollowingIds: {}),
      );
    }
  }

  void _reload() {
    if (_myId == null) return;
    setState(() => _future = _load(_myId!));
  }

  Future<void> _toggleFollow(SellerProfileEntity user) async {
    final me = _myId;
    if (me == null) return;
    try {
      await context.read<ProfileRepository>().toggleFollow(me, user.id);
      _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось выполнить действие')),
      );
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

    return Scaffold(
      appBar: AppBar(title: const Text('Подписчики')),
      body: BlocListener<AuthBloc, AuthState>(
        listenWhen: (prev, curr) =>
            curr is AuthAuthenticated &&
            (prev is! AuthAuthenticated || prev.user.id != curr.user.id),
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            _myId = state.user.id;
            _reload();
          }
        },
        child: FutureBuilder<_FollowersData>(
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
                      onPressed: _reload,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              );
            }
            final data = snapshot.data!;
            final list = data.followers;
            if (list.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_outline, size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      'На вас пока никто не подписался',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              itemCount: list.length,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final u = list[index];
                final iFollow = data.myFollowingIds.contains(u.id);
                final isMutual = iFollow; // они подписаны на меня И я на них

                return _FollowerTile(
                  user: u,
                  iFollow: iFollow,
                  isMutual: isMutual,
                  onTap: () => context.push('/profile/${u.id}'),
                  onFollowTap: () => _toggleFollow(u),
                  onMessageTap: () => context.push(
                    '/chat/${u.id}?name=${Uri.encodeComponent(u.name)}',
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _FollowerTile extends StatelessWidget {
  const _FollowerTile({
    required this.user,
    required this.iFollow,
    required this.isMutual,
    required this.onTap,
    required this.onFollowTap,
    required this.onMessageTap,
  });

  final SellerProfileEntity user;
  final bool iFollow;
  final bool isMutual;
  final VoidCallback onTap;
  final VoidCallback onFollowTap;
  final VoidCallback onMessageTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CachedAvatar(
                imageUrl: user.avatarUrl,
                radius: 24,
                fallbackText: user.name,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isMutual) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Друзья',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (user.bio != null && user.bio!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        user.bio!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      'Подписан на вас',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!iFollow)
                _ActionButton(
                  label: 'Подписаться',
                  filled: true,
                  onTap: onFollowTap,
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionButton(
                      label: 'Сообщение',
                      filled: false,
                      onTap: onMessageTap,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        ),
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text(label),
    );
  }
}
