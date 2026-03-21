import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/storage/chat_list_storage.dart';
import '../../../../core/theme/theme_decoration_helper.dart';
import '../../../../core/theme/theme_index_notifier.dart';
import '../../../../core/widgets/theme_picker_sheet.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../stories/domain/entities/story_group_entity.dart';
import '../../../stories/domain/repositories/stories_repository.dart';
import '../../../stories/presentation/pages/story_viewer_args.dart';

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
  static const String _storyDmPrefix = '__story__';
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
                          final structured = _parseStoryDirectMessage(text);
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
                              child: structured == null
                                  ? Text(
                                      text,
                                      style: TextStyle(
                                        color:
                                            isMe ? Colors.white : Colors.black87,
                                      ),
                                    )
                                  : _StoryLinkedChatBubble(
                                      message: structured,
                                      isMe: isMe,
                                      onOpenStory: () => _openStoryFromMessage(
                                        structured.storyId,
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

  _StoryDirectMessage? _parseStoryDirectMessage(String text) {
    if (!text.startsWith('$_storyDmPrefix|')) return null;
    final parts = text.split('|');
    if (parts.length < 5) return null;
    String decode(String value) {
      try {
        return Uri.decodeComponent(value);
      } catch (_) {
        return value;
      }
    }

    final kind = parts[1];
    final storyId = decode(parts[2]);
    final previewUrl = decode(parts[3]);
    final payload = decode(parts[4]);
    if (storyId.isEmpty) return null;
    return _StoryDirectMessage(
      kind: kind,
      storyId: storyId,
      previewUrl: previewUrl,
      payload: payload,
    );
  }

  Future<void> _openStoryFromMessage(String storyId) async {
    if (storyId.isEmpty) return;
    try {
      final groups = await context.read<StoriesRepository>().getStoriesGroupedByUser();
      StoryGroupEntity? peerGroup;
      for (final g in groups) {
        if (g.userId == widget.peerId) {
          peerGroup = g;
          break;
        }
      }
      if (peerGroup == null || peerGroup.stories.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сторис недоступна')),
        );
        return;
      }
      final stories = peerGroup.stories;
      final storyIndex = stories.indexWhere((s) => s.id == storyId);
      if (storyIndex == -1) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Эта сторис уже недоступна')),
        );
        return;
      }
      final reorderedStories = [
        ...stories.sublist(storyIndex),
        ...stories.sublist(0, storyIndex),
      ];
      final reorderedGroup = StoryGroupEntity(
        userId: peerGroup.userId,
        stories: reorderedStories,
        userName: peerGroup.userName,
        userAvatarUrl: peerGroup.userAvatarUrl,
      );
      await context.push(
        '/stories',
        extra: StoryViewerArgs(
          groups: [reorderedGroup],
          initialGroupIndex: 0,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть сторис')),
      );
    }
  }
}

class _StoryDirectMessage {
  const _StoryDirectMessage({
    required this.kind,
    required this.storyId,
    required this.previewUrl,
    required this.payload,
  });

  final String kind;
  final String storyId;
  final String previewUrl;
  final String payload;
}

class _StoryLinkedChatBubble extends StatelessWidget {
  const _StoryLinkedChatBubble({
    required this.message,
    required this.isMe,
    required this.onOpenStory,
  });

  final _StoryDirectMessage message;
  final bool isMe;
  final VoidCallback onOpenStory;

  @override
  Widget build(BuildContext context) {
    final textColor = isMe ? Colors.white : Colors.black87;
    final title = message.kind == 'reaction'
        ? 'Реакция на сторис: ${message.payload}'
        : 'Ответ на сторис: ${message.payload}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.previewUrl.isNotEmpty)
          GestureDetector(
            onTap: onOpenStory,
            child: Container(
              width: 140,
              height: 180,
              margin: const EdgeInsets.only(bottom: 6),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.black12,
              ),
              child: CachedNetworkImage(
                imageUrl: message.previewUrl,
                fit: BoxFit.cover,
                errorWidget: (_, url, error) => const Center(
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          ),
        Text(
          title,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
