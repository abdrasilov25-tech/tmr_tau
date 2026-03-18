import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/storage/chat_list_storage.dart';
import '../../../../core/theme/theme_decoration_helper.dart';
import '../../../../core/theme/theme_index_notifier.dart';
import '../../../../core/widgets/theme_picker_sheet.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.peerId,
    this.peerName = 'Продавец',
    this.markReadOnOpen = true,
  });

  final String peerId;
  final String peerName;
  /// Если true, при открытии чат помечается прочитанным. Если false — оставляем непрочитанным.
  final bool markReadOnOpen;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final SupabaseClient _client;
  String? _currentUserId;
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
    if (widget.markReadOnOpen) {
      context.read<ChatListStorage>().setLastReadAt(widget.peerId, DateTime.now());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Stream<List<Map<String, dynamic>>> _messagesStream() {
    if (_currentUserId == null) {
      return const Stream.empty();
    }
    final me = _currentUserId!;
    final peer = widget.peerId;
    // Стримим только сообщения, где текущий пользователь участвует как отправитель или получатель.
    // Это уменьшает объём данных по сравнению со стримом по всей таблице.
    final baseStream = _client
        .from(SupabaseConstants.messagesTable)
        .stream(primaryKey: ['id']);

    return baseStream.map(
      (list) {
        final dialogMessages = list
            // Оставляем только конкретный диалог me <-> peer
            .where(
              (m) =>
                  (m['sender_id'] == me && m['receiver_id'] == peer) ||
                  (m['sender_id'] == peer && m['receiver_id'] == me),
            )
            .toList()
          ..sort(
            (a, b) => (a['created_at'] as String)
                .compareTo(b['created_at'] as String),
          );

        // Ограничиваем количество сообщений в памяти (например, последние 200)
        const maxMessages = 200;
        if (dialogMessages.length <= maxMessages) {
          return dialogMessages;
        }
        return dialogMessages.sublist(
          dialogMessages.length - maxMessages,
          dialogMessages.length,
        );
      },
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _currentUserId == null || _sending) return;
    setState(() {
      _sending = true;
    });
    try {
      await _client.from(SupabaseConstants.messagesTable).insert({
        'sender_id': _currentUserId,
        'receiver_id': widget.peerId,
        'text': text,
      });
      _controller.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отправить сообщение: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.peerName),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Войдите, чтобы писать сообщения'),
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

    final themeNotifier = context.read<ThemeIndexNotifier>();

    return ListenableBuilder(
      listenable: themeNotifier.listenable,
      builder: (context, _) {
        final decoration = themeDecoration(
          themeNotifier.value,
          themeNotifier.customImagePath,
        );
        return Container(
          decoration: decoration,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              title: Text(widget.peerName),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.palette_outlined),
                  onPressed: _showThemePicker,
                ),
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _messagesStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Ошибка загрузки сообщений',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        );
                      }
                      final messages = snapshot.data ?? const [];
                      if (messages.isEmpty) {
                        return Center(
                          child: Text(
                            'Напишите первое сообщение',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        );
                      }
                      final me = _currentUserId;
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final m = messages[index];
                          final senderId = m['sender_id'] as String?;
                          final text = m['text'] as String? ?? '';
                          final isMe = senderId == me;
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
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                text,
                                style: TextStyle(
                                  color:
                                      isMe ? Colors.white : Colors.black87,
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
                  child: Material(
                    color: ThemedContentSurface.scaffoldElevated,
                    elevation: 8,
                    shadowColor: Colors.black26,
                    child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            decoration: const InputDecoration(
                              hintText: 'Сообщение',
                              border: OutlineInputBorder(),
                              isDense: true,
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
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.send),
                        ),
                      ],
                    ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showThemePicker() {
    final themeNotifier = context.read<ThemeIndexNotifier>();
    showThemePickerSheet(
      context,
      currentIndex: themeNotifier.value,
      onSelect: (index) => themeNotifier.setIndex(index),
      onAddCustom: () async {
        final picker = ImagePicker();
        final xFile = await picker.pickImage(source: ImageSource.gallery);
        if (xFile == null || !mounted) return;
        final bytes = await xFile.readAsBytes();
        if (!mounted) return;
        await themeNotifier.setCustomThemeFromImageBytes(bytes);
      },
    );
  }
}
