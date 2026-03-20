import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/themed_content_surface.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/notification_entity.dart';
import '../../domain/repositories/notifications_repository.dart';

class NotificationsActivityPage extends StatefulWidget {
  const NotificationsActivityPage({super.key});

  @override
  State<NotificationsActivityPage> createState() =>
      _NotificationsActivityPageState();
}

class _NotificationsActivityPageState extends State<NotificationsActivityPage> {
  bool _loading = true;
  bool _markingAll = false;
  String? _error;
  List<NotificationEntity> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;
    if (userId == null) {
      setState(() {
        _loading = false;
        _error = 'Войдите, чтобы смотреть уведомления';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<NotificationsRepository>();
      final list = await repo.getNotifications(userId);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _markAllRead() async {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;
    if (userId == null) return;
    setState(() => _markingAll = true);
    try {
      await context.read<NotificationsRepository>().markAllAsRead(userId);
      if (!mounted) return;
      await _load();
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _markOneRead(NotificationEntity item) async {
    if (item.isRead) return;
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;
    if (userId == null) return;
    await context
        .read<NotificationsRepository>()
        .markAsRead(item.id, userId);
    if (!mounted) return;
    setState(() {
      _items = _items
          .map(
            (n) => n.id == item.id
                ? NotificationEntity(
                    id: n.id,
                    userId: n.userId,
                    type: n.type,
                    createdAt: n.createdAt,
                    actorId: n.actorId,
                    title: n.title,
                    body: n.body,
                    productId: n.productId,
                    readAt: DateTime.now(),
                  )
                : n,
          )
          .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemedContentSurface.scaffold,
      appBar: AppBar(
        title: const Text('Уведомления'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _markingAll ? null : _markAllRead,
            child: _markingAll
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Прочитано'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? const Center(
                      child: Text('Пока нет уведомлений'),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return ListTile(
                            onTap: () async {
                              await _markOneRead(item);
                              if (!mounted) return;
                              final postId = _extractPostId(item.body);
                              if (postId != null) {
                                await context.push('/post/$postId');
                              }
                            },
                            leading: Icon(
                              _iconByType(item.type),
                              color: item.isRead
                                  ? Colors.grey
                                  : Theme.of(context).colorScheme.primary,
                            ),
                            title: Text(item.title ?? _titleByType(item.type)),
                            subtitle: Text(item.body ?? ''),
                            trailing: item.isRead
                                ? const Icon(Icons.done, size: 16, color: Colors.grey)
                                : const Icon(Icons.circle, size: 10),
                          );
                        },
                      ),
                    ),
    );
  }

  String _titleByType(String type) {
    switch (type) {
      case 'post_like':
        return 'Новый лайк';
      case 'post_comment':
        return 'Новый комментарий';
      default:
        return 'Уведомление';
    }
  }

  IconData _iconByType(String type) {
    switch (type) {
      case 'post_like':
        return Icons.favorite_rounded;
      case 'post_comment':
        return Icons.chat_bubble_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  String? _extractPostId(String? body) {
    if (body == null || body.isEmpty) return null;
    final match = RegExp(r'\[post:([a-fA-F0-9\-]{36})\]').firstMatch(body);
    return match?.group(1);
  }
}

