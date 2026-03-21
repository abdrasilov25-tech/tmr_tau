import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class ChannelPage extends StatefulWidget {
  const ChannelPage({super.key, required this.channelId, required this.title});

  final String channelId;
  final String title;

  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  late final SupabaseClient _client;
  String? _currentUserId;
  String? _ownerId;
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _client = Supabase.instance.client;
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _currentUserId = authState.user.id;
    }
    _loadChannelOwner();
  }

  Future<void> _loadChannelOwner() async {
    try {
      final row = await _client
          .from(SupabaseConstants.userChannelsTable)
          .select('owner_id')
          .eq('id', widget.channelId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _ownerId = row?['owner_id'] as String?;
      });
    } catch (_) {
      // no-op
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canPost => _currentUserId != null && _currentUserId == _ownerId;

  Stream<List<Map<String, dynamic>>> _messagesStream() {
    return _client
        .from(SupabaseConstants.channelMessagesTable)
        .stream(primaryKey: ['id'])
        .eq('channel_id', widget.channelId)
        .order('created_at')
        .map((list) => list.cast<Map<String, dynamic>>());
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (!_canPost || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _client.from(SupabaseConstants.channelMessagesTable).insert({
        'channel_id': widget.channelId,
        'sender_id': _currentUserId,
        'text': text,
      });
      _controller.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отправить пост канала: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
                  return const Center(child: Text('Ошибка загрузки канала'));
                }
                final items = snapshot.data ?? const [];
                if (items.isEmpty) {
                  return const Center(
                    child: Text('Канал создан. Публикаций пока нет.'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final text = (item['text'] as String?) ?? '';
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(text),
                    );
                  },
                );
              },
            ),
          ),
          if (_canPost)
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
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Новая публикация канала',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
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
            )
          else
            const SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Text('Только владелец может публиковать в этом канале.'),
              ),
            ),
        ],
      ),
    );
  }
}
