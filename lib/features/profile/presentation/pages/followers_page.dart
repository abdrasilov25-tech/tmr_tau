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

    return Scaffold(
      appBar: AppBar(title: const Text('Подписчики')),
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
                  const Text('Не удалось загрузить подписчиков'),
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
                            .getFollowersUsers(uid);
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
                    'На вас пока никто не подписался',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final u = list[index];
              return ListTile(
                leading: CachedAvatar(
                  imageUrl: u.avatarUrl,
                  radius: 22,
                  fallbackText: u.name,
                ),
                title: Text(u.name),
                subtitle: u.bio != null && u.bio!.isNotEmpty
                    ? Text(
                        u.bio!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                onTap: () => context.push('/profile/${u.id}'),
              );
            },
          );
        },
      ),
    );
  }
}

