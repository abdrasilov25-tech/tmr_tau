import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/storage/chat_list_storage.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../chat_unread_badge_controller.dart';

class GroupChatPage extends StatefulWidget {
  const GroupChatPage({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  late final SupabaseClient _client;
  String? _currentUserId;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  String _groupTitle = '';
  String? _groupAvatarUrl;

  @override
  void initState() {
    super.initState();
    _client = Supabase.instance.client;
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _currentUserId = authState.user.id;
    }
    _groupTitle = widget.groupName;
    _loadGroupMeta();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthBloc>().state;
      if (auth is! AuthAuthenticated) return;
      await context.read<ChatListStorage>().setLastReadAt(
            widget.groupId,
            DateTime.now(),
          );
      if (!mounted) return;
      await context.read<ChatUnreadBadgeController>().refresh();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Stream<List<Map<String, dynamic>>> _messagesStream() {
    return _client
        .from(SupabaseConstants.chatGroupMessagesTable)
        .stream(primaryKey: ['id'])
        .eq('group_id', widget.groupId)
        .order('created_at', ascending: true)
        .map((list) => list.cast<Map<String, dynamic>>());
  }

  Future<void> _loadGroupMeta() async {
    try {
      final row = await _client
          .from(SupabaseConstants.chatGroupsTable)
          .select('title,avatar_url')
          .eq('id', widget.groupId)
          .maybeSingle();
      if (row == null || !mounted) return;
      setState(() {
        _groupTitle = (row['title'] as String?) ?? widget.groupName;
        _groupAvatarUrl = row['avatar_url'] as String?;
      });
    } catch (_) {
      // keep fallback title/avatar
    }
  }

  Future<void> _openGroupInfo() async {
    final left = await context.push('/chat-group/${widget.groupId}/info');
    if (!mounted) return;
    if (left == true) {
      context.pop();
      return;
    }
    await _loadGroupMeta();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    final senderId = _currentUserId;
    if (text.isEmpty || senderId == null || _sending) return;
    setState(() => _sending = true);
    try {
      await _client.from(SupabaseConstants.chatGroupMessagesTable).insert({
        'group_id': widget.groupId,
        'sender_id': senderId,
        'text': text,
        'kind': 'text',
      });
      _controller.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось отправить: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: Text(_groupTitle)),
        body: const Center(child: Text('Войдите, чтобы открыть групповой чат')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _openGroupInfo,
          borderRadius: BorderRadius.circular(10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CachedAvatar(
                imageUrl: _groupAvatarUrl,
                radius: 14,
                fallbackText: _groupTitle,
              ),
              const SizedBox(width: 8),
              Flexible(child: Text(_groupTitle, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messagesStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Ошибка загрузки сообщений'));
                }
                final messages = snapshot.data ?? const [];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('Групповой чат создан. Напишите сообщение.'),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!_scrollController.hasClients) return;
                  _scrollController.jumpTo(
                    _scrollController.position.maxScrollExtent,
                  );
                });
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final m = messages[index];
                    final kind = m['kind'] as String? ?? 'text';
                    final text = (m['text'] as String?) ?? '';
                    if (kind != 'text') {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 320),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              text,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade900,
                                fontSize: 12.5,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    final isMe = m['sender_id'] == _currentUserId;
                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          text,
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Сообщение в группу',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendMessage,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
