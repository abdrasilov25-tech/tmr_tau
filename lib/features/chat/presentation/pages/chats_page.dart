import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/storage/chat_list_storage.dart';
import '../../../../core/storage/chat_story_list_storage.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../stories/domain/entities/story_group_entity.dart';
import '../../../stories/domain/repositories/stories_repository.dart';
import '../../../stories/presentation/pages/story_viewer_args.dart';
import '../widgets/chat_stories_friends_strip.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  static const String _storyDmPrefix = '__story__';
  late final SupabaseClient _client;
  late final String _currentUserId;
  late final ChatListStorage _chatStorage;
  late final ChatStoryListStorage _storySeenStorage;
  late final StoriesRepository _storiesRepository;
  late Future<_ChatsPageData> _pageFuture;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    _chatStorage = context.read<ChatListStorage>();
    _storySeenStorage = context.read<ChatStoryListStorage>();
    _storiesRepository = context.read<StoriesRepository>();
    if (authState is! AuthAuthenticated) {
      _pageFuture = Future.value(
        const _ChatsPageData(
          threads: [],
          visibleStoryGroups: [],
          newStoriesByUserId: <String, bool>{},
        ),
      );
      return;
    }
    _currentUserId = authState.user.id;
    _client = Supabase.instance.client;
    _pageFuture = _loadPageData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_ChatsPageData> _loadPageData() async {
    final threads = await _loadThreads();
    final peerIds = threads.map((t) => t.peerId).toSet();
    if (peerIds.isEmpty) {
      return _ChatsPageData(
        threads: threads,
        visibleStoryGroups: const [],
        newStoriesByUserId: const <String, bool>{},
      );
    }

    final allStoriesGroups = await _storiesRepository.getStoriesGroupedByUser();
    final visibleStoryGroups = allStoriesGroups
        .where((g) => peerIds.contains(g.userId))
        .where((g) => g.stories.isNotEmpty)
        .toList(growable: false);

    final newStoriesByUserId = <String, bool>{};
    for (final g in visibleStoryGroups) {
      final latestStoryAt = g.firstStory.createdAt;
      final lastSeenAt = _storySeenStorage.getLastSeenAt(g.userId);
      newStoriesByUserId[g.userId] =
          lastSeenAt == null || latestStoryAt.isAfter(lastSeenAt);
    }

    return _ChatsPageData(
      threads: threads,
      visibleStoryGroups: visibleStoryGroups,
      newStoriesByUserId: newStoriesByUserId,
    );
  }

  Future<void> _showCreateChatDialog() async {
    final rootContext = context;
    final controller = TextEditingController();
    List<_UserSuggestion> suggestions = const [];
    bool loading = false;
    bool sheetOpen = true;
    _UserSuggestion? selectedUser;

    Timer? debounce;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            Future<List<_UserSuggestion>> _fetchSuggestions(String q) async {
              final query = q.trim();
              if (query.isEmpty) return const [];
              final res = await _client
                  .from(SupabaseConstants.usersTable)
                  .select('id,name,avatar')
                  .ilike('name', '%$query%')
                  .limit(10);
              final list = res as List<dynamic>;
              return list
                  .map((e) => e as Map<String, dynamic>)
                  .map(
                    (j) => _UserSuggestion(
                      userId: j['id'] as String,
                      name: j['name'] as String?,
                      avatarUrl: j['avatar'] as String?,
                    ),
                  )
                  .toList();
            }

            final media = MediaQuery.of(ctx);
            final desiredHeight = media.size.height * 0.75;
            final maxUsableHeight = media.size.height - media.viewInsets.bottom - 24;
            final sheetHeight = desiredHeight.clamp(280.0, maxUsableHeight);
            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: media.viewInsets.bottom + 12,
              ),
              child: SizedBox(
                height: sheetHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            decoration: const InputDecoration(
                              hintText: 'Имя пользователя',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                            onChanged: (v) {
                              if (!sheetOpen) return;
                              debounce?.cancel();
                              debounce = Timer(const Duration(milliseconds: 350), () async {
                                if (!sheetOpen || !ctx.mounted) return;
                                setStateDialog(() => loading = true);
                                try {
                                  final res = await _fetchSuggestions(v);
                                  if (!mounted || !sheetOpen || !ctx.mounted) return;
                                  setStateDialog(() {
                                    suggestions = res;
                                    loading = false;
                                  });
                                } catch (_) {
                                  if (!mounted || !sheetOpen || !ctx.mounted) return;
                                  setStateDialog(() {
                                    suggestions = const [];
                                    loading = false;
                                  });
                                }
                              });
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : suggestions.isEmpty
                              ? const Center(
                                  child: Text('Ничего не найдено'),
                                )
                              : ListView.separated(
                                  itemCount: suggestions.length,
                                  separatorBuilder: (c, i) =>
                                      const Divider(height: 1),
                                  itemBuilder: (c, i) {
                                    final s = suggestions[i];
                                    return ListTile(
                                      leading: CachedAvatar(
                                        imageUrl: s.avatarUrl,
                                        radius: 20,
                                        fallbackText: s.name ?? 'Пользователь',
                                      ),
                                      title: Text(s.name ?? 'Пользователь'),
                                      onTap: () {
                                        selectedUser = s;
                                        Navigator.pop(ctx);
                                      },
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    sheetOpen = false;
    debounce?.cancel();
    // Dispose after sheet is fully closed from widget tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    if (selectedUser == null || !rootContext.mounted) return;
    await rootContext.push(
      '/chat/${selectedUser!.userId}?name=${Uri.encodeComponent(selectedUser!.name ?? 'Пользователь')}',
    );
    if (!mounted) return;
    setState(() {
      _pageFuture = _loadPageData();
    });
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
      final text = _displayTextForThread(json['text'] as String? ?? '');
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
          lastIncomingAt: null,
        );
      }
    }

    if (threadsByPeer.isEmpty) return const [];

    final peerIds = threadsByPeer.keys.toList(growable: false);
    final blockedIds = await _loadBlockedPeerIds(peerIds);

    for (final entry in threadsByPeer.entries) {
      final peerId = entry.key;
      final t = entry.value;
      final lastRead = _chatStorage.getLastReadAt(peerId);
      int unreadCount = 0;
      DateTime? lastIncomingAt;
      for (final row in rows) {
        final json = row as Map<String, dynamic>;
        if (json['sender_id'] == peerId &&
            json['receiver_id'] == _currentUserId) {
          final msgAt = DateTime.parse(json['created_at'] as String);
          if (lastIncomingAt == null || msgAt.isAfter(lastIncomingAt)) {
            lastIncomingAt = msgAt;
          }
          if (lastRead == null || msgAt.isAfter(lastRead)) {
            unreadCount++;
          }
        }
      }
      threadsByPeer[peerId] = t.copyWith(
        unreadCount: unreadCount,
        lastIncomingAt: lastIncomingAt,
        isBlocked: blockedIds.contains(peerId),
      );
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

  String _displayTextForThread(String rawText) {
    if (!rawText.startsWith('$_storyDmPrefix|')) return rawText;
    final parts = rawText.split('|');
    if (parts.length < 5) return 'Сторис';
    String decode(String value) {
      try {
        return Uri.decodeComponent(value);
      } catch (_) {
        return value;
      }
    }
    final kind = parts[1];
    final payload = decode(parts[4]);
    if (kind == 'reaction') return 'Реакция на сторис: $payload';
    return 'Ответ на сторис: $payload';
  }

  Future<Set<String>> _loadBlockedPeerIds(List<String> peerIds) async {
    if (peerIds.isEmpty) return const {};
    try {
      final res = await _client
          .from('blocked_users')
          .select('blocked_user_id')
          .eq('blocker_id', _currentUserId)
          .inFilter('blocked_user_id', peerIds);
      return (res as List)
          .map((e) => (e as Map)['blocked_user_id'] as String)
          .toSet();
    } catch (_) {
      return const {};
    }
  }

  List<_ChatThread> _filterByTab(List<_ChatThread> threads, int tabIndex) {
    final archived = _chatStorage.getArchivedPeerIds();
    final q = _searchQuery.trim().toLowerCase();

    bool matchesSearch(_ChatThread t) {
      if (q.isEmpty) return true;
      return t.peerName.toLowerCase().contains(q);
    }

    if (tabIndex == 0) {
      return threads.where((t) => !archived.contains(t.peerId) && matchesSearch(t)).toList();
    }
    return threads.where((t) => archived.contains(t.peerId) && matchesSearch(t)).toList();
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
                if (!mounted) return;
                setState(() {
                  _pageFuture = _loadPageData();
                });
              },
            ),
            ListTile(
              leading: Icon(
                t.isBlocked ? Icons.block : Icons.block_outlined,
                color: t.isBlocked ? Colors.orange : null,
              ),
              title: Text(
                t.isBlocked ? 'Разблокировать' : 'Заблокировать',
                style: t.isBlocked
                    ? const TextStyle(color: Colors.orange)
                    : null,
              ),
              onTap: () async {
                Navigator.pop(ctx);
                if (t.isBlocked) {
                  await _unblockPeer(t.peerId);
                } else {
                  await _blockPeer(t.peerId);
                }
                if (!mounted) return;
                setState(() {
                  _pageFuture = _loadPageData();
                });
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

  Future<void> _blockPeer(String peerId) async {
    await _client.from('blocked_users').insert({
      'blocker_id': _currentUserId,
      'blocked_user_id': peerId,
    });
  }

  Future<void> _unblockPeer(String peerId) async {
    await _client
        .from('blocked_users')
        .delete()
        .eq('blocker_id', _currentUserId)
        .eq('blocked_user_id', peerId);
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
      if (mounted) setState(() { _pageFuture = _loadPageData(); });
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
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Мои чаты'),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_outlined),
              onPressed: () => _showCreateChatDialog(),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Чаты'),
              Tab(text: 'Архив'),
            ],
          ),
        ),
        body: FutureBuilder<_ChatsPageData>(
          future: _pageFuture,
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
                        setState(() { _pageFuture = _loadPageData(); });
                      },
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              );
            }
            final data = snapshot.data;
            if (data == null) {
              return const SizedBox.shrink();
            }

            return Column(
              children: [
                ChatStoriesFriendsStrip(
                  groups: data.visibleStoryGroups,
                  newStoriesByUserId: data.newStoriesByUserId,
                  currentUserId: _currentUserId,
                  onAddStoryTap: () async {
                    await context.push('/add-story');
                    if (!mounted) return;
                    setState(() {
                      _pageFuture = _loadPageData();
                    });
                  },
                  onStoryTap: (group) async {
                    if (group.stories.isEmpty) return;
                    final latestStoryAt = group.firstStory.createdAt;
                    await _storySeenStorage.setLastSeenAt(group.userId, latestStoryAt);
                    if (!mounted) return;
                    setState(() {
                      _pageFuture = _loadPageData();
                    });
                    await context.push(
                      '/stories',
                      extra: StoryViewerArgs(groups: [group], initialGroupIndex: 0),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Поиск по пользователю',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.grey.shade900.withValues(alpha: 0.2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade700),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade700),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [0, 1].map((tabIndex) {
                      final threads = _filterByTab(data.threads, tabIndex);
                      if (threads.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 56, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                tabIndex == 0 ? 'Пока нет чатов' : 'В архиве пусто',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        );
                      }
                      return _buildThreadList(context, threads);
                    }).toList(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openChat(_ChatThread t) async {
    final isUnread = t.unreadCount > 0;
    final lastIncoming = t.lastIncomingAt;
    final lastDialog = _chatStorage.getLastDialogShownAt(t.peerId);
    final alreadyAccepted = _chatStorage.isAccepted(t.peerId);
    final shouldShowDialog = isUnread &&
        !alreadyAccepted &&
        lastIncoming != null &&
        (lastDialog == null || lastIncoming.isAfter(lastDialog));

    if (shouldShowDialog) {
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
      await _chatStorage.setLastDialogShownAt(t.peerId, lastIncoming);
      if (accept == true) {
        await _chatStorage.setAccepted(t.peerId, true);
        final at = lastIncoming.add(const Duration(milliseconds: 1));
        await _chatStorage.setLastReadAt(t.peerId, at);
      }
      await context.push(
        '/chat/${t.peerId}?name=${Uri.encodeComponent(t.peerName)}&markRead=${accept == true ? '1' : '0'}',
      );
    } else {
      await context.push('/chat/${t.peerId}?name=${Uri.encodeComponent(t.peerName)}');
    }
    if (mounted) setState(() { _pageFuture = _loadPageData(); });
  }

  Future<void> _markThreadRead(_ChatThread t) async {
    final readAt = (t.lastIncomingAt ?? t.lastMessageAt).add(const Duration(milliseconds: 1));
    await _chatStorage.setLastReadAt(t.peerId, readAt);
    if (!mounted) return;
    setState(() {
      _pageFuture = _loadPageData();
    });
  }

  Future<void> _setThreadArchived(_ChatThread t, bool archived) async {
    await _chatStorage.setArchived(t.peerId, archived);
    if (!mounted) return;
    setState(() {
      _pageFuture = _loadPageData();
    });
  }

  Widget _buildThreadList(BuildContext context, List<_ChatThread> threads) {
    return RefreshIndicator(
      onRefresh: () async {
        final f = _loadPageData();
        if (!mounted) return;
        setState(() => _pageFuture = f);
        await f;
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: threads.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final t = threads[index];
          final isUnread = t.unreadCount > 0;
          return Dismissible(
            key: ValueKey(t.peerId),
            direction: DismissDirection.horizontal,
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.startToEnd) {
                await _markThreadRead(t);
                return false;
              }
              if (direction == DismissDirection.endToStart) {
                await _setThreadArchived(t, true);
                return false;
              }
              return false;
            },
            background: _SwipeActionBackground(
              color: Colors.blue.withValues(alpha: 0.18),
              icon: Icons.mark_chat_read_outlined,
              label: 'Прочитано',
              alignRight: false,
            ),
            secondaryBackground: _SwipeActionBackground(
              color: Colors.orange.withValues(alpha: 0.18),
              icon: Icons.archive_outlined,
              label: 'В архив',
              alignRight: true,
            ),
            child: ListTile(
              leading: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: CachedAvatar(
                    imageUrl: t.peerAvatarUrl,
                    radius: 22,
                    fallbackText: t.peerName,
                  ),
                ),
              ),
              title: Text(
                t.peerName,
                style: TextStyle(
                  fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                ),
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
            ),
          );
        },
      ),
    );
  }
}

class _SwipeActionBackground extends StatelessWidget {
  const _SwipeActionBackground({
    required this.color,
    required this.icon,
    required this.label,
    required this.alignRight,
  });

  final Color color;
  final IconData icon;
  final String label;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
    required this.lastMessageSenderId,
    this.unreadCount = 0,
    this.lastIncomingAt,
    this.isBlocked = false,
  });

  final String peerId;
  final String peerName;
  final String? peerAvatarUrl;
  final String lastMessageText;
  final DateTime lastMessageAt;
  final String lastMessageSenderId;
  final int unreadCount;
  final DateTime? lastIncomingAt;
  final bool isBlocked;

  _ChatThread copyWith({
    String? peerName,
    String? peerAvatarUrl,
    int? unreadCount,
    DateTime? lastIncomingAt,
    bool? isBlocked,
  }) {
    return _ChatThread(
      peerId: peerId,
      peerName: peerName ?? this.peerName,
      peerAvatarUrl: peerAvatarUrl ?? this.peerAvatarUrl,
      lastMessageText: lastMessageText,
      lastMessageAt: lastMessageAt,
      lastMessageSenderId: lastMessageSenderId,
      unreadCount: unreadCount ?? this.unreadCount,
      lastIncomingAt: lastIncomingAt ?? this.lastIncomingAt,
      isBlocked: isBlocked ?? this.isBlocked,
    );
  }
}

class _ChatsPageData {
  const _ChatsPageData({
    required this.threads,
    required this.visibleStoryGroups,
    required this.newStoriesByUserId,
  });

  final List<_ChatThread> threads;
  final List<StoryGroupEntity> visibleStoryGroups;
  final Map<String, bool> newStoriesByUserId;
}

class _UserSuggestion {
  const _UserSuggestion({
    required this.userId,
    required this.name,
    required this.avatarUrl,
  });

  final String userId;
  final String? name;
  final String? avatarUrl;
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
