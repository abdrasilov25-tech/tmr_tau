import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/user_list_skeleton.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/seller_profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';

class FollowingPage extends StatefulWidget {
  const FollowingPage({super.key});

  @override
  State<FollowingPage> createState() => _FollowingPageState();
}

class _FollowingPageState extends State<FollowingPage> {
  late Future<List<SellerProfileEntity>> _future;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final uid = authState.user.id;
      _future = context.read<ProfileRepository>().getFollowingUsers(uid);
    } else {
      _future = Future.value(const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Подписки')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Войдите, чтобы видеть подписки'),
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
      appBar: AppBar(title: const Text('Подписки')),
      body: FutureBuilder<List<SellerProfileEntity>>(
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
                  const Text('Не удалось загрузить подписки'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        final uid =
                            (context.read<AuthBloc>().state as AuthAuthenticated)
                                .user
                                .id;
                        _future = context
                            .read<ProfileRepository>()
                            .getFollowingUsers(uid);
                      });
                    },
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
                    'Вы ни на кого не подписаны',
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
                    subtitle: u.bio != null && u.bio!.isNotEmpty
                        ? Text(
                            u.bio!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: FilledButton.tonal(
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
    );
  }
}

