import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/storage/chat_list_storage.dart';
import '../chat_unread_badge_controller.dart';
import '../../../../core/theme/theme_decoration_helper.dart';
import '../../../../core/theme/theme_index_notifier.dart';
import '../../../../core/widgets/theme_picker_sheet.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../stories/domain/entities/story_group_entity.dart';
import '../../data/models/shared_post_message.dart';
import '../../../stories/domain/repositories/stories_repository.dart';
import '../../../stories/presentation/pages/story_viewer_args.dart';
import '../../../post/domain/repositories/post_repository.dart';

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
  final ScrollController _messagesScrollController = ScrollController();
  bool _sending = false;
  bool _showScrollToBottom = false;
  bool _showNewMessagesHint = false;
  bool _didInitialAutoScroll = false;
  int _lastMessageCount = 0;
  String? _lastLatestMessageId;
  bool _forceScrollToLatest = false;
  bool _selectionMode = false;
  final Set<String> _selectedMessageIds = <String>{};
  List<Map<String, dynamic>> _latestDialogMessages = const [];

  @override
  void initState() {
    super.initState();
    _client = Supabase.instance.client;
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _currentUserId = authState.user.id;
    }
    if (widget.markReadOnOpen) {
      context
          .read<ChatListStorage>()
          .setLastReadAt(widget.peerId, DateTime.now())
          .then((_) {
        if (!mounted) return;
        context.read<ChatUnreadBadgeController>().refresh();
      });
    }
  }

  @override
  void deactivate() {
    if (context.mounted) {
      context.read<ChatUnreadBadgeController>().refresh();
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _controller.dispose();
    _messagesScrollController.dispose();
    super.dispose();
  }

  Stream<List<Map<String, dynamic>>> _messagesStream() {
    if (_currentUserId == null) {
      return const Stream.empty();
    }
    final me = _currentUserId!;
    final peer = widget.peerId;
    final hiddenIds = context.read<ChatListStorage>().getHiddenMessageIds(peer);
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
        if (hiddenIds.isNotEmpty) {
          dialogMessages.removeWhere(
            (m) => hiddenIds.contains((m['id'] ?? '').toString()),
          );
        }

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
      // Ensure own outgoing message pins dialog to latest.
      _forceScrollToLatest = true;
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

  void _scrollToBottom({bool animated = false}) {
    if (!_messagesScrollController.hasClients) return;
    final bottom = _messagesScrollController.position.minScrollExtent;
    if (animated) {
      _messagesScrollController.animateTo(
        bottom,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _messagesScrollController.jumpTo(bottom);
    }
  }

  void _handleScroll() {
    if (!_messagesScrollController.hasClients) return;
    final position = _messagesScrollController.position;
    final distanceFromBottom = position.pixels - position.minScrollExtent;
    final shouldShow = distanceFromBottom > 160;
    final isNearBottom = distanceFromBottom < 120;
    if (shouldShow != _showScrollToBottom ||
        (isNearBottom && _showNewMessagesHint)) {
      setState(() {
        _showScrollToBottom = shouldShow;
        if (isNearBottom) {
          _showNewMessagesHint = false;
        }
      });
    }
  }

  void _openPeerProfile() {
    context.push('/profile/${widget.peerId}');
  }

  void _toggleSelectionMode([bool? enabled]) {
    setState(() {
      _selectionMode = enabled ?? !_selectionMode;
      if (!_selectionMode) {
        _selectedMessageIds.clear();
      }
    });
  }

  void _toggleMessageSelection(String messageId) {
    if (messageId.isEmpty) return;
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  Future<void> _deleteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty || _currentUserId == null) return;
    final selected = _selectedMessageIds.toList(growable: false);
    final chatStorage = context.read<ChatListStorage>();
    final unreadController = context.read<ChatUnreadBadgeController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _client
          .from(SupabaseConstants.messagesTable)
          .delete()
          .inFilter('id', selected)
          .or(
            'and(sender_id.eq.${_currentUserId!},receiver_id.eq.${widget.peerId}),'
            'and(sender_id.eq.${widget.peerId},receiver_id.eq.${_currentUserId!})',
          );
      if (!mounted) return;
      await chatStorage.clearPeerState(widget.peerId);
      setState(() {
        _selectedMessageIds.clear();
        _selectionMode = false;
      });
      unreadController.refresh();
      messenger.showSnackBar(
        const SnackBar(content: Text('Сообщения удалены навсегда')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить сообщения: $e')),
      );
    }
  }

  Future<void> _deleteAllMessagesInDialog() async {
    if (_currentUserId == null) return;
    final chatStorage = context.read<ChatListStorage>();
    final unreadController = context.read<ChatUnreadBadgeController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _client.rpc('delete_chat', params: {'peer_id': widget.peerId});
    } catch (_) {
      await _client
          .from(SupabaseConstants.messagesTable)
          .delete()
          .eq('sender_id', _currentUserId!)
          .eq('receiver_id', widget.peerId);
      await _client
          .from(SupabaseConstants.messagesTable)
          .delete()
          .eq('sender_id', widget.peerId)
          .eq('receiver_id', _currentUserId!);
    }
    if (!mounted) return;
    await chatStorage.clearPeerState(widget.peerId);
    setState(() {
      _selectedMessageIds.clear();
      _selectionMode = false;
      _didInitialAutoScroll = false;
      _showNewMessagesHint = false;
      _showScrollToBottom = false;
      _lastMessageCount = 0;
      _lastLatestMessageId = null;
    });
    unreadController.refresh();
    messenger.showSnackBar(
      const SnackBar(content: Text('Вся переписка удалена навсегда')),
    );
  }

  Future<void> _confirmDeleteSelected() async {
    if (_selectedMessageIds.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить выбранные сообщения?'),
        content: Text(
          'Будет удалено: ${_selectedMessageIds.length}. Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _deleteSelectedMessages();
    }
  }

  List<Map<String, dynamic>> _selectedMessages() {
    if (_selectedMessageIds.isEmpty || _latestDialogMessages.isEmpty) {
      return const [];
    }
    return _latestDialogMessages
        .where((m) => _selectedMessageIds.contains((m['id'] ?? '').toString()))
        .toList();
  }

  bool _canEditSelectedMessage() {
    if (_currentUserId == null) return false;
    final selected = _selectedMessages();
    if (selected.length != 1) return false;
    final m = selected.first;
    final senderId = (m['sender_id'] ?? '').toString();
    final text = (m['text'] ?? '').toString().trim();
    if (senderId != _currentUserId) return false;
    if (text.isEmpty) return false;
    if (SharedPostMessage.isSharedPost(text) || text.startsWith(_storyDmPrefix)) {
      return false;
    }
    return true;
  }

  Future<void> _editSelectedMessage() async {
    final selected = _selectedMessages();
    if (selected.length != 1 || _currentUserId == null) return;
    final message = selected.first;
    final messageId = (message['id'] ?? '').toString();
    final oldText = (message['text'] ?? '').toString();
    final controller = TextEditingController(text: oldText);
    final nextText = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Изменить сообщение'),
        content: TextField(
          controller: controller,
          minLines: 1,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Введите новый текст',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (nextText == null || nextText.isEmpty || nextText == oldText.trim()) {
      return;
    }
    try {
      await _client
          .from(SupabaseConstants.messagesTable)
          .update({'text': nextText})
          .eq('id', messageId)
          .eq('sender_id', _currentUserId!)
          .eq('receiver_id', widget.peerId);
      if (!mounted) return;
      setState(() {
        _selectionMode = false;
        _selectedMessageIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сообщение изменено')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить сообщение: $e')),
      );
    }
  }

  Future<void> _deleteSelectedForMe() async {
    if (_selectedMessageIds.isEmpty) return;
    final chatStorage = context.read<ChatListStorage>();
    final unreadController = context.read<ChatUnreadBadgeController>();
    final selected = _selectedMessageIds.toList(growable: false);
    await chatStorage.addHiddenMessageIds(widget.peerId, selected);
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
    unreadController.refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Сообщения удалены у вас')),
    );
  }

  Future<void> _showDeleteSelectedOptions() async {
    if (_selectedMessageIds.isEmpty) return;
    final selectedCount = _selectedMessageIds.length;
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text('Удалить у меня ($selectedCount)'),
              onTap: () async {
                Navigator.pop(ctx);
                await _deleteSelectedForMe();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(
                'Удалить у всех ($selectedCount)',
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await _confirmDeleteSelected();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить весь чат?'),
        content: const Text(
          'Вся переписка будет удалена навсегда и не сохранится в кэше.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Удалить всё'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _deleteAllMessagesInDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            onTap: _openPeerProfile,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(widget.peerName)),
                const SizedBox(width: 6),
                const Icon(Icons.open_in_new, size: 18),
              ],
            ),
          ),
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
              title: _selectionMode
                  ? Text('Выбрано: ${_selectedMessageIds.length}')
                  : GestureDetector(
                      onTap: _openPeerProfile,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(child: Text(widget.peerName)),
                          const SizedBox(width: 6),
                          const Icon(Icons.open_in_new, size: 18),
                        ],
                      ),
                    ),
              leading: IconButton(
                icon: Icon(_selectionMode ? Icons.close : Icons.arrow_back),
                onPressed: () {
                  if (_selectionMode) {
                    _toggleSelectionMode(false);
                    return;
                  }
                  context.pop();
                },
              ),
              actions: [
                if (_selectionMode) ...[
                  IconButton(
                    tooltip: 'Удалить выбранные',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _selectedMessageIds.isEmpty
                        ? null
                        : _showDeleteSelectedOptions,
                  ),
                  IconButton(
                    tooltip: 'Изменить',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed:
                        _canEditSelectedMessage() ? _editSelectedMessage : null,
                  ),
                  IconButton(
                    tooltip: 'Удалить все',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: _confirmDeleteAll,
                  ),
                ] else ...[
                  IconButton(
                    icon: const Icon(Icons.palette_outlined),
                    onPressed: _showThemePicker,
                  ),
                ],
              ],
            ),
            body: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _messagesStream(),
                        builder: (context, snapshot) {
                      final messages = snapshot.data ?? const [];
                      if (snapshot.connectionState ==
                              ConnectionState.waiting &&
                          messages.isEmpty) {
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
                      if (messages.isEmpty) {
                        return Center(
                          child: Text(
                            'Напишите первое сообщение',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        );
                      }
                      final me = _currentUserId;
                      _latestDialogMessages = messages;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted || !_messagesScrollController.hasClients) return;
                        final position = _messagesScrollController.position;
                        final isNearBottom =
                            (position.pixels - position.minScrollExtent) < 120;
                        final latestMessageId = messages.isNotEmpty
                            ? (messages.last['id']?.toString() ?? '')
                            : '';
                        final hasNewLatestMessage = latestMessageId.isNotEmpty &&
                            latestMessageId != _lastLatestMessageId;
                        if (!_didInitialAutoScroll) {
                          _didInitialAutoScroll = true;
                          _lastMessageCount = messages.length;
                          _lastLatestMessageId = latestMessageId;
                          _scrollToBottom();
                          return;
                        }
                        final hasNewMessages = messages.length > _lastMessageCount;
                        _lastMessageCount = messages.length;
                        _lastLatestMessageId = latestMessageId;
                        if (_forceScrollToLatest) {
                          _forceScrollToLatest = false;
                          if (_showNewMessagesHint) {
                            setState(() => _showNewMessagesHint = false);
                          }
                          _scrollToBottom();
                        } else if (isNearBottom && hasNewLatestMessage) {
                          // Keep user pinned only when they already stay at latest.
                          _scrollToBottom();
                        } else if ((hasNewMessages || hasNewLatestMessage) &&
                            !_showNewMessagesHint &&
                            !isNearBottom) {
                          setState(() => _showNewMessagesHint = true);
                        }
                      });
                      return NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          _handleScroll();
                          return false;
                        },
                        child: ListView.builder(
                          controller: _messagesScrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                          final m = messages[messages.length - 1 - index];
                          final messageId = (m['id'] ?? '').toString();
                          final senderId = m['sender_id'] as String?;
                          final text = m['text'] as String? ?? '';
                          final structured = _parseStoryDirectMessage(text);
                          final postStructured = SharedPostMessage.tryParse(text);
                          final isMe = senderId == me;
                          final isSelected =
                              messageId.isNotEmpty &&
                              _selectedMessageIds.contains(messageId);
                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: GestureDetector(
                              onLongPress: () {
                                if (!_selectionMode) {
                                  _toggleSelectionMode(true);
                                }
                                _toggleMessageSelection(messageId);
                              },
                              onTap: _selectionMode
                                  ? () => _toggleMessageSelection(messageId)
                                  : null,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Theme.of(context)
                                          .colorScheme
                                          .secondaryContainer
                                      : isMe
                                          ? Theme.of(context).colorScheme.primary
                                          : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(16),
                                  border: isSelected
                                      ? Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          width: 1.2,
                                        )
                                      : null,
                                ),
                                child: postStructured != null
                                  ? _PostLinkedChatBubble(
                                      message: postStructured,
                                      isMe: isMe,
                                      onOpenPost: _selectionMode
                                          ? () => _toggleMessageSelection(messageId)
                                          : () {
                                              context.push('/post/${postStructured.postId}');
                                            },
                                      onShare: () async {
                                        if (_selectionMode) return;
                                        await SharePlus.instance.share(
                                          ShareParams(
                                            text:
                                                'https://tmr-tau.app/post/${postStructured.postId}',
                                          ),
                                        );
                                      },
                                      onSave: () async {
                                        if (_selectionMode) return;
                                        if (_currentUserId == null) return;
                                        final postRepo =
                                            context.read<PostRepository>();
                                        final messenger =
                                            ScaffoldMessenger.of(context);
                                        try {
                                          await postRepo.toggleSave(
                                            postStructured.postId,
                                            _currentUserId!,
                                          );
                                          if (!mounted) return;
                                          messenger.showSnackBar(
                                            const SnackBar(
                                              content: Text('Публикация сохранена'),
                                            ),
                                          );
                                        } catch (_) {
                                          if (!mounted) return;
                                          messenger.showSnackBar(
                                            const SnackBar(
                                              content: Text('Не удалось сохранить публикацию'),
                                            ),
                                          );
                                        }
                                      },
                                    )
                                  : structured == null
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
                                      onOpenStory: _selectionMode
                                          ? () => _toggleMessageSelection(messageId)
                                          : () => _openStoryFromMessage(
                                              structured.storyId,
                                            ),
                                    ),
                              ),
                            ),
                          );
                          },
                        ),
                      );
                    },
                  ),
                ),
                if (!_selectionMode)
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
                Positioned(
                  right: 16,
                  bottom: 92,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: (_showScrollToBottom || _showNewMessagesHint)
                        ? Material(
                            key: ValueKey(_showNewMessagesHint),
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () {
                                _scrollToBottom(animated: true);
                                if (_showNewMessagesHint) {
                                  setState(() => _showNewMessagesHint = false);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 8,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color:
                                          Theme.of(context).colorScheme.onPrimary,
                                      size: 18,
                                    ),
                                    if (_showNewMessagesHint) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        'Новые',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
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
      if (!mounted) return;
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

class _PostLinkedChatBubble extends StatelessWidget {
  const _PostLinkedChatBubble({
    required this.message,
    required this.isMe,
    required this.onOpenPost,
    required this.onShare,
    required this.onSave,
  });

  final SharedPostMessage message;
  final bool isMe;
  final VoidCallback onOpenPost;
  final Future<void> Function() onShare;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final textColor = isMe ? Colors.white : Colors.black87;
    final hasPreview = message.imageUrl.isNotEmpty;
    final hasVideo = message.videoUrl.isNotEmpty;
    return GestureDetector(
      onTap: onOpenPost,
      child: SizedBox(
        width: 210,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasPreview)
              Container(
                width: 210,
                height: 240,
                margin: const EdgeInsets.only(bottom: 6),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.black12,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: message.imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          const Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                    if (hasVideo)
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          size: 34,
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              ),
            Text(
              message.authorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (message.caption.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                message.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textColor),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                _PostMetricChip(
                  icon: Icons.favorite_border_rounded,
                  value: message.likesCount,
                  color: textColor,
                ),
                const SizedBox(width: 10),
                _PostMetricChip(
                  icon: Icons.mode_comment_outlined,
                  value: message.commentsCount,
                  color: textColor,
                ),
                const SizedBox(width: 10),
                _PostMetricChip(
                  icon: Icons.repeat_rounded,
                  value: message.repostsCount,
                  color: textColor,
                ),
                const Spacer(),
                InkWell(
                  onTap: onShare,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.send_outlined, size: 16, color: textColor),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onSave,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.bookmark_border_rounded, size: 16, color: textColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PostMetricChip extends StatelessWidget {
  const _PostMetricChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(
          _formatCount(value),
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

String _formatCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }
  return '$value';
}
