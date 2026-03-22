import 'dart:async';
import 'package:flutter/foundation.dart' show compute;
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
import '../../../stories/domain/entities/story_entity.dart';
import '../../../stories/presentation/pages/story_viewer_args.dart';
import '../widgets/chat_stories_friends_strip.dart';

/// Аргументы для [compute]: тяжёлая сборка директ-тредов в отдельном изоляте.
class _DirectThreadsComputeArgs {
  const _DirectThreadsComputeArgs({
    required this.rows,
    required this.currentUserId,
    required this.lastReadIsoByPeer,
  });

  final List<Map<String, dynamic>> rows;
  final String currentUserId;
  final Map<String, String?> lastReadIsoByPeer;
}

String _displayTextForDirectThread(String rawText) {
  const storyDmPrefix = '__story__';
  if (!rawText.startsWith('$storyDmPrefix|')) return rawText;
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

/// Сборка списка диалогов из сырых сообщений (без Supabase/SharedPreferences).
List<_ChatThread> _computeDirectThreadsFromRows(_DirectThreadsComputeArgs args) {
  final rows = args.rows;
  final currentUserId = args.currentUserId;
  final lastReadIsoByPeer = args.lastReadIsoByPeer;

  final Map<String, _ChatThread> threadsByPeer = {};
  final Map<String, int> unreadByPeer = {};
  final Map<String, DateTime?> lastIncomingByPeer = {};

  for (final json in rows) {
    final senderId = json['sender_id'] as String;
    final receiverId = json['receiver_id'] as String;
    final peerId = senderId == currentUserId ? receiverId : senderId;
    final text = _displayTextForDirectThread(json['text'] as String? ?? '');
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

    final isIncoming = senderId == peerId && receiverId == currentUserId;
    if (!isIncoming) continue;

    final lastReadStr = lastReadIsoByPeer[peerId];
    final lastRead = lastReadStr != null ? DateTime.tryParse(lastReadStr) : null;

    final prevIncoming = lastIncomingByPeer[peerId];
    if (prevIncoming == null || createdAt.isAfter(prevIncoming)) {
      lastIncomingByPeer[peerId] = createdAt;
    }
    if (lastRead == null || createdAt.isAfter(lastRead)) {
      unreadByPeer[peerId] = (unreadByPeer[peerId] ?? 0) + 1;
    }
  }

  if (threadsByPeer.isEmpty) return const [];

  return threadsByPeer.entries.map((e) {
    final peerId = e.key;
    final t = e.value;
    return t.copyWith(
      unreadCount: unreadByPeer[peerId] ?? 0,
      lastIncomingAt: lastIncomingByPeer[peerId],
    );
  }).toList(growable: false);
}

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  /// Лимит сообщений для построения списка диалогов (не вся история).
  static const int _kMessagesListLimit = 500;
  /// Лимит сторис для полосы друзей (без блокировки refresh).
  static const int _kStoriesStripLimit = 120;

  late final SupabaseClient _client;
  late final String _currentUserId;
  late final ChatListStorage _chatStorage;
  late final ChatStoryListStorage _storySeenStorage;
  late Future<_ChatsPageData> _pageFuture;

  /// Последний загруженный список чатов — для merge со сторис без повторного await.
  List<_ChatThread> _cachedThreadsForStories = const [];

  /// Поколение фоновой загрузки сторис (отмена устаревших результатов при быстром refresh).
  int _storiesLoadGeneration = 0;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    _chatStorage = context.read<ChatListStorage>();
    _storySeenStorage = context.read<ChatStoryListStorage>();
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
    final gen = ++_storiesLoadGeneration;

    final directFuture = _loadDirectThreads();
    final groupFuture = _loadGroupThreads();
    final results = await Future.wait<List<_ChatThread>>([
      directFuture,
      groupFuture,
    ]);
    final threads = [...results[0], ...results[1]]
      ..sort((a, b) {
        final aUnread = a.unreadCount > 0;
        final bUnread = b.unreadCount > 0;
        if (aUnread != bUnread) return aUnread ? -1 : 1;
        return b.lastMessageAt.compareTo(a.lastMessageAt);
      });

    _cachedThreadsForStories = threads;

    final peerIds = threads
        .where((t) => t.kind == _ChatThreadKind.direct)
        .map((t) => t.peerId)
        .toSet();
    if (peerIds.isEmpty) {
      return _ChatsPageData(
        threads: threads,
        visibleStoryGroups: const [],
        newStoriesByUserId: const <String, bool>{},
      );
    }

    // Сначала отдаём список чатов — RefreshIndicator завершается быстро.
    // Сторис подгружаютcя отдельно (тяжёлый запрос + группировка), без блокировки свайпа.
    unawaited(_loadStoriesDeferred(peerIds, gen));

    return _ChatsPageData(
      threads: threads,
      visibleStoryGroups: const [],
      newStoriesByUserId: const <String, bool>{},
    );
  }

  Future<void> _loadStoriesDeferred(Set<String> peerIds, int gen) async {
    try {
      final visibleStoryGroups = await _loadVisibleStoryGroups(peerIds);
      if (!mounted || gen != _storiesLoadGeneration) return;

      final newStoriesByUserId = <String, bool>{};
      for (final g in visibleStoryGroups) {
        final latestStoryAt = g.firstStory.createdAt;
        final lastSeenAt = _storySeenStorage.getLastSeenAt(g.userId);
        newStoriesByUserId[g.userId] =
            lastSeenAt == null || latestStoryAt.isAfter(lastSeenAt);
      }

      setState(() {
        _pageFuture = Future.value(
          _ChatsPageData(
            threads: _cachedThreadsForStories,
            visibleStoryGroups: visibleStoryGroups,
            newStoriesByUserId: newStoriesByUserId,
          ),
        );
      });
    } catch (_) {
      if (!mounted || gen != _storiesLoadGeneration) return;
    }
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
            Future<List<_UserSuggestion>> fetchSuggestions(String q) async {
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
            final maxUsableHeight =
                media.size.height - media.viewInsets.bottom - 24;
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
                              debounce = Timer(
                                const Duration(milliseconds: 350),
                                () async {
                                  if (!sheetOpen || !ctx.mounted) return;
                                  setStateDialog(() => loading = true);
                                  try {
                                    final res = await fetchSuggestions(v);
                                    if (!mounted || !sheetOpen || !ctx.mounted) {
                                      return;
                                    }
                                    setStateDialog(() {
                                      suggestions = res;
                                      loading = false;
                                    });
                                  } catch (_) {
                                    if (!mounted || !sheetOpen || !ctx.mounted) {
                                      return;
                                    }
                                    setStateDialog(() {
                                      suggestions = const [];
                                      loading = false;
                                    });
                                  }
                                },
                              );
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
                          ? const Center(child: Text('Ничего не найдено'))
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

  Future<List<_MutualUser>> _loadMutualFollowers() async {
    final myFollowingRes = await _client
        .from(SupabaseConstants.followersTable)
        .select('following_id')
        .eq('follower_id', _currentUserId);
    final myFollowersRes = await _client
        .from(SupabaseConstants.followersTable)
        .select('follower_id')
        .eq('following_id', _currentUserId);

    final followingIds = (myFollowingRes as List)
        .map((e) => (e as Map<String, dynamic>)['following_id'] as String?)
        .whereType<String>()
        .toSet();
    final followerIds = (myFollowersRes as List)
        .map((e) => (e as Map<String, dynamic>)['follower_id'] as String?)
        .whereType<String>()
        .toSet();
    final mutualIds = followingIds
        .intersection(followerIds)
        .toList(growable: false);
    if (mutualIds.isEmpty) return const [];

    final usersRes = await _client
        .from(SupabaseConstants.usersTable)
        .select('id,name,avatar')
        .inFilter('id', mutualIds)
        .order('name');
    return (usersRes as List)
        .map((e) => e as Map<String, dynamic>)
        .map(
          (j) => _MutualUser(
            id: j['id'] as String,
            name: (j['name'] as String?) ?? 'Пользователь',
            avatarUrl: j['avatar'] as String?,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _showCreateGroupChatDialog() async {
    final rootContext = context;
    try {
      final users = await _loadMutualFollowers();
      if (!mounted) return;
      if (users.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нет взаимных подписок для группового чата'),
          ),
        );
        return;
      }

      final titleController = TextEditingController();
      final selected = <String>{};
      String draftTitle = '';
      final created = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          final media = MediaQuery.of(ctx);
          return StatefulBuilder(
            builder: (ctx, setStateSheet) {
              return AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.only(
                  bottom: media.viewInsets.bottom,
                ),
                child: DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: 0.78,
                  minChildSize: 0.45,
                  maxChildSize: 0.95,
                  builder: (context, scrollController) {
                    return ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      children: [
                        TextField(
                          controller: titleController,
                          decoration: const InputDecoration(
                            labelText: 'Название группы',
                            hintText: 'Например: Друзья',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Участники (взаимные подписки)',
                          style: Theme.of(ctx).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(users.length, (i) {
                          final u = users[i];
                          final isChecked = selected.contains(u.id);
                          return Column(
                            children: [
                              CheckboxListTile(
                                value: isChecked,
                                onChanged: (v) {
                                  setStateSheet(() {
                                    if (v == true) {
                                      selected.add(u.id);
                                    } else {
                                      selected.remove(u.id);
                                    }
                                  });
                                },
                                secondary: CachedAvatar(
                                  imageUrl: u.avatarUrl,
                                  radius: 18,
                                  fallbackText: u.name,
                                ),
                                title: Text(u.name),
                                controlAffinity:
                                    ListTileControlAffinity.trailing,
                              ),
                              if (i != users.length - 1)
                                const Divider(height: 1),
                            ],
                          );
                        }),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () {
                                  draftTitle = titleController.text.trim();
                                  Navigator.pop(ctx, true);
                                },
                          child: const Text('Создать групповой чат'),
                        ),
                        TextButton(
                          onPressed: () {
                            draftTitle = titleController.text.trim();
                            Navigator.pop(ctx, false);
                          },
                          child: const Text('Отмена'),
                        ),
                        const SizedBox(height: 6),
                      ],
                    );
                  },
                ),
              );
            },
          );
        },
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        titleController.dispose();
      });
      if (created != true || !rootContext.mounted) return;
      final title = draftTitle.isEmpty ? 'Групповой чат' : draftTitle;
      final groupRes = await _client
          .from(SupabaseConstants.chatGroupsTable)
          .insert({'owner_id': _currentUserId, 'title': title})
          .select('id')
          .single();
      final groupId = groupRes['id'] as String;
      final members = <Map<String, dynamic>>[
        {'group_id': groupId, 'user_id': _currentUserId},
        ...selected.map((id) => {'group_id': groupId, 'user_id': id}),
      ];
      await _client
          .from(SupabaseConstants.chatGroupMembersTable)
          .upsert(members);

      if (!rootContext.mounted) return;
      await rootContext.push(
        '/chat-group/$groupId?name=${Uri.encodeComponent(title)}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать групповой чат: $e')),
      );
    }
  }

  Future<void> _openMyChannel() async {
    try {
      final existing = await _client
          .from(SupabaseConstants.userChannelsTable)
          .select('id,title')
          .eq('owner_id', _currentUserId)
          .maybeSingle();
      String channelId;
      String title;
      if (existing != null) {
        channelId = existing['id'] as String;
        title = (existing['title'] as String?) ?? 'Мой канал';
      } else {
        final created = await _client
            .from(SupabaseConstants.userChannelsTable)
            .insert({'owner_id': _currentUserId, 'title': 'Мой канал'})
            .select('id,title')
            .single();
        channelId = created['id'] as String;
        title = (created['title'] as String?) ?? 'Мой канал';
      }
      if (!mounted) return;
      await context.push(
        '/channel/$channelId?title=${Uri.encodeComponent(title)}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось открыть канал: $e')));
    }
  }

  Future<void> _showChatsTopMenu() async {
    final selected = await showModalBottomSheet<String>(
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
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Создать групповой чат'),
              onTap: () => Navigator.pop(ctx, 'group'),
            ),
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: const Text('Мой канал'),
              onTap: () => Navigator.pop(ctx, 'channel'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == 'group') {
      await _showCreateGroupChatDialog();
      return;
    }
    await _openMyChannel();
  }

  Future<List<_ChatThread>> _loadDirectThreads() async {
    final res = await _client
        .from(SupabaseConstants.messagesTable)
        .select()
        .or('sender_id.eq.$_currentUserId,receiver_id.eq.$_currentUserId')
        .order('created_at', ascending: false)
        .limit(_kMessagesListLimit);

    final rows = (res as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return const [];

    // lastRead из SharedPreferences — только на главном изоляте.
    final peerIds = <String>{};
    for (final json in rows) {
      final senderId = json['sender_id'] as String;
      final receiverId = json['receiver_id'] as String;
      peerIds.add(senderId == _currentUserId ? receiverId : senderId);
    }
    final lastReadIsoByPeer = <String, String?>{};
    for (final id in peerIds) {
      final r = _chatStorage.getLastReadAt(id);
      lastReadIsoByPeer[id] = r?.toIso8601String();
    }

    final partialThreads = await compute(
      _computeDirectThreadsFromRows,
      _DirectThreadsComputeArgs(
        rows: rows,
        currentUserId: _currentUserId,
        lastReadIsoByPeer: lastReadIsoByPeer,
      ),
    );
    if (partialThreads.isEmpty) return const [];

    final Map<String, _ChatThread> threadsByPeer = {
      for (final t in partialThreads) t.peerId: t,
    };

    final peerIdList = threadsByPeer.keys.toList(growable: false);
    final blockedIds = await _loadBlockedPeerIds(peerIdList);

    for (final peerId in threadsByPeer.keys.toList()) {
      final t = threadsByPeer[peerId]!;
      threadsByPeer[peerId] = t.copyWith(
        isBlocked: blockedIds.contains(peerId),
      );
    }

    try {
      final usersRes = await _client
        .from(SupabaseConstants.usersTable)
        .select('id, name, avatar')
        .inFilter('id', peerIdList);
      final users = (usersRes as List).cast<Map<String, dynamic>>();
      for (final u in users) {
        final peerId = u['id'] as String?;
        if (peerId == null) continue;
        final existing = threadsByPeer[peerId];
        if (existing == null) continue;
        final name = u['name'] as String?;
        final avatar = u['avatar'] as String?;
        threadsByPeer[peerId] = existing.copyWith(
          peerName: name?.isNotEmpty == true ? name! : existing.peerName,
          peerAvatarUrl: avatar ?? existing.peerAvatarUrl,
          unreadCount: existing.unreadCount,
        );
      }
    } catch (_) {
      // Keep fallback names and avatars.
    }

    return threadsByPeer.values.toList();
  }

  Future<List<StoryGroupEntity>> _loadVisibleStoryGroups(Set<String> peerIds) async {
    if (peerIds.isEmpty) return const [];
    try {
      final storiesRes = await _client
          .from(SupabaseConstants.storiesTable)
          .select('id,user_id,image_url,video_url,caption,created_at,expires_at')
          .inFilter('user_id', peerIds.toList(growable: false))
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false)
          .limit(_kStoriesStripLimit);
      final rows = (storiesRes as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return const [];

      final usersRes = await _client
          .from(SupabaseConstants.usersTable)
          .select('id,name,avatar')
          .inFilter('id', peerIds.toList(growable: false));
      final users = (usersRes as List).cast<Map<String, dynamic>>();
      final userMap = <String, Map<String, dynamic>>{
        for (final u in users) u['id'] as String: u,
      };

      final grouped = <String, List<StoryEntity>>{};
      for (final r in rows) {
        final userId = r['user_id'] as String?;
        if (userId == null) continue;
        final u = userMap[userId];
        final createdAtRaw = r['created_at'] as String?;
        final expiresAtRaw = r['expires_at'] as String?;
        if (createdAtRaw == null || expiresAtRaw == null) continue;
        final story = StoryEntity(
          id: r['id'] as String,
          userId: userId,
          imageUrl: (r['image_url'] as String?) ?? '',
          videoUrl: r['video_url'] as String?,
          caption: r['caption'] as String?,
          createdAt: DateTime.parse(createdAtRaw),
          expiresAt: DateTime.parse(expiresAtRaw),
          userName: u?['name'] as String?,
          userAvatarUrl: u?['avatar'] as String?,
        );
        grouped.putIfAbsent(userId, () => []).add(story);
      }

      return grouped.entries.map((e) {
        final first = e.value.first;
        return StoryGroupEntity(
          userId: e.key,
          stories: e.value,
          userName: first.userName,
          userAvatarUrl: first.userAvatarUrl,
        );
      }).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<_ChatThread>> _loadGroupThreads() async {
    try {
      final membershipRes = await _client
          .from(SupabaseConstants.chatGroupMembersTable)
          .select('group_id')
          .eq('user_id', _currentUserId);
      final groupIds = (membershipRes as List)
          .map((e) => (e as Map<String, dynamic>)['group_id'] as String?)
          .whereType<String>()
          .toList(growable: false);
      if (groupIds.isEmpty) return const [];

      final groupsRes = await _client
          .from(SupabaseConstants.chatGroupsTable)
          .select('id,title,created_at')
          .inFilter('id', groupIds);
      final groups = (groupsRes as List).cast<Map<String, dynamic>>();

      final groupMessagesRes = await _client
          .from(SupabaseConstants.chatGroupMessagesTable)
          .select('group_id,text,created_at,sender_id')
          .inFilter('group_id', groupIds)
          .order('created_at', ascending: false)
          .limit(400);
      final allMessages = (groupMessagesRes as List).cast<Map<String, dynamic>>();
      final latestByGroup = <String, Map<String, dynamic>>{};
      for (final m in allMessages) {
        final gid = m['group_id'] as String?;
        if (gid == null) continue;
        latestByGroup.putIfAbsent(gid, () => m);
      }

      return groups.map((g) {
        final id = g['id'] as String;
        final title = (g['title'] as String?) ?? 'Групповой чат';
        final latest = latestByGroup[id];
        final createdAtRaw = g['created_at'] as String?;
        final fallbackCreatedAt = createdAtRaw != null
            ? DateTime.tryParse(createdAtRaw)
            : null;
        return _ChatThread(
          kind: _ChatThreadKind.group,
          peerId: id,
          peerName: title,
          peerAvatarUrl: null,
          lastMessageText: (latest?['text'] as String?) ?? 'Группа создана',
          lastMessageAt: latest != null
              ? DateTime.parse(latest['created_at'] as String)
              : (fallbackCreatedAt ?? DateTime.now()),
          lastMessageSenderId:
              (latest?['sender_id'] as String?) ?? _currentUserId,
          unreadCount: 0,
          lastIncomingAt: null,
        );
      }).toList(growable: false);
    } catch (_) {
      return const [];
    }
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
      return threads
          .where((t) => !archived.contains(t.storageKey) && matchesSearch(t))
          .toList();
    }
    return threads
        .where((t) => archived.contains(t.storageKey) && matchesSearch(t))
        .toList();
  }

  void _showThreadMenu(BuildContext context, _ChatThread t) {
    final archived = _chatStorage.getArchivedPeerIds();
    final isArchived = archived.contains(t.storageKey);
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
              leading: Icon(
                isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              ),
              title: Text(isArchived ? 'Из архива' : 'В архив'),
              onTap: () async {
                Navigator.pop(ctx);
                await _chatStorage.setArchived(t.storageKey, !isArchived);
                if (!mounted) return;
                setState(() {
                  _pageFuture = _loadPageData();
                });
              },
            ),
            if (t.kind == _ChatThreadKind.direct) ...[
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
                title: const Text(
                  'Удалить чат',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Удалить чат?'),
                      content: Text('Переписка с ${t.peerName} будет удалена.'),
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
                  if (ok == true && mounted) await _deleteChat(t);
                },
              ),
            ],
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
      await _chatStorage.setArchived(t.storageKey, false);
      if (mounted) {
        setState(() {
          _pageFuture = _loadPageData();
        });
      }
    } catch (e) {
      debugPrint('_deleteChat error: $e');
      if (mounted) {
        final msg = e.toString();
        final isRpcMissing =
            msg.contains('function') && msg.contains('does not exist');
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
            IconButton(
              icon: const Icon(Icons.more_horiz),
              onPressed: _showChatsTopMenu,
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
                        setState(() {
                          _pageFuture = _loadPageData();
                        });
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
                  currentUserAvatarUrl: authState.user.avatarUrl,
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
                    await _storySeenStorage.setLastSeenAt(
                      group.userId,
                      latestStoryAt,
                    );
                    if (!mounted) return;
                    setState(() {
                      _pageFuture = _loadPageData();
                    });
                    if (!context.mounted) return;
                    await context.push(
                      '/stories',
                      extra: StoryViewerArgs(
                        groups: [group],
                        initialGroupIndex: 0,
                      ),
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
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 56,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                tabIndex == 0
                                    ? 'Пока нет чатов'
                                    : 'В архиве пусто',
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
    if (t.kind == _ChatThreadKind.group) {
      await context
          .push('/chat-group/${t.peerId}?name=${Uri.encodeComponent(t.peerName)}');
      if (mounted) {
        setState(() {
          _pageFuture = _loadPageData();
        });
      }
      return;
    }

    final isUnread = t.unreadCount > 0;
    final lastIncoming = t.lastIncomingAt;
    final lastDialog = _chatStorage.getLastDialogShownAt(t.peerId);
    final alreadyAccepted = _chatStorage.isAccepted(t.peerId);
    final shouldShowDialog =
        isUnread &&
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
      if (!mounted) return;
      if (accept == true) {
        await _chatStorage.setAccepted(t.peerId, true);
        final at = lastIncoming.add(const Duration(milliseconds: 1));
        await _chatStorage.setLastReadAt(t.peerId, at);
      }
      if (!mounted) return;
      await context.push(
        '/chat/${t.peerId}?name=${Uri.encodeComponent(t.peerName)}&markRead=${accept == true ? '1' : '0'}',
      );
    } else {
      await context.push(
        '/chat/${t.peerId}?name=${Uri.encodeComponent(t.peerName)}',
      );
    }
    if (mounted) {
      setState(() {
        _pageFuture = _loadPageData();
      });
    }
  }

  Future<void> _markThreadRead(_ChatThread t) async {
    final readAt = (t.lastIncomingAt ?? t.lastMessageAt).add(
      const Duration(milliseconds: 1),
    );
    await _chatStorage.setLastReadAt(t.peerId, readAt);
    if (!mounted) return;
    setState(() {
      _pageFuture = _loadPageData();
    });
  }

  Future<void> _setThreadArchived(_ChatThread t, bool archived) async {
    await _chatStorage.setArchived(t.storageKey, archived);
    if (!mounted) return;
    setState(() {
      _pageFuture = _loadPageData();
    });
  }

  Widget _buildThreadList(BuildContext context, List<_ChatThread> threads) {
    return RefreshIndicator(
      onRefresh: () async {
        final messenger = ScaffoldMessenger.of(this.context);
        final f = _loadPageData();
        if (!mounted) return;
        setState(() => _pageFuture = f);
        try {
          await f.timeout(const Duration(seconds: 12));
        } on TimeoutException {
          if (!mounted) return;
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Обновление заняло слишком много времени'),
            ),
          );
        } catch (_) {
          // Error state will be shown by FutureBuilder.
        }
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: threads.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final t = threads[index];
          final isUnread = t.unreadCount > 0;
          return Dismissible(
            key: ValueKey(t.storageKey),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
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
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
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
    this.kind = _ChatThreadKind.direct,
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

  final _ChatThreadKind kind;
  final String peerId;
  final String peerName;
  final String? peerAvatarUrl;
  final String lastMessageText;
  final DateTime lastMessageAt;
  final String lastMessageSenderId;
  final int unreadCount;
  final DateTime? lastIncomingAt;
  final bool isBlocked;
  String get storageKey => '${kind.name}:$peerId';

  _ChatThread copyWith({
    _ChatThreadKind? kind,
    String? peerName,
    String? peerAvatarUrl,
    int? unreadCount,
    DateTime? lastIncomingAt,
    bool? isBlocked,
  }) {
    return _ChatThread(
      kind: kind ?? this.kind,
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

enum _ChatThreadKind { direct, group }

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

class _MutualUser {
  const _MutualUser({
    required this.id,
    required this.name,
    required this.avatarUrl,
  });

  final String id;
  final String name;
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
