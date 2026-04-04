import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../domain/entities/notification_entity.dart';
import '../bloc/notifications_bloc.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Уведомления',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.black87,
              ),
        ),
        centerTitle: true,
        actions: [
          BlocBuilder<NotificationsBloc, NotificationsState>(
            buildWhen: (prev, curr) {
              final prevHas = prev is NotificationsLoaded && prev.notifications.isNotEmpty;
              final currHas = curr is NotificationsLoaded && curr.notifications.isNotEmpty;
              return prevHas != currHas;
            },
            builder: (context, state) {
              if (state is NotificationsLoaded && state.notifications.isNotEmpty) {
                return TextButton(
                  onPressed: () =>
                      context.read<NotificationsBloc>().add(NotificationsMarkAllRead()),
                  child: const Text('Прочитать все'),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: BlocBuilder<NotificationsBloc, NotificationsState>(
        builder: (context, state) {
          if (state is NotificationsLoading) {
            return const Center(child: AppLoading());
          }
          if (state is NotificationsFailure) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(state.message),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        context.read<NotificationsBloc>().add(NotificationsRequested()),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            );
          }
          if (state is NotificationsLoaded) {
            if (state.notifications.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 80,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Нет уведомлений',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: state.notifications.length,
              itemBuilder: (context, index) {
                final n = state.notifications[index];
                return _NotificationTile(
                  notification: n,
                  onTap: () {
                    if (!n.isRead) {
                      context.read<NotificationsBloc>().add(
                            NotificationsMarkRead(n.id),
                          );
                    }
                    if (n.type == 'follow' && n.actorId != null) {
                      context.push('/profile/${n.actorId}');
                    } else if (n.productId != null) {
                      context.push('/product/${n.productId}');
                    } else if (n.postId != null) {
                      context.push('/post/${n.postId}');
                    }
                  },
                );
              },
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  final NotificationEntity notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget leading;
    if (notification.actorId != null) {
      leading = CachedAvatar(
        imageUrl: notification.actorAvatarUrl,
        radius: 24,
        fallbackText: notification.actorName,
        enableLightboxOnTap: false,
      );
    } else {
      leading = CircleAvatar(
        radius: 24,
        backgroundColor: Colors.grey.shade200,
        child: Icon(
          _iconForType(notification.type),
          color: Colors.grey.shade600,
        ),
      );
    }

    return ListTile(
      leading: leading,
      title: Text(
        notification.title ?? notification.type,
        style: TextStyle(
          fontWeight: notification.isRead ? FontWeight.normal : FontWeight.w600,
        ),
      ),
      subtitle: notification.body != null
          ? Text(
              notification.body!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: notification.isRead ? null : const Icon(Icons.circle, size: 8, color: Colors.blue),
      onTap: onTap,
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'follow':
        return Icons.person_add_rounded;
      case 'like':
        return Icons.favorite_rounded;
      case 'comment':
        return Icons.comment_rounded;
      case 'purchase':
        return Icons.shopping_bag_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }
}
