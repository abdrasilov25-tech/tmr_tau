import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
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
  late Future<List<_ChatThread>> _threadsFuture;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
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
        );
      }
    }

    if (threadsByPeer.isEmpty) return const [];

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
          );
        }
      } catch (_) {
        // Если не удалось загрузить пользователя, оставляем дефолтные данные
        continue;
      }
    }

    final threads = threadsByPeer.values.toList()
      ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return threads;
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

    return Scaffold(
      appBar: AppBar(title: const Text('Мои чаты')),
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
                      setState(() {
                        _threadsFuture = _loadThreads();
                      });
                    },
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            );
          }
          final threads = snapshot.data ?? const [];
          if (threads.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    'Пока нет чатов',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: threads.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final t = threads[index];
              return ListTile(
                leading: CachedAvatar(
                  imageUrl: t.peerAvatarUrl,
                  radius: 22,
                  fallbackText: t.peerName,
                ),
                title: Text(t.peerName),
                subtitle: Text(
                  t.lastMessageText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  _timeAgo(t.lastMessageAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                onTap: () {
                  final encodedName = Uri.encodeComponent(t.peerName);
                  context.push('/chat/${t.peerId}?name=$encodedName');
                },
              );
            },
          );
        },
      ),
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
  });

  final String peerId;
  final String peerName;
  final String? peerAvatarUrl;
  final String lastMessageText;
  final DateTime lastMessageAt;

  _ChatThread copyWith({
    String? peerName,
    String? peerAvatarUrl,
  }) {
    return _ChatThread(
      peerId: peerId,
      peerName: peerName ?? this.peerName,
      peerAvatarUrl: peerAvatarUrl ?? this.peerAvatarUrl,
      lastMessageText: lastMessageText,
      lastMessageAt: lastMessageAt,
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

