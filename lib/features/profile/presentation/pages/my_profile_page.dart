import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class MyProfilePage extends StatelessWidget {
  const MyProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          final user = state is AuthAuthenticated ? state.user : null;
          if (user == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Войдите в аккаунт'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.push('/login'),
                    child: const Text('Войти'),
                  ),
                ],
              ),
            );
          }
          return _ProfileContent(user: user);
        },
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              CachedAvatar(
                imageUrl: user.avatarUrl,
                radius: 48,
                fallbackText: user.name ?? user.email,
              ),
              const SizedBox(height: 12),
              Text(
                user.name ?? user.email,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (user.bio != null && user.bio!.isNotEmpty)
                Text(
                  user.bio!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        ListTile(
          leading: const Icon(Icons.shopping_bag_outlined),
          title: const Text('Мои заказы'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/orders'),
        ),
        ListTile(
          leading: const Icon(Icons.favorite_border),
          title: const Text('Избранное'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/home/favorites'),
        ),
        ListTile(
          leading: const Icon(Icons.chat_bubble_outline),
          title: const Text('Сообщения'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {},
        ),
        ListTile(
          leading: const Icon(Icons.store_outlined),
          title: const Text('Мой магазин'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/profile/${user.id}'),
        ),
        ListTile(
          leading: const Icon(Icons.add_business_outlined),
          title: const Text('Добавить товар'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/add-product'),
        ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Выйти'),
          onTap: () => context.read<AuthBloc>().add(const AuthSignOutRequested()),
        ),
      ],
    );
  }
}
