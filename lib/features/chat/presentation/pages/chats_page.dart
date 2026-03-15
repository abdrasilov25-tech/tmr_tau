import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/storage/chat_list_storage.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  late final SupabaseClient _client;
  late final String _currentUserId;
  late final ChatListStorage _chatStorage;
  late Future<List<_ChatThread>> _threadsFuture;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    _chatStorage = context.read<ChatListStorage>();
    if (authState is! AuthAuthenticated) {
      _threadsFuture = Future.value(const []);
      return;
    }
    _currentUserId = authState.user.id;
    _client = Supabase.instance.client;
    _threadsFuture = _loadThreads();
  }

  Future<List<_ChatThread>> _loadThreads() async {
    final res = await _client
        .from(SupabaseConstants.messagesTable)
        .select()
        .or('sender_id.eq.$_currentUserId,receiver_id.eq.$_currentUserId')
        .order('created_at', ascending: false);

    final List<dynamic> rows = res as List<dynamic>;
    final Map<String, _ChatThread> threadsByPeer = {};

    for (final row in rows) {
      final json = row as Map<String, dynamic>;
      final senderId = json['sender_id'] as String;
      final receiverId = json['receiver_id'] as String;
      final peerId = senderId == _currentUserId ? receiverId : senderId;
      final text = json['text'] as String? ?? '';
      final createdAt = DateTime.parse(json['created_at'] as String);

      if (!threadsByPeer.containsKey(peerId)) {
        threadsByPeer[peerId] = _ChatThread(
          peerId: peerId,
          peerName: 'Пользователь',
          peerAvatarUrl: null,
          lastMessageText: text,
          lastMessageAt: createdAt,
          lastMessageSenderId: senderId,
          unreadCount: 0,
        );
      }
    }

    if (threadsByPeer.isEmpty) return const [];

    for (final entry in threadsByPeer.entries) {
      final peerId = entry.key;
      final t = entry.value;
      final lastRead = _chatStorage.getLastReadAt(peerId);
      int unreadCount = 0;
      for (final row in rows) {
        final json = row as Map<String, dynamic>;
        if (json['sender_id'] == peerId && json['receiver_id'] == _currentUserId) {
          final msgAt = DateTime.parse(json['created_at'] as String);
          if (lastRead == null || msgAt.isAfter(lastRead)) unreadCount++;
        }
      }
      threadsByPeer[peerId] = t.copyWith(unreadCount: unreadCount);
    }

    for (final peerId in threadsByPeer.keys) {
      try {
        final userRes = await _client
            .from(SupabaseConstants.usersTable)
            .select('id, name, avatar')
            .eq('id', peerId)
            .maybeSingle();
        if (userRes == null) continue;
        final json = userRes;
        final name = json['name'] as String?;
        final avatar = json['avatar'] as String?;
        final existing = threadsByPeer[peerId];
        if (existing != null) {
          threadsByPeer[peerId] = existing.copyWith(
            peerName: name?.isNotEmpty == true ? name! : existing.peerName,
            peerAvatarUrl: avatar ?? existing.peerAvatarUrl,
            unreadCount: existing.unreadCount,
          );
        }
      } catch (_) {
        continue;
      }
    }

    final threads = threadsByPeer.values.toList()
      ..sort((a, b) {
        final aUnread = a.unreadCount > 0;
        final bUnread = b.unreadCount > 0;
        if (aUnread != bUnread) return aUnread ? -1 : 1;
        return b.lastMessageAt.compareTo(a.lastMessageAt);
      });
    return threads;
  }

  List<_ChatThread> _filterByTab(List<_ChatThread> threads, int tabIndex) {
    final archived = _chatStorage.getArchivedPeerIds();
    if (tabIndex == 0) {
      return threads.where((t) => !archived.contains(t.peerId)).toList();
    }
    if (tabIndex == 1) {
      return threads.where((t) {
        if (archived.contains(t.peerId)) return false;
        final lastRead = _chatStorage.getLastReadAt(t.peerId);
        final fromPeer = t.lastMessageSenderId != _currentUserId;
        return fromPeer && (lastRead == null || t.lastMessageAt.isAfter(lastRead));
      }).toList();
    }
    return threads.where((t) => archived.contains(t.peerId)).toList();
  }

  void _showThreadMenu(BuildContext context, _ChatThread t) {
    final archived = _chatStorage.getArchivedPeerIds();
    final isArchived = archived.contains(t.peerId);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(isArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
              title: Text(isArchived ? 'Из архива' : 'В архив'),
              onTap: () async {
                Navigator.pop(ctx);
                await _chatStorage.setArchived(t.peerId, !isArchived);
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Удалить чат', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Удалить чат?'),
                    content: Text('Переписка с ${t.peerName} будет удалена.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Удалить')),
                    ],
                  ),
                );
                if (ok == true && mounted) await _deleteChat(t);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteChat(_ChatThread t) async {
    try {
      try {
        await _client.rpc('delete_chat', params: {'peer_id': t.peerId});
      } catch (rpcError) {
        debugPrint('delete_chat RPC error: $rpcError');
        // Запасной вариант: удаление через два DELETE (нужны политики RLS на DELETE)
        await _client
            .from(SupabaseConstants.messagesTable)
            .delete()
            .eq('sender_id', _currentUserId)
            .eq('receiver_id', t.peerId);
        await _client
            .from(SupabaseConstants.messagesTable)
            .delete()
            .eq('sender_id', t.peerId)
            .eq('receiver_id', _currentUserId);
      }
      await _chatStorage.setArchived(t.peerId, false);
      if (mounted) setState(() { _threadsFuture = _loadThreads(); });
    } catch (e) {
      debugPrint('_deleteChat error: $e');
      if (mounted) {
        final msg = e.toString();
        final isRpcMissing = msg.contains('function') && msg.contains('does not exist');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isRpcMissing
                  ? 'Выполни в Supabase SQL Editor: drop + create function delete_chat (см. миграцию)'
                  : 'Не удалось удалить чат: $msg',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Мои чаты')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Войдите, чтобы видеть чаты'),
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

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Мои чаты'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Основные'),
              Tab(text: 'Непрочитанное'),
              Tab(text: 'Архив'),
            ],
          ),
        ),
        body: FutureBuilder<List<_ChatThread>>(
          future: _threadsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Не удалось загрузить чаты'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        setState(() { _threadsFuture = _loadThreads(); });
                      },
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              );
            }
            final allThreads = snapshot.data ?? [];
            return TabBarView(
              children: [0, 1, 2].map((tabIndex) {
                final threads = _filterByTab(allThreads, tabIndex);
                if (threads.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 56, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          tabIndex == 0
                              ? 'Пока нет чатов'
                              : tabIndex == 1
                                  ? 'Нет непрочитанных'
                                  : 'В архиве пусто',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  );
                }
                return _buildThreadList(context, threads);
              }).toList(),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openChat(_ChatThread t) async {
    final isUnread = t.unreadCount > 0;
    if (isUnread) {
      final accept = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Новое сообщение'),
          content: const Text(
            'Принять сообщение (отметить прочитанным) или оставить непрочитанным?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Оставить непрочитанным'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Принять'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (accept == true) {
        await _chatStorage.setLastReadAt(t.peerId, DateTime.now());
      }
      await context.push(
        '/chat/${t.peerId}?name=${Uri.encodeComponent(t.peerName)}&markRead=${accept == true ? '1' : '0'}',
      );
    } else {
      await context.push('/chat/${t.peerId}?name=${Uri.encodeComponent(t.peerName)}');
    }
    if (mounted) setState(() { _threadsFuture = _loadThreads(); });
  }

  Widget _buildThreadList(BuildContext context, List<_ChatThread> threads) {
    return ListView.separated(
      itemCount: threads.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final t = threads[index];
        final isUnread = t.unreadCount > 0;
        return ListTile(
          leading: CachedAvatar(
            imageUrl: t.peerAvatarUrl,
            radius: 22,
            fallbackText: t.peerName,
          ),
          title: Text(
            t.peerName,
            style: TextStyle(fontWeight: isUnread ? FontWeight.bold : FontWeight.normal),
          ),
          subtitle: Text(
            t.lastMessageText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _timeAgo(t.lastMessageAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (isUnread) ...[
                const SizedBox(width: 6),
                if (t.unreadCount > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${t.unreadCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
              IconButton(
                icon: const Icon(Icons.more_vert, size: 22),
                onPressed: () => _showThreadMenu(context, t),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
          onTap: () => _openChat(t),
          onLongPress: () => _showThreadMenu(context, t),
        );
      },
    );
  }
}

class _ChatThread {
  const _ChatThread({
    required this.peerId,
    required this.peerName,
    required this.peerAvatarUrl,
    required this.lastMessageText,
    required this.lastMessageAt,
    required this.lastMessageSenderId,
    this.unreadCount = 0,
  });

  final String peerId;
  final String peerName;
  final String? peerAvatarUrl;
  final String lastMessageText;
  final DateTime lastMessageAt;
  final String lastMessageSenderId;
  final int unreadCount;

  _ChatThread copyWith({
    String? peerName,
    String? peerAvatarUrl,
    int? unreadCount,
  }) {
    return _ChatThread(
      peerId: peerId,
      peerName: peerName ?? this.peerName,
      peerAvatarUrl: peerAvatarUrl ?? this.peerAvatarUrl,
      lastMessageText: lastMessageText,
      lastMessageAt: lastMessageAt,
      lastMessageSenderId: lastMessageSenderId,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

String _timeAgo(DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime);
  if (diff.inMinutes < 1) return 'только что';
  if (diff.inMinutes < 60) return '${diff.inMinutes} мин';
  if (diff.inHours < 24) return '${diff.inHours} ч';
  if (diff.inDays < 7) return '${diff.inDays} дн';
  return '${dateTime.day}.${dateTime.month}.${dateTime.year}';
}
