import 'dart:async';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/storage/chat_list_storage.dart';
import '../../../../core/storage/chat_story_list_storage.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../widgets/city_chat_fixed_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../stories/domain/entities/story_group_entity.dart';
import '../../../stories/domain/entities/story_entity.dart';
import '../../../stories/presentation/pages/story_viewer_args.dart';
import '../widgets/chat_stories_friends_strip.dart';
import '../../data/group_chat_system_api.dart';
import '../../domain/temirtau_city_group_config.dart';
import '../chat_unread_badge_controller.dart';
import '../widgets/channel_create_wizard_sheet.dart';

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

String _normalizeForChatSearch(String? s) {
  if (s == null || s.isEmpty) return '';
  return s.toLowerCase().trim().replaceAll('ё', 'е');
}

String _normalizeChatSearchQuery(String raw) =>
    _normalizeForChatSearch(raw.trim());

/// Все непустые токены из [queryNorm] должны встречаться в [haystackNorm].
bool _haystackMatchesChatSearchQuery(String haystackNorm, String queryNorm) {
  if (queryNorm.isEmpty) return true;
  if (haystackNorm.isEmpty) return false;
  for (final tok in queryNorm.split(RegExp(r'\s+')).where((x) => x.isNotEmpty)) {
    if (!haystackNorm.contains(tok)) return false;
  }
  return true;
}

/// Убираем символы шаблона LIKE и ограничиваем длину (PostgREST ilike).
String _sanitizeIlikeUserInput(String raw) {
  var s = raw.trim().replaceAll('%', '').replaceAll('_', '');
  if (s.length > 48) s = s.substring(0, 48);
  return s;
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

/// Превью последнего сообщения в списке диалогов (учитывает message_type).
String _dmThreadPreviewText(Map<String, dynamic> json) {
  final type = json['message_type'] as String? ?? 'text';
  final text = json['text'] as String? ?? '';
  switch (type) {
    case 'image':
      return '📷 Фото';
    case 'gif':
      return 'GIF';
    case 'audio':
      return '🎤 Голосовое сообщение';
    case 'video_circle':
      return '📹 Видеосообщение';
    case 'file':
      final n = (json['file_name'] as String?)?.trim();
      if (n != null && n.isNotEmpty) return '📎 $n';
      return '📎 Файл';
    case 'event':
      return '📅 Мероприятие';
    case 'location':
      return '📍 Геолокация';
    default:
      return _displayTextForDirectThread(text);
  }
}

/// Сборка списка диалогов из сырых сообщений (без Supabase/SharedPreferences).
List<_ChatThread> _computeDirectThreadsFromRows(
  _DirectThreadsComputeArgs args,
) {
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
    final text = _dmThreadPreviewText(json);
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
    final lastRead = lastReadStr != null
        ? DateTime.tryParse(lastReadStr)
        : null;

    final prevIncoming = lastIncomingByPeer[peerId];
    if (prevIncoming == null || createdAt.isAfter(prevIncoming)) {
      lastIncomingByPeer[peerId] = createdAt;
    }
    if (lastRead == null || createdAt.isAfter(lastRead)) {
      unreadByPeer[peerId] = (unreadByPeer[peerId] ?? 0) + 1;
    }
  }

  if (threadsByPeer.isEmpty) return const [];

  return threadsByPeer.entries
      .map((e) {
        final peerId = e.key;
        final t = e.value;
        return t.copyWith(
          unreadCount: unreadByPeer[peerId] ?? 0,
          lastIncomingAt: lastIncomingByPeer[peerId],
        );
      })
      .toList(growable: false);
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
  /// Короткий кэш первого кадра списка чатов — меньше «мигания» при возврате на вкладку.
  static const Duration _warmCacheTtl = Duration(seconds: 120);

  /// Не дергать полный resolve Temirtau чаще (меньше запросов при каждом refresh).
  static const Duration _temirtauIdCacheTtl = Duration(minutes: 4);
  static _ChatsWarmCache? _warmCache;
  static _TemirtauIdCache? _temirtauIdCache;

  static void _clearChatsTransientCaches() {
    _warmCache = null;
    _temirtauIdCache = null;
  }

  late final SupabaseClient _client;
  String _sessionUserId = '';
  late final ChatListStorage _chatStorage;
  late final ChatStoryListStorage _storySeenStorage;
  late Future<_ChatsPageData> _pageFuture;

  /// Последний загруженный список чатов — для merge со сторис без повторного await.
  List<_ChatThread> _cachedThreadsForStories = const [];

  /// Последний набор `following_id` — подмешивается в отложенный merge сторис.
  Set<String> _lastFollowingPeerIds = const {};

  /// Поколение фоновой загрузки сторис (отмена устаревших результатов при быстром refresh).
  int _storiesLoadGeneration = 0;

  static const int _kGlobalChatSearchLimit = 40;
  static const Duration _kRemoteSearchDebounce = Duration(milliseconds: 460);
  static const Duration _kBlockedIdsCacheTtl = Duration(seconds: 75);

  /// Поиск без setState всей стран при каждом символе.
  final ValueNotifier<String> _searchQueryListenable = ValueNotifier<String>(
    '',
  );
  /// Результаты глобального поиска — только список чатов пересобирается (без лишних rebuild всей страницы).
  final ValueNotifier<List<_ChatThread>> _remoteSearchNotifier =
      ValueNotifier<List<_ChatThread>>(const []);
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchRemoteDebounce;
  int _searchRemoteGen = 0;
  Set<String>? _blockedPeerIdsCache;
  DateTime? _blockedPeerIdsCacheAt;
  bool _threadSelectionMode = false;
  final Set<String> _selectedThreadKeys = <String>{};

  /// Оптимистичные значения только для [_optimisticMyStoryNoteOwnerId] — иначе после смены аккаунта
  /// чужая заметка попадала бы в полоску сторис под новым user id.
  String? _optimisticMyStoryNote;
  String? _optimisticMyStoryLocation;
  String? _optimisticMyStoryNoteOwnerId;

  @override
  void initState() {
    super.initState();
    _client = Supabase.instance.client;
    final authState = context.read<AuthBloc>().state;
    _chatStorage = context.read<ChatListStorage>();
    _storySeenStorage = context.read<ChatStoryListStorage>();
    if (authState is! AuthAuthenticated) {
      _pageFuture = Future.value(
        const _ChatsPageData(
          threads: [],
          visibleStoryGroups: [],
          newStoriesByUserId: <String, bool>{},
          storyNotesByUserId: <String, String>{},
          storyLocationsByUserId: <String, String>{},
        ),
      );
      return;
    }
    _sessionUserId = authState.user.id;
    final cache = _warmCache;
    final canUseCache =
        cache != null &&
        cache.userId == _sessionUserId &&
        DateTime.now().difference(cache.createdAt) <= _warmCacheTtl;
    // Start loading after first frame to keep navigation into chats responsive.
    _pageFuture = Future.value(
      canUseCache
          ? cache.data
          : const _ChatsPageData(
              threads: [],
              visibleStoryGroups: [],
              newStoriesByUserId: <String, bool>{},
              storyNotesByUserId: <String, String>{},
              storyLocationsByUserId: <String, String>{},
            ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cache = _warmCache;
      final sameUser = cache != null && cache.userId == _sessionUserId;
      final veryFresh =
          sameUser &&
          DateTime.now().difference(cache.createdAt) <
              const Duration(seconds: 12);
      if (veryFresh) {
        unawaited(_reloadChatsSilentlyReplaceFuture());
        return;
      }
      setState(() {
        _pageFuture = _loadPageData();
      });
    });
  }

  /// Обновление без мигания загрузчика: текущий Future уже data из warm cache.
  Future<void> _reloadChatsSilentlyReplaceFuture() async {
    try {
      final data = await _loadPageData();
      if (!mounted) return;
      setState(() {
        _pageFuture = Future.value(data);
      });
    } catch (e, st) {
      debugPrint('ChatsPage._reloadChatsSilentlyReplaceFuture: $e\n$st');
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
    _searchRemoteDebounce?.cancel();
    _remoteSearchNotifier.dispose();
    _searchQueryListenable.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _sameRemoteSearchHits(List<_ChatThread> a, List<_ChatThread> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].storageKey != b[i].storageKey) return false;
    }
    return true;
  }

  void _publishRemoteSearchHits(List<_ChatThread> next) {
    final prev = _remoteSearchNotifier.value;
    if (_sameRemoteSearchHits(prev, next)) return;
    _remoteSearchNotifier.value = next;
  }

  Future<Set<String>> _blockedPeerIdsForSearch() async {
    final now = DateTime.now();
    if (_blockedPeerIdsCache != null &&
        _blockedPeerIdsCacheAt != null &&
        now.difference(_blockedPeerIdsCacheAt!) < _kBlockedIdsCacheTtl) {
      return _blockedPeerIdsCache!;
    }
    try {
      final blockedRes = await _client
          .from('blocked_users')
          .select('blocked_user_id')
          .eq('blocker_id', _sessionUserId);
      final blocked = (blockedRes as List)
          .map((e) => (e as Map)['blocked_user_id'] as String)
          .toSet();
      _blockedPeerIdsCache = blocked;
      _blockedPeerIdsCacheAt = now;
      return blocked;
    } catch (_) {
      return const {};
    }
  }

  void _onChatsSearchChanged(String v) {
    _searchQueryListenable.value = v;
    _scheduleRemoteChatsSearch(v);
  }

  void _scheduleRemoteChatsSearch(String raw) {
    _searchRemoteDebounce?.cancel();
    final safe = _sanitizeIlikeUserInput(raw);
    if (safe.length < 2) {
      _publishRemoteSearchHits(const []);
      return;
    }
    final gen = ++_searchRemoteGen;
    _searchRemoteDebounce = Timer(_kRemoteSearchDebounce, () {
      _runRemoteChatsSearch(raw, safe, gen);
    });
  }

  Future<void> _runRemoteChatsSearch(
    String raw,
    String ilikeSafe,
    int gen,
  ) async {
    if (!mounted || gen != _searchRemoteGen) return;
    if (_sessionUserId.isEmpty) return;
    final queryNorm = _normalizeChatSearchQuery(raw);
    if (queryNorm.length < 2) {
      if (mounted) _publishRemoteSearchHits(const []);
      return;
    }
    final pattern = '%$ilikeSafe%';
    try {
      final blocked = await _blockedPeerIdsForSearch();

      final usersF = _client
          .from(SupabaseConstants.usersTable)
          .select('id,name,avatar')
          .ilike('name', pattern)
          .neq('id', _sessionUserId)
          .limit(_kGlobalChatSearchLimit);

      final channelsF = _client
          .from(SupabaseConstants.userChannelsTable)
          .select('id,title,avatar_url')
          .ilike('title', pattern)
          .limit(_kGlobalChatSearchLimit);

      final groupsF = _client
          .from(SupabaseConstants.chatGroupsTable)
          .select('id,title,avatar_url,is_official_city_chat')
          .ilike('title', pattern)
          .limit(_kGlobalChatSearchLimit);

      final results = await Future.wait<Object?>([
        usersF,
        channelsF,
        groupsF,
      ]);
      if (!mounted || gen != _searchRemoteGen) return;

      final usersRows = (results[0] as List).cast<Map<String, dynamic>>();
      final channelRows = (results[1] as List).cast<Map<String, dynamic>>();
      final groupRows = (results[2] as List).cast<Map<String, dynamic>>();

      final placeholderAt = DateTime.fromMillisecondsSinceEpoch(0);
      final out = <_ChatThread>[];

      for (final row in usersRows) {
        final id = row['id'] as String?;
        if (id == null || blocked.contains(id)) continue;
        final name = (row['name'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;
        if (!_haystackMatchesChatSearchQuery(
          _normalizeForChatSearch(name),
          queryNorm,
        )) {
          continue;
        }
        out.add(
          _ChatThread(
            kind: _ChatThreadKind.direct,
            peerId: id,
            peerName: name,
            peerAvatarUrl: row['avatar'] as String?,
            lastMessageText: 'Написать',
            lastMessageAt: placeholderAt,
            lastMessageSenderId: id,
            unreadCount: 0,
            lastIncomingAt: null,
            fromGlobalSearch: true,
          ),
        );
      }

      for (final row in groupRows) {
        final id = row['id'] as String?;
        if (id == null) continue;
        final title = (row['title'] as String?)?.trim() ?? '';
        if (title.isEmpty) continue;
        if (!_haystackMatchesChatSearchQuery(
          _normalizeForChatSearch(title),
          queryNorm,
        )) {
          continue;
        }
        final isOfficial =
            (row['is_official_city_chat'] as bool?) == true ||
            TemirtauCityGroupConfig.isOfficialCityChatTitle(title);
        out.add(
          _ChatThread(
            kind: _ChatThreadKind.group,
            peerId: id,
            peerName: title,
            peerAvatarUrl: row['avatar_url'] as String?,
            lastMessageText: isOfficial
                ? TemirtauCityGroupConfig.listSubtitle
                : 'Групповой чат',
            lastMessageAt: placeholderAt,
            lastMessageSenderId: _sessionUserId,
            unreadCount: 0,
            lastIncomingAt: null,
            isTemirtauCity: isOfficial,
            fromGlobalSearch: true,
          ),
        );
      }

      for (final row in channelRows) {
        final id = row['id'] as String?;
        if (id == null) continue;
        final title = (row['title'] as String?)?.trim() ?? '';
        if (title.isEmpty) continue;
        if (!_haystackMatchesChatSearchQuery(
          _normalizeForChatSearch(title),
          queryNorm,
        )) {
          continue;
        }
        out.add(
          _ChatThread(
            kind: _ChatThreadKind.channel,
            peerId: id,
            peerName: title,
            peerAvatarUrl: row['avatar_url'] as String?,
            lastMessageText: 'Канал',
            lastMessageAt: placeholderAt,
            lastMessageSenderId: _sessionUserId,
            unreadCount: 0,
            lastIncomingAt: null,
            fromGlobalSearch: true,
          ),
        );
      }

      out.sort(
        (a, b) => a.peerName.toLowerCase().compareTo(b.peerName.toLowerCase()),
      );

      if (!mounted || gen != _searchRemoteGen) return;
      _publishRemoteSearchHits(out);
    } catch (e, st) {
      debugPrint('ChatsPage._runRemoteChatsSearch: $e\n$st');
      if (!mounted || gen != _searchRemoteGen) return;
      _publishRemoteSearchHits(const []);
    }
  }

  /// Доп. строки из поиска по БД (пользователь / канал / группа), без дубликатов с [allLoaded].
  List<_ChatThread> _mergeGlobalSearchRows(
    List<_ChatThread> allLoaded,
    List<_ChatThread> tabFiltered,
    List<_ChatThread> globalHits,
  ) {
    final existing = {for (final t in allLoaded) t.storageKey};
    final merged = [...tabFiltered];
    for (final t in globalHits) {
      if (existing.contains(t.storageKey)) continue;
      merged.add(t);
      existing.add(t.storageKey);
    }
    return merged;
  }

  void _syncChatBadge() {
    if (!mounted) return;
    context.read<ChatUnreadBadgeController>().refresh();
  }

  /// Обновление после возврата из чата без показа глобального лоадера.
  void _refreshChatsAfterPopSilent() {
    if (!mounted) return;
    _syncChatBadge();
    unawaited(_reloadChatsSilentlyReplaceFuture());
  }

  void _optimisticallyMarkThreadReadInList(_ChatThread thread) {
    unawaited(
      _pageFuture.then((data) {
        if (!mounted) return;
        final idx = data.threads.indexWhere(
          (t) => t.storageKey == thread.storageKey,
        );
        if (idx < 0) return;
        final current = data.threads[idx];
        if (current.unreadCount == 0) return;
        final updatedThreads = List<_ChatThread>.from(data.threads);
        updatedThreads[idx] = current.copyWith(unreadCount: 0);
        final updated = _ChatsPageData(
          threads: updatedThreads,
          visibleStoryGroups: data.visibleStoryGroups,
          newStoriesByUserId: data.newStoriesByUserId,
          storyNotesByUserId: data.storyNotesByUserId,
          storyLocationsByUserId: data.storyLocationsByUserId,
          followingPeerIds: data.followingPeerIds,
        );
        _cachedThreadsForStories = updatedThreads;
        setState(() {
          _pageFuture = Future.value(updated);
          _storeWarmCache(updated);
        });
      }).catchError((_) {
        // Keep navigation instant even if current pageFuture fails.
      }),
    );
  }

  void _storeWarmCache(_ChatsPageData data) {
    _warmCache = _ChatsWarmCache(
      createdAt: DateTime.now(),
      userId: _sessionUserId,
      data: _ChatsPageData(
        threads: List<_ChatThread>.from(data.threads),
        visibleStoryGroups: List<StoryGroupEntity>.from(
          data.visibleStoryGroups,
        ),
        newStoriesByUserId: Map<String, bool>.from(data.newStoriesByUserId),
        storyNotesByUserId: Map<String, String>.from(data.storyNotesByUserId),
        storyLocationsByUserId: Map<String, String>.from(
          data.storyLocationsByUserId,
        ),
        followingPeerIds: Set<String>.from(data.followingPeerIds),
      ),
    );
  }

  Future<({Map<String, String> notes, Map<String, String> locations})>
  _loadStoryNotes(Set<String> userIds) async {
    if (userIds.isEmpty) {
      return (
        notes: const <String, String>{},
        locations: const <String, String>{},
      );
    }
    try {
      final res = await _client
          .from(SupabaseConstants.userStorySettingsTable)
          .select('user_id,story_note,note_location,share_location')
          .inFilter('user_id', userIds.toList(growable: false));
      final rows = res as List<dynamic>;
      final notes = <String, String>{};
      final locations = <String, String>{};
      for (final row in rows) {
        final json = row as Map<String, dynamic>;
        final id = (json['user_id'] ?? '').toString();
        final note = (json['story_note'] ?? '').toString().trim();
        final location = (json['note_location'] ?? '').toString().trim();
        final shareLocation = json['share_location'] == true;
        if (id.isNotEmpty && note.isNotEmpty) {
          notes[id] = note;
        }
        if (id.isNotEmpty && shareLocation && location.isNotEmpty) {
          locations[id] = location;
        }
      }
      return (notes: notes, locations: locations);
    } catch (_) {
      // If migration is not applied yet, keep chat list functional without notes.
      return (
        notes: const <String, String>{},
        locations: const <String, String>{},
      );
    }
  }

  Future<void> _showOwnStoryNoteSheet(
    String currentNote, {
    String currentLocation = '',
  }) async {
    final controller = TextEditingController(text: currentNote);
    final locationController = TextEditingController(
      text: _optimisticMyStoryLocation ?? currentLocation,
    );
    var shareLocation = (locationController.text.trim().isNotEmpty);
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final inset = MediaQuery.of(ctx).viewInsets.bottom;
        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + inset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Ваша заметка',
                    hintText: 'Напишите короткую заметку',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: shareLocation,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Показывать геопозицию'),
                  subtitle: const Text('Например: Алматы, Казахстан'),
                  onChanged: (v) => setSheetState(() => shareLocation = v),
                ),
                TextField(
                  controller: locationController,
                  enabled: shareLocation,
                  maxLength: 48,
                  decoration: const InputDecoration(
                    labelText: 'Город / локация',
                    hintText: 'Введите город',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, 'delete'),
                        child: const Text('Удалить'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, 'save'),
                        child: const Text('Сохранить'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (action == null) return;
    try {
      if (action == 'delete') {
        await _client.from(SupabaseConstants.userStorySettingsTable).upsert({
          'user_id': _sessionUserId,
          'story_note': '',
          'note_location': '',
          'share_location': false,
        }, onConflict: 'user_id');
        _optimisticMyStoryNote = '';
        _optimisticMyStoryLocation = '';
        _optimisticMyStoryNoteOwnerId = _sessionUserId;
      } else if (action == 'save') {
        await _client.from(SupabaseConstants.userStorySettingsTable).upsert({
          'user_id': _sessionUserId,
          'story_note': controller.text.trim(),
          'note_location': locationController.text.trim(),
          'share_location': shareLocation,
        }, onConflict: 'user_id');
        _optimisticMyStoryNote = controller.text.trim();
        _optimisticMyStoryLocation = shareLocation
            ? locationController.text.trim()
            : '';
        _optimisticMyStoryNoteOwnerId = _sessionUserId;
      }
      if (!mounted) return;
      setState(() {
        _pageFuture = _loadPageData();
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final isMissingRelation =
          msg.contains('user_story_settings') ||
          (msg.contains('story_note') && msg.toLowerCase().contains('column'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isMissingRelation
                ? 'Нужно выполнить миграцию user_story_settings в Supabase (SQL Editor)'
                : 'Не удалось обновить заметку: $e',
          ),
        ),
      );
    }
  }

  Future<_ChatsPageData> _loadPageData() async {
    final gen = ++_storiesLoadGeneration;

    final followingFuture = _loadFollowingPeerIds();

    final directFuture = _loadDirectThreads();
    final groupFuture = _loadGroupThreads();
    final channelFuture = _loadChannelThreads();
    final results = await Future.wait<List<_ChatThread>>([
      directFuture,
      groupFuture,
      channelFuture,
    ]);
    final threads = [...results[0], ...results[1], ...results[2]]
      ..sort((a, b) {
        final aUnread = a.unreadCount > 0;
        final bUnread = b.unreadCount > 0;
        if (aUnread != bUnread) return aUnread ? -1 : 1;
        return b.lastMessageAt.compareTo(a.lastMessageAt);
      });
    final pinnedIdx = threads.indexWhere((t) => t.isTemirtauCity);
    if (pinnedIdx > 0) {
      final pinned = threads.removeAt(pinnedIdx);
      threads.insert(0, pinned);
    }

    _cachedThreadsForStories = threads;

    final peerIds = threads
        .where((t) => t.kind == _ChatThreadKind.direct)
        .map((t) => t.peerId)
        .toSet();
    final noteUserIds = {...peerIds, _sessionUserId};
    final storyMeta = await _loadStoryNotes(noteUserIds);
    final followingPeerIds = await followingFuture;
    _lastFollowingPeerIds = followingPeerIds;
    final storyNotesByUserId = Map<String, String>.from(storyMeta.notes);
    final storyLocationsByUserId = Map<String, String>.from(
      storyMeta.locations,
    );
    if (_optimisticMyStoryNote != null &&
        _optimisticMyStoryNoteOwnerId != null &&
        _optimisticMyStoryNoteOwnerId == _sessionUserId) {
      final note = _optimisticMyStoryNote!.trim();
      if (note.isEmpty) {
        storyNotesByUserId.remove(_sessionUserId);
      } else {
        storyNotesByUserId[_sessionUserId] = note;
      }
    }
    if (_optimisticMyStoryLocation != null &&
        _optimisticMyStoryNoteOwnerId != null &&
        _optimisticMyStoryNoteOwnerId == _sessionUserId) {
      final loc = _optimisticMyStoryLocation!.trim();
      if (loc.isEmpty) {
        storyLocationsByUserId.remove(_sessionUserId);
      } else {
        storyLocationsByUserId[_sessionUserId] = loc;
      }
    }
    if (peerIds.isEmpty) {
      final data = _ChatsPageData(
        threads: threads,
        visibleStoryGroups: const [],
        newStoriesByUserId: const <String, bool>{},
        storyNotesByUserId: storyNotesByUserId,
        storyLocationsByUserId: storyLocationsByUserId,
        followingPeerIds: followingPeerIds,
      );
      _storeWarmCache(data);
      return data;
    }

    // Сначала отдаём список чатов — RefreshIndicator завершается быстро.
    // Сторис подгружаютcя отдельно (тяжёлый запрос + группировка), без блокировки свайпа.
    unawaited(
      _loadStoriesDeferred(
        peerIds,
        gen,
        storyNotesByUserId,
        storyLocationsByUserId,
      ),
    );

    final data = _ChatsPageData(
      threads: threads,
      visibleStoryGroups: const [],
      newStoriesByUserId: const <String, bool>{},
      storyNotesByUserId: storyNotesByUserId,
      storyLocationsByUserId: storyLocationsByUserId,
      followingPeerIds: followingPeerIds,
    );
    _storeWarmCache(data);
    return data;
  }

  Future<void> _loadStoriesDeferred(
    Set<String> peerIds,
    int gen,
    Map<String, String> storyNotesByUserId,
    Map<String, String> storyLocationsByUserId,
  ) async {
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
        final merged = _ChatsPageData(
          threads: _cachedThreadsForStories,
          visibleStoryGroups: visibleStoryGroups,
          newStoriesByUserId: newStoriesByUserId,
          storyNotesByUserId: storyNotesByUserId,
          storyLocationsByUserId: storyLocationsByUserId,
          followingPeerIds: Set<String>.from(_lastFollowingPeerIds),
        );
        _pageFuture = Future.value(merged);
        _storeWarmCache(merged);
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
                                    if (!mounted ||
                                        !sheetOpen ||
                                        !ctx.mounted) {
                                      return;
                                    }
                                    setStateDialog(() {
                                      suggestions = res;
                                      loading = false;
                                    });
                                  } catch (_) {
                                    if (!mounted ||
                                        !sheetOpen ||
                                        !ctx.mounted) {
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
                          : ListView.builder(
                              itemCount: suggestions.length,
                              itemBuilder: (c, i) {
                                final s = suggestions[i];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: Material(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(14),
                                    child: ListTile(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
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
                                    ),
                                  ),
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

  Future<void> _openMyChannel() async {
    try {
      final existing = await _client
          .from(SupabaseConstants.userChannelsTable)
          .select('id,title')
          .eq('owner_id', _sessionUserId)
          .maybeSingle();
      if (!mounted) return;
      if (existing != null) {
        final channelId = existing['id'] as String;
        final title = (existing['title'] as String?) ?? 'Мой канал';
        await context.push(
          '/channel/$channelId?title=${Uri.encodeComponent(title)}',
        );
        return;
      }
      final created = await ChannelCreateWizardSheet.show(
        context,
        client: _client,
        ownerId: _sessionUserId,
      );
      if (!mounted || created == null) return;
      await context.push(
        '/channel/${created.channelId}?title=${Uri.encodeComponent(created.title)}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось открыть канал: $e')));
    }
  }

  Future<void> _showCreateGroupDialog() async {
    final nameController = TextEditingController();
    final searchController = TextEditingController();
    final selectedMembers = <_UserSuggestion>[];
    var searchResults = <_UserSuggestion>[];
    var searching = false;
    var creating = false;
    Timer? debounce;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            Future<void> runSearch(String q) async {
              if (q.trim().isEmpty) {
                setModal(() { searchResults = []; searching = false; });
                return;
              }
              try {
                final res = await _client
                    .from(SupabaseConstants.usersTable)
                    .select('id,name,avatar')
                    .ilike('name', '%${_sanitizeIlikeUserInput(q)}%')
                    .neq('id', _sessionUserId)
                    .limit(12);
                final list = (res as List)
                    .map((e) => e as Map<String, dynamic>)
                    .map((e) => _UserSuggestion(
                          userId: e['id'] as String,
                          name: e['name'] as String?,
                          avatarUrl: e['avatar'] as String?,
                        ))
                    .where(
                      (u) => !selectedMembers.any((s) => s.userId == u.userId),
                    )
                    .toList();
                if (!ctx.mounted) return;
                setModal(() { searchResults = list; searching = false; });
              } catch (_) {
                if (!ctx.mounted) return;
                setModal(() => searching = false);
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: DraggableScrollableSheet(
                initialChildSize: 0.88,
                minChildSize: 0.5,
                maxChildSize: 0.95,
                expand: false,
                builder: (ctx, scrollController) {
                  return Column(
                    children: [
                      // Handle
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                        child: Row(
                          children: [
                            const Text(
                              'Новая группа',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      ),
                      // Group name
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: nameController,
                          decoration: InputDecoration(
                            hintText: 'Название группы',
                            prefixIcon: const Icon(Icons.group_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onChanged: (_) => setModal(() {}),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Selected members chips
                      if (selectedMembers.isNotEmpty) ...[
                        SizedBox(
                          height: 48,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: selectedMembers.length,
                            itemBuilder: (_, i) {
                              final m = selectedMembers[i];
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: InputChip(
                                  label: Text(
                                    m.name ?? 'Участник',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  onDeleted: () => setModal(
                                    () => selectedMembers.removeAt(i),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Member search
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            hintText: 'Добавить участников...',
                            prefixIcon: const Icon(Icons.person_add_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onChanged: (val) {
                            debounce?.cancel();
                            setModal(() => searching = true);
                            debounce = Timer(
                              const Duration(milliseconds: 400),
                              () => runSearch(val),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Results or spinner
                      Expanded(
                        child: searching
                            ? const Center(child: CircularProgressIndicator())
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: searchResults.length,
                                itemBuilder: (_, i) {
                                  final u = searchResults[i];
                                  return ListTile(
                                    leading: CachedAvatar(
                                      imageUrl: u.avatarUrl,
                                      radius: 20,
                                      fallbackText: u.name ?? '?',
                                    ),
                                    title: Text(u.name ?? 'Участник'),
                                    trailing: const Icon(
                                      Icons.add_circle_outline,
                                      color: Color(0xFF22C55E),
                                    ),
                                    onTap: () => setModal(() {
                                      selectedMembers.add(u);
                                      searchResults.removeAt(i);
                                    }),
                                  );
                                },
                              ),
                      ),
                      // Create button
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton.icon(
                            onPressed:
                                creating ||
                                    nameController.text.trim().isEmpty
                                ? null
                                : () async {
                                    setModal(() => creating = true);
                                    try {
                                      final name =
                                          nameController.text.trim();
                                      final created = await _client
                                          .from(
                                            SupabaseConstants.chatGroupsTable,
                                          )
                                          .insert({
                                            'owner_id': _sessionUserId,
                                            'title': name,
                                          })
                                          .select('id,title')
                                          .single();
                                      final gid = created['id'] as String;
                                      await GroupChatSystemApi
                                          .notifyGroupCreated(
                                        _client,
                                        groupId: gid,
                                        ownerId: _sessionUserId,
                                        title: name,
                                      );
                                      await _client
                                          .from(
                                            SupabaseConstants
                                                .chatGroupMembersTable,
                                          )
                                          .insert({
                                            'group_id': gid,
                                            'user_id': _sessionUserId,
                                          });
                                      for (final m in selectedMembers) {
                                        try {
                                          await _client
                                              .from(
                                                SupabaseConstants
                                                    .chatGroupMembersTable,
                                              )
                                              .insert({
                                                'group_id': gid,
                                                'user_id': m.userId,
                                              });
                                        } catch (_) {}
                                      }
                                      if (!ctx.mounted) return;
                                      Navigator.pop(ctx);
                                      if (!mounted) return;
                                      setState(
                                        () =>
                                            _pageFuture = _loadPageData(),
                                      );
                                      if (!context.mounted) return;
                                      await context.push(
                                        '/chat-group/$gid?name=${Uri.encodeComponent(name)}',
                                      );
                                    } catch (e) {
                                      if (!ctx.mounted) return;
                                      setModal(() => creating = false);
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('Ошибка: $e'),
                                        ),
                                      );
                                    }
                                  },
                            icon: creating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.group_add_rounded),
                            label: const Text('Создать группу'),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
    nameController.dispose();
    searchController.dispose();
    debounce?.cancel();
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
    await _openMyChannel();
  }

  Future<List<_ChatThread>> _loadDirectThreads() async {
    final res = await _client
        .from(SupabaseConstants.messagesTable)
        .select()
        .or('sender_id.eq.$_sessionUserId,receiver_id.eq.$_sessionUserId')
        .order('created_at', ascending: false)
        .limit(_kMessagesListLimit);

    final rows = (res as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return const [];

    // lastRead из SharedPreferences — только на главном изоляте.
    final peerIds = <String>{};
    for (final json in rows) {
      final senderId = json['sender_id'] as String;
      final receiverId = json['receiver_id'] as String;
      peerIds.add(senderId == _sessionUserId ? receiverId : senderId);
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
        currentUserId: _sessionUserId,
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

  Future<List<StoryGroupEntity>> _loadVisibleStoryGroups(
    Set<String> peerIds,
  ) async {
    if (peerIds.isEmpty) return const [];
    try {
      final storiesRes = await _client
          .from(SupabaseConstants.storiesTable)
          .select(
            'id,user_id,image_url,video_url,caption,created_at,expires_at',
          )
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

      return grouped.entries
          .map((e) {
            final first = e.value.first;
            return StoryGroupEntity(
              userId: e.key,
              stories: e.value,
              userName: first.userName,
              userAvatarUrl: first.userAvatarUrl,
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<_ChatThread>> _loadGroupThreads() async {
    try {
      final temirtau = await _ensureTemirtauCityGroup();

      // Load all groups where user is a member
      final membershipRes = await _client
          .from(SupabaseConstants.chatGroupMembersTable)
          .select('group_id')
          .eq('user_id', _sessionUserId);
      final memberGroupIds = (membershipRes as List)
          .map((e) => (e as Map<String, dynamic>)['group_id'] as String?)
          .whereType<String>()
          .toSet();
      memberGroupIds.add(temirtau.id);
      final groupIds = memberGroupIds.toList();

      final groupsRes = await _client
          .from(SupabaseConstants.chatGroupsTable)
          .select('id,title,avatar_url,created_at')
          .inFilter('id', groupIds);
      final groups = (groupsRes as List).cast<Map<String, dynamic>>();

      final groupMessagesRes = await _client
          .from(SupabaseConstants.chatGroupMessagesTable)
          .select('group_id,text,created_at,sender_id,kind')
          .inFilter('group_id', groupIds)
          .order('created_at', ascending: false)
          .limit(400);
      final allMessages = (groupMessagesRes as List)
          .cast<Map<String, dynamic>>();
      final latestByGroup = <String, Map<String, dynamic>>{};
      for (final m in allMessages) {
        final gid = m['group_id'] as String?;
        if (gid == null) continue;
        latestByGroup.putIfAbsent(gid, () => m);
      }

      final unreadByGroupId = <String, int>{};
      final lastIncomingByGroup = <String, DateTime?>{};
      for (final m in allMessages) {
        final kind = m['kind'] as String? ?? 'text';
        if (kind != 'text') continue;
        final gid = m['group_id'] as String?;
        if (gid == null) continue;
        final senderId = m['sender_id'] as String;
        final createdAt = DateTime.parse(m['created_at'] as String);
        if (senderId == _sessionUserId) continue;
        final prevIn = lastIncomingByGroup[gid];
        if (prevIn == null || createdAt.isAfter(prevIn)) {
          lastIncomingByGroup[gid] = createdAt;
        }
        final lr = _chatStorage.getLastReadAt(gid);
        if (lr == null || createdAt.isAfter(lr)) {
          unreadByGroupId[gid] = (unreadByGroupId[gid] ?? 0) + 1;
        }
      }

      final mapped = groups
          .map((g) {
            final id = g['id'] as String;
            final title = (g['title'] as String?) ?? 'Групповой чат';
            final latest = latestByGroup[id];
            final createdAtRaw = g['created_at'] as String?;
            final fallbackCreatedAt = createdAtRaw != null
                ? DateTime.tryParse(createdAtRaw)
                : null;
            final kind = latest?['kind'] as String? ?? 'text';
            final lastPreview =
                kind == TemirtauCityGroupConfig.messageKindCityRules
                ? 'Правила сообщества'
                : (latest?['text'] as String?) ?? 'Группа создана';
            return _ChatThread(
              kind: _ChatThreadKind.group,
              peerId: id,
              peerName: title,
              peerAvatarUrl:
                  (g['avatar_url'] as String?)?.trim().isEmpty == true
                  ? null
                  : g['avatar_url'] as String?,
              lastMessageText: lastPreview,
              lastMessageAt: latest != null
                  ? DateTime.parse(latest['created_at'] as String)
                  : (fallbackCreatedAt ?? DateTime.now()),
              lastMessageSenderId:
                  (latest?['sender_id'] as String?) ?? _sessionUserId,
              unreadCount: unreadByGroupId[id] ?? 0,
              lastIncomingAt: lastIncomingByGroup[id],
              isTemirtauCity: id == temirtau.id,
            );
          })
          .toList(growable: false);
      mapped.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
      return mapped;
    } catch (e, st) {
      debugPrint('ChatsPage._loadGroupThreads: $e\n$st');
      return const [];
    }
  }

  Future<({String id, String title})> _ensureTemirtauCityGroup() async {
    final now = DateTime.now();
    final tc = _temirtauIdCache;
    if (tc != null &&
        tc.userId == _sessionUserId &&
        now.difference(tc.at) <= _temirtauIdCacheTtl) {
      try {
        await _client.from(SupabaseConstants.chatGroupMembersTable).insert({
          'group_id': tc.id,
          'user_id': _sessionUserId,
        }, defaultToNull: false);
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow;
      }
      return (id: tc.id, title: tc.title);
    }

    final existingRes = await _client
        .from(SupabaseConstants.chatGroupsTable)
        .select('id,title')
        .eq('title', TemirtauCityGroupConfig.title)
        .order('created_at', ascending: true)
        .limit(1);
    String id;
    String title;
    if ((existingRes as List).isNotEmpty) {
      final row = Map<String, dynamic>.from(existingRes.first as Map);
      id = row['id'] as String;
      title = (row['title'] as String?) ?? TemirtauCityGroupConfig.title;
      try {
        await _client
            .from(SupabaseConstants.chatGroupsTable)
            .update({
              'description': TemirtauCityGroupConfig.communityDescription,
              'is_official_city_chat': true,
              'is_discoverable': true,
            })
            .eq('id', id);
      } catch (_) {
        // Старый проект без колонки — после миграции заработает.
      }
    } else {
      final created = await _client
          .from(SupabaseConstants.chatGroupsTable)
          .insert({
            'owner_id': _sessionUserId,
            'title': TemirtauCityGroupConfig.title,
            'description': TemirtauCityGroupConfig.communityDescription,
            'is_official_city_chat': true,
            'is_discoverable': true,
          })
          .select('id,title')
          .single();
      final row = Map<String, dynamic>.from(created);
      id = row['id'] as String;
      title = (row['title'] as String?) ?? TemirtauCityGroupConfig.title;
      await GroupChatSystemApi.notifyGroupCreated(
        _client,
        groupId: id,
        ownerId: _sessionUserId,
        title: title,
      );
      await _client.from(SupabaseConstants.chatGroupMessagesTable).insert({
        'group_id': id,
        'sender_id': _sessionUserId,
        'text': TemirtauCityGroupConfig.systemWelcomeMessage,
        'kind': 'system_created',
      });
    }
    try {
      await _client.from(SupabaseConstants.chatGroupMembersTable).insert({
        'group_id': id,
        'user_id': _sessionUserId,
      }, defaultToNull: false);
    } on PostgrestException catch (e) {
      // Already a member (unique key) is expected on repeated loads.
      if (e.code != '23505') rethrow;
    }
    _temirtauIdCache = _TemirtauIdCache(
      userId: _sessionUserId,
      id: id,
      title: title,
      at: DateTime.now(),
    );
    return (id: id, title: title);
  }

  Future<List<_ChatThread>> _loadChannelThreads() async {
    try {
      final membershipRes = await _client
          .from(SupabaseConstants.channelSubscribersTable)
          .select('channel_id')
          .eq('user_id', _sessionUserId);
      final channelIds = (membershipRes as List)
          .map((e) => (e as Map<String, dynamic>)['channel_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList(growable: false);
      if (channelIds.isEmpty) return const [];

      final channelsRes = await _client
          .from(SupabaseConstants.userChannelsTable)
          .select('id,title,avatar_url,created_at')
          .inFilter('id', channelIds);
      final channels = (channelsRes as List).cast<Map<String, dynamic>>();

      final channelMessagesRes = await _client
          .from(SupabaseConstants.channelMessagesTable)
          .select('channel_id,text,created_at,sender_id')
          .inFilter('channel_id', channelIds)
          .order('created_at', ascending: false)
          .limit(400);
      final allMessages = (channelMessagesRes as List)
          .cast<Map<String, dynamic>>();

      final latestByChannel = <String, Map<String, dynamic>>{};
      final unreadByChannel = <String, int>{};
      final lastIncomingByChannel = <String, DateTime?>{};
      for (final m in allMessages) {
        final cid = m['channel_id'] as String?;
        if (cid == null) continue;
        latestByChannel.putIfAbsent(cid, () => m);
        final senderId = m['sender_id'] as String;
        final createdAt = DateTime.parse(m['created_at'] as String);
        if (senderId == _sessionUserId) continue;
        final prevIn = lastIncomingByChannel[cid];
        if (prevIn == null || createdAt.isAfter(prevIn)) {
          lastIncomingByChannel[cid] = createdAt;
        }
        final lr = _chatStorage.getLastReadAt(cid);
        if (lr == null || createdAt.isAfter(lr)) {
          unreadByChannel[cid] = (unreadByChannel[cid] ?? 0) + 1;
        }
      }

      return channels
          .map((c) {
            final id = c['id'] as String;
            final title = (c['title'] as String?) ?? 'Канал';
            final latest = latestByChannel[id];
            final createdAtRaw = c['created_at'] as String?;
            final fallbackCreatedAt = createdAtRaw != null
                ? DateTime.tryParse(createdAtRaw)
                : null;
            return _ChatThread(
              kind: _ChatThreadKind.channel,
              peerId: id,
              peerName: title,
              peerAvatarUrl:
                  (c['avatar_url'] as String?)?.trim().isEmpty == true
                  ? null
                  : c['avatar_url'] as String?,
              lastMessageText: (latest?['text'] as String?) ?? 'Канал создан',
              lastMessageAt: latest != null
                  ? DateTime.parse(latest['created_at'] as String)
                  : (fallbackCreatedAt ?? DateTime.now()),
              lastMessageSenderId:
                  (latest?['sender_id'] as String?) ?? _sessionUserId,
              unreadCount: unreadByChannel[id] ?? 0,
              lastIncomingAt: lastIncomingByChannel[id],
            );
          })
          .toList(growable: false);
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
          .eq('blocker_id', _sessionUserId)
          .inFilter('blocked_user_id', peerIds);
      return (res as List)
          .map((e) => (e as Map)['blocked_user_id'] as String)
          .toSet();
    } catch (_) {
      return const {};
    }
  }

  Future<Set<String>> _loadFollowingPeerIds() async {
    try {
      final res = await _client
          .from(SupabaseConstants.followersTable)
          .select('following_id')
          .eq('follower_id', _sessionUserId);
      return (res as List)
          .map((e) => (e as Map)['following_id'] as String)
          .toSet();
    } catch (_) {
      return const {};
    }
  }

  /// Входящее от пользователя, на которого вы не подписаны (кандидат в «Запросы»).
  bool _isStrangerIncomingThread(_ChatThread t, Set<String> followingPeerIds) {
    if (t.kind != _ChatThreadKind.direct) return false;
    if (t.isBlocked) return false;
    if (followingPeerIds.contains(t.peerId)) return false;
    if (t.lastMessageSenderId != t.peerId) return false;
    return true;
  }

  bool _isMessageRequestRow(_ChatThread t, Set<String> followingPeerIds) {
    if (!_isStrangerIncomingThread(t, followingPeerIds)) return false;
    if (_chatStorage.isAccepted(t.peerId)) return false;
    if (_chatStorage.declinedHidesRequest(t.peerId, t.lastMessageAt)) {
      return false;
    }
    return true;
  }

  List<_ChatThread> _filterByTab(
    _ChatsPageData data,
    int tabIndex,
    String searchRaw,
  ) {
    final threads = data.threads;
    final followingPeerIds = data.followingPeerIds;
    final archived = _chatStorage.getArchivedPeerIds();
    final q = _normalizeChatSearchQuery(searchRaw);

    bool matchesSearch(_ChatThread t) {
      if (q.isEmpty) return true;
      final name = _normalizeForChatSearch(t.peerName);
      final sub = _normalizeForChatSearch(t.lastMessageText);
      return _haystackMatchesChatSearchQuery('$name $sub', q);
    }

    if (tabIndex == 0) {
      final list = threads
          .where(
            (t) =>
                (t.isTemirtauCity || !archived.contains(t.storageKey)) &&
                (!_isStrangerIncomingThread(t, followingPeerIds) ||
                    _chatStorage.isAccepted(t.peerId)) &&
                matchesSearch(t),
          )
          .toList();
      list.sort((a, b) {
        if (a.isTemirtauCity != b.isTemirtauCity) {
          return a.isTemirtauCity ? -1 : 1;
        }
        return b.lastMessageAt.compareTo(a.lastMessageAt);
      });
      return list;
    }
    if (tabIndex == 1) {
      return threads
          .where(
            (t) =>
                !t.isTemirtauCity &&
                archived.contains(t.storageKey) &&
                matchesSearch(t),
          )
          .toList();
    }
    return threads
        .where(
          (t) =>
              !archived.contains(t.storageKey) &&
              _isMessageRequestRow(t, followingPeerIds) &&
              matchesSearch(t),
        )
        .toList();
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
            .eq('sender_id', _sessionUserId)
            .eq('receiver_id', t.peerId);
        await _client
            .from(SupabaseConstants.messagesTable)
            .delete()
            .eq('sender_id', t.peerId)
            .eq('receiver_id', _sessionUserId);
      }
      await _chatStorage.clearPeerState(t.storageKey);
      _clearChatsTransientCaches();
      if (mounted) {
        setState(() {
          _pageFuture = _loadPageData();
        });
        _syncChatBadge();
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

  void _toggleThreadSelectionMode([bool? enabled]) {
    setState(() {
      _threadSelectionMode = enabled ?? !_threadSelectionMode;
      if (!_threadSelectionMode) {
        _selectedThreadKeys.clear();
      }
    });
  }

  void _toggleThreadSelection(_ChatThread t) {
    setState(() {
      if (_selectedThreadKeys.contains(t.storageKey)) {
        _selectedThreadKeys.remove(t.storageKey);
      } else {
        _selectedThreadKeys.add(t.storageKey);
      }
    });
  }

  Future<void> _deleteSelectedThreads() async {
    if (_selectedThreadKeys.isEmpty) return;
    final data = await _pageFuture;
    if (!mounted) return;
    final selected = data.threads
        .where((t) => _selectedThreadKeys.contains(t.storageKey))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить выбранные чаты?'),
        content: Text(
          'Будет удалено: ${selected.length}. Это действие нельзя отменить.',
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
    if (ok != true) return;
    for (final t in selected) {
      await _deleteThreadByKind(t);
    }
    if (!mounted) return;
    setState(() {
      _threadSelectionMode = false;
      _selectedThreadKeys.clear();
      _ChatsPageState._clearChatsTransientCaches();
      _pageFuture = _loadPageData();
    });
  }

  Future<void> _deleteThreadByKind(_ChatThread t) async {
    if (t.isTemirtauCity) return;
    if (t.kind == _ChatThreadKind.direct) {
      await _deleteChat(t);
      return;
    }
    try {
      if (t.kind == _ChatThreadKind.group) {
        await _client
            .from('chat_group_members')
            .delete()
            .eq('group_id', t.peerId)
            .eq('user_id', _sessionUserId);
      } else if (t.kind == _ChatThreadKind.channel) {
        final channel = await _client
            .from(SupabaseConstants.userChannelsTable)
            .select('id,owner_id')
            .eq('id', t.peerId)
            .maybeSingle();
        final ownerId = (channel?['owner_id'] ?? '').toString();
        if (ownerId == _sessionUserId) {
          // Owner deletes the whole channel (messages/subscribers cascade).
          await _client
              .from(SupabaseConstants.userChannelsTable)
              .delete()
              .eq('id', t.peerId)
              .eq('owner_id', _sessionUserId);
        } else {
          // Non-owner removes only own subscription.
          await _client
              .from(SupabaseConstants.channelSubscribersTable)
              .delete()
              .eq('channel_id', t.peerId)
              .eq('user_id', _sessionUserId);
        }
      }
      await _chatStorage.clearPeerState(t.storageKey);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить чат ${t.peerName}: $e')),
      );
    }
  }

  void _selectAllThreads(_ChatsPageData data) {
    setState(() {
      _selectedThreadKeys
        ..clear()
        ..addAll(
          data.threads.where((t) => !t.isTemirtauCity).map((t) => t.storageKey),
        );
    });
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

    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, curr) {
        final lostAuth =
            prev is AuthAuthenticated && curr is! AuthAuthenticated;
        final gainedAuth =
            prev is! AuthAuthenticated && curr is AuthAuthenticated;
        final switchedUser =
            prev is AuthAuthenticated &&
            curr is AuthAuthenticated &&
            prev.user.id != curr.user.id;
        return lostAuth || gainedAuth || switchedUser;
      },
      listener: (context, state) {
        _ChatsPageState._clearChatsTransientCaches();
        _searchRemoteDebounce?.cancel();
        _searchRemoteGen++;
        _blockedPeerIdsCache = null;
        _blockedPeerIdsCacheAt = null;
        _remoteSearchNotifier.value = const [];
        if (state is! AuthAuthenticated) return;
        setState(() {
          _sessionUserId = state.user.id;
          _optimisticMyStoryNote = null;
          _optimisticMyStoryLocation = null;
          _optimisticMyStoryNoteOwnerId = null;
          _pageFuture = _loadPageData();
        });
      },
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: _threadSelectionMode
                ? Text('Выбрано: ${_selectedThreadKeys.length}')
                : const Text('Мои чаты'),
            actions: [
              if (_threadSelectionMode) ...[
                FutureBuilder<_ChatsPageData>(
                  future: _pageFuture,
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    return IconButton(
                      tooltip: 'Выбрать все',
                      icon: const Icon(Icons.select_all_rounded),
                      onPressed: data == null
                          ? null
                          : () => _selectAllThreads(data),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Удалить выбранные',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _selectedThreadKeys.isEmpty
                      ? null
                      : _deleteSelectedThreads,
                ),
                IconButton(
                  tooltip: 'Закрыть выбор',
                  icon: const Icon(Icons.close),
                  onPressed: () => _toggleThreadSelectionMode(false),
                ),
              ] else ...[
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  onPressed: () => _showCreateChatDialog(),
                ),
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  onPressed: _showChatsTopMenu,
                ),
              ],
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Чаты'),
                Tab(text: 'Архив'),
                Tab(text: 'Запросы'),
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
                    storyNotesByUserId: data.storyNotesByUserId,
                    storyLocationsByUserId: data.storyLocationsByUserId,
                    currentUserId: authState.user.id,
                    currentUserAvatarUrl: authState.user.avatarUrl,
                    onOwnNoteTap: (currentNote) {
                      final uid = authState.user.id;
                      final effective =
                          (_optimisticMyStoryNoteOwnerId == uid &&
                              _optimisticMyStoryNote != null)
                          ? _optimisticMyStoryNote!
                          : currentNote;
                      final location =
                          (_optimisticMyStoryNoteOwnerId == uid &&
                              _optimisticMyStoryLocation != null)
                          ? _optimisticMyStoryLocation!
                          : (data.storyLocationsByUserId[uid] ?? '');
                      _showOwnStoryNoteSheet(
                        effective,
                        currentLocation: location,
                      );
                    },
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
                      onChanged: _onChatsSearchChanged,
                      decoration: InputDecoration(
                        hintText:
                            'Имя, чат, канал или текст в последнем сообщении',
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
                    child: ValueListenableBuilder<String>(
                      valueListenable: _searchQueryListenable,
                      builder: (context, searchRaw, _) {
                        return ValueListenableBuilder<List<_ChatThread>>(
                          valueListenable: _remoteSearchNotifier,
                          builder: (context, remoteHits, _) {
                            return TabBarView(
                              children: [0, 1, 2].map((tabIndex) {
                                var threads = _filterByTab(
                                  data,
                                  tabIndex,
                                  searchRaw,
                                );
                                if (tabIndex == 0 &&
                                    searchRaw.trim().isNotEmpty) {
                                  threads = _mergeGlobalSearchRows(
                                    data.threads,
                                    threads,
                                    remoteHits,
                                  );
                                }
                                if (threads.isEmpty) {
                                  return Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
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
                                              : tabIndex == 1
                                                  ? 'В архиве пусто'
                                                  : 'Нет запросов на сообщения',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return _buildThreadList(
                                  context,
                                  threads,
                                  requestsTab: tabIndex == 2,
                                );
                              }).toList(),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          floatingActionButton: _threadSelectionMode
              ? null
              : FloatingActionButton(
                  heroTag: 'shell_chats_fab_create_group',
                  onPressed: _showCreateGroupDialog,
                  tooltip: 'Создать группу',
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.group_add_rounded),
                ),
        ),
      ),
    );
  }

  Future<void> _openChat(_ChatThread t) async {
    if (t.kind == _ChatThreadKind.channel) {
      _optimisticallyMarkThreadReadInList(t);
      await context.push(
        '/channel/${t.peerId}?title=${Uri.encodeComponent(t.peerName)}',
      );
      _refreshChatsAfterPopSilent();
      return;
    }

    if (t.kind == _ChatThreadKind.group) {
      _optimisticallyMarkThreadReadInList(t);
      final city = t.isTemirtauCity ? '&city=1' : '';
      await context.push(
        '/chat-group/${t.peerId}?name=${Uri.encodeComponent(t.peerName)}$city',
      );
      _refreshChatsAfterPopSilent();
      return;
    }

    final chatsData = await _pageFuture;
    if (!mounted) return;
    final followingPeerIds = chatsData.followingPeerIds;
    // Подписки (ваши «друзья» в ленте): без диалога «принять» при каждом новом сообщении.
    if (followingPeerIds.contains(t.peerId)) {
      await _chatStorage.setAccepted(t.peerId, true);
    }
    final suppressFirstMessageDialog = _isMessageRequestRow(
      t,
      followingPeerIds,
    );

    final isUnread = t.unreadCount > 0;
    final lastIncoming = t.lastIncomingAt;
    final lastDialog = _chatStorage.getLastDialogShownAt(t.peerId);
    final alreadyAccepted = _chatStorage.isAccepted(t.peerId);
    final isFollowingPeer = followingPeerIds.contains(t.peerId);
    final shouldShowDialog =
        isUnread &&
        !alreadyAccepted &&
        !suppressFirstMessageDialog &&
        !isFollowingPeer &&
        lastIncoming != null &&
        (lastDialog == null || lastIncoming.isAfter(lastDialog));

    if (shouldShowDialog) {
      if (!mounted) return;
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
        _optimisticallyMarkThreadReadInList(t);
      }
      if (!mounted) return;
      await context.push(
        '/chat/${t.peerId}?name=${Uri.encodeComponent(t.peerName)}&markRead=${accept == true ? '1' : '0'}',
      );
    } else {
      _optimisticallyMarkThreadReadInList(t);
      if (!mounted) return;
      await context.push(
        '/chat/${t.peerId}?name=${Uri.encodeComponent(t.peerName)}',
      );
    }
    _refreshChatsAfterPopSilent();
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
    _syncChatBadge();
  }

  Future<void> _setThreadArchived(_ChatThread t, bool archived) async {
    if (t.isTemirtauCity) return;
    await _chatStorage.setArchived(t.storageKey, archived);
    if (!mounted) return;
    setState(() {
      _pageFuture = _loadPageData();
    });
    _syncChatBadge();
  }

  Future<void> _acceptMessageRequest(_ChatThread t) async {
    await _chatStorage.setDeclined(t.peerId, false);
    await _chatStorage.setAccepted(t.peerId, true);
    final at = (t.lastIncomingAt ?? t.lastMessageAt).add(
      const Duration(milliseconds: 1),
    );
    await _chatStorage.setLastReadAt(t.peerId, at);
    if (!mounted) return;
    setState(() {
      _pageFuture = _loadPageData();
    });
    _syncChatBadge();
  }

  Future<void> _declineMessageRequest(_ChatThread t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Отклонить запрос?'),
        content: const Text(
          'Чат скроется из запросов. Когда придёт новое сообщение, запрос снова появится здесь.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Отклонить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _chatStorage.setDeclined(
      t.peerId,
      true,
      lastMessageEpochMs: t.lastMessageAt.millisecondsSinceEpoch,
    );
    if (!mounted) return;
    setState(() {
      _pageFuture = _loadPageData();
    });
    _syncChatBadge();
  }

  Widget _buildThreadList(
    BuildContext context,
    List<_ChatThread> threads, {
    bool requestsTab = false,
  }) {
    // Build sectioned list items
    final items = <_ChatListEntry>[];
    if (requestsTab) {
      for (final t in threads) { items.add(_ChatListEntry.thread(t)); }
    } else {
      final unreadDMs = threads
          .where(
            (t) =>
                t.kind == _ChatThreadKind.direct &&
                t.unreadCount > 0 &&
                !t.fromGlobalSearch,
          )
          .toList();
      final groups = threads
          .where(
            (t) =>
                (t.kind == _ChatThreadKind.group ||
                    t.kind == _ChatThreadKind.channel) &&
                !t.fromGlobalSearch,
          )
          .toList();
      final readDMs = threads
          .where(
            (t) =>
                t.kind == _ChatThreadKind.direct &&
                t.unreadCount == 0 &&
                !t.fromGlobalSearch,
          )
          .toList();
      final searchResults =
          threads.where((t) => t.fromGlobalSearch).toList();

      if (unreadDMs.isNotEmpty) {
        items.add(
          _ChatListEntry.header('Непрочитанные', const Color(0xFFEF4444)),
        );
        for (final t in unreadDMs) { items.add(_ChatListEntry.thread(t)); }
      }
      if (groups.isNotEmpty) {
        items.add(
          _ChatListEntry.headerWithAdd(
            'Группы и каналы',
            const Color(0xFFF59E0B),
            _showCreateGroupDialog,
          ),
        );
        for (final t in groups) { items.add(_ChatListEntry.thread(t)); }
      }
      if (readDMs.isNotEmpty) {
        items.add(
          _ChatListEntry.header('Диалоги', const Color(0xFF22C55E)),
        );
        for (final t in readDMs) { items.add(_ChatListEntry.thread(t)); }
      }
      if (searchResults.isNotEmpty) {
        items.add(
          _ChatListEntry.header('Результаты поиска', Colors.grey),
        );
        for (final t in searchResults) { items.add(_ChatListEntry.thread(t)); }
      }
    }

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
        if (mounted) _syncChatBadge();
      },
      child: RepaintBoundary(
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            if (item.isHeader) {
              return _SectionHeader(
                title: item.headerTitle!,
                color: item.headerColor!,
                onAdd: item.onAdd,
              );
            }
            final t = item.thread!;
            final isUnread = t.unreadCount > 0;
            final isOnline = _isProbablyOnline(t);
            return Padding(
              padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
              child: (t.isTemirtauCity ||
                      _threadSelectionMode ||
                      t.fromGlobalSearch
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _buildThreadTile(
                        context,
                        t,
                        isUnread,
                        isOnline,
                        showRequestActions: requestsTab,
                      ),
                    )
                  : Dismissible(
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
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _buildThreadTile(
                          context,
                          t,
                          isUnread,
                          isOnline,
                          showRequestActions: requestsTab,
                        ),
                      ),
                    )),
            );
          },
        ),
      ),
    );
  }

  Widget _buildThreadTile(
    BuildContext context,
    _ChatThread t,
    bool isUnread,
    bool isOnline, {
    bool showRequestActions = false,
  }) {
    final isSelected = _selectedThreadKeys.contains(t.storageKey);
    final accentColor = _accentColorFor(t);
    final bgColor = _bgColorFor(t);
    return Container(
      decoration: BoxDecoration(
        border: t.isTemirtauCity
            ? Border.all(color: const Color(0xFF0EA5E9), width: 1.1)
            : isSelected
            ? Border.all(color: const Color(0xFF2563EB), width: 1.4)
            : Border(
                left: BorderSide(color: accentColor, width: 3.5),
              ),
        color: t.isTemirtauCity
            ? const Color(0xFFF0F9FF)
            : isSelected
            ? const Color(0x1A2563EB)
            : bgColor,
      ),
      child: ListTile(
        shape: const RoundedRectangleBorder(),
        minVerticalPadding: 10,
        leading: SizedBox(
          width: 52,
          height: 52,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                t.isTemirtauCity
                    ? const CityChatFixedAvatar(radius: 26)
                    : CachedAvatar(
                        imageUrl: t.peerAvatarUrl,
                        radius: 26,
                        fallbackText: t.peerName,
                      ),
                if (isOnline)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                t.peerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: -0.1,
                  color: t.isTemirtauCity ? const Color(0xFF0C4A6E) : null,
                ),
              ),
            ),
            if (t.isTemirtauCity) ...[
              const SizedBox(width: 8),
              const _CityListBadge(),
            ],
          ],
        ),
        subtitle: Text(
          t.lastMessageText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: t.isTemirtauCity
                ? const Color(0xFF0369A1)
                : Colors.grey.shade600,
            fontWeight: isUnread ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
        trailing: showRequestActions
            ? SizedBox(
                width: 168,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _timeAgo(t.lastMessageAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isUnread
                            ? const Color(0xFF2563EB)
                            : Colors.grey.shade500,
                        fontWeight: isUnread
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 0,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _acceptMessageRequest(t),
                          child: const Text('Принять'),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _declineMessageRequest(t),
                          child: const Text('Отклонить'),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            : SizedBox(
                width: 54,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!t.fromGlobalSearch)
                      Text(
                        _timeAgo(t.lastMessageAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isUnread
                              ? const Color(0xFF2563EB)
                              : Colors.grey.shade500,
                          fontWeight: isUnread
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      )
                    else
                      Text(
                        'поиск',
                        maxLines: 1,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                        ),
                      ),
                    const SizedBox(height: 6),
                    if (isUnread)
                      if (t.unreadCount > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${t.unreadCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2563EB),
                            shape: BoxShape.circle,
                          ),
                        )
                    else
                      const SizedBox(height: 9),
                  ],
                ),
              ),
        onTap: () {
          if (_threadSelectionMode) {
            if (t.isTemirtauCity) return;
            _toggleThreadSelection(t);
            return;
          }
          _openChat(t);
        },
        onLongPress: () {
          if (t.isTemirtauCity) return;
          if (!_threadSelectionMode) {
            _toggleThreadSelectionMode(true);
          }
          _toggleThreadSelection(t);
        },
      ),
    );
  }

  bool _isProbablyOnline(_ChatThread t) {
    if (t.kind != _ChatThreadKind.direct) return false;
    final diff = DateTime.now().difference(t.lastMessageAt);
    return diff.inMinutes <= 5;
  }

  Color _accentColorFor(_ChatThread t) {
    if (t.isTemirtauCity) return const Color(0xFF0EA5E9);
    if (t.kind == _ChatThreadKind.group ||
        t.kind == _ChatThreadKind.channel) {
      return const Color(0xFFF59E0B);
    }
    return t.unreadCount > 0
        ? const Color(0xFFEF4444)
        : const Color(0xFF22C55E);
  }

  Color _bgColorFor(_ChatThread t) {
    if (t.isTemirtauCity) return const Color(0xFFF0F9FF);
    if (t.kind == _ChatThreadKind.group ||
        t.kind == _ChatThreadKind.channel) {
      return const Color(0xFFFFFBEB);
    }
    if (t.unreadCount > 0) return const Color(0xFFFFF5F5);
    return const Color(0xFFF0FDF4);
  }
}

/// Бейдж официального городского чата в списке диалогов.
class _CityListBadge extends StatelessWidget {
  const _CityListBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF0284C7), Color(0xFF0EA5E9)],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF0EA5E9).withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Text(
        'CITY',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
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
    this.isTemirtauCity = false,
    this.fromGlobalSearch = false,
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
  final bool isTemirtauCity;
  /// Строка из отложенного поиска по БД — без свайпов «архив», время в списке скрыто.
  final bool fromGlobalSearch;
  String get storageKey => '${kind.name}:$peerId';

  _ChatThread copyWith({
    _ChatThreadKind? kind,
    String? peerName,
    String? peerAvatarUrl,
    int? unreadCount,
    DateTime? lastIncomingAt,
    bool? isBlocked,
    bool? isTemirtauCity,
    bool? fromGlobalSearch,
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
      isTemirtauCity: isTemirtauCity ?? this.isTemirtauCity,
      fromGlobalSearch: fromGlobalSearch ?? this.fromGlobalSearch,
    );
  }
}

enum _ChatThreadKind { direct, group, channel }

class _ChatsPageData {
  const _ChatsPageData({
    required this.threads,
    required this.visibleStoryGroups,
    required this.newStoriesByUserId,
    required this.storyNotesByUserId,
    required this.storyLocationsByUserId,
    this.followingPeerIds = const {},
  });

  final List<_ChatThread> threads;
  final List<StoryGroupEntity> visibleStoryGroups;
  final Map<String, bool> newStoriesByUserId;
  final Map<String, String> storyNotesByUserId;
  final Map<String, String> storyLocationsByUserId;

  /// `following_id` для auth-пользователя — для вкладки «Запросы» (как в Instagram).
  final Set<String> followingPeerIds;
}

class _ChatsWarmCache {
  const _ChatsWarmCache({
    required this.createdAt,
    required this.userId,
    required this.data,
  });

  final DateTime createdAt;
  final String userId;
  final _ChatsPageData data;
}

class _TemirtauIdCache {
  const _TemirtauIdCache({
    required this.userId,
    required this.id,
    required this.title,
    required this.at,
  });

  final String userId;
  final String id;
  final String title;
  final DateTime at;
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

// ─────────────────────────────────────────────────────────────────
//  Chat list sectioned items
// ─────────────────────────────────────────────────────────────────

class _ChatListEntry {
  final String? headerTitle;
  final Color? headerColor;
  final VoidCallback? onAdd;
  final _ChatThread? thread;

  const _ChatListEntry._({
    this.headerTitle,
    this.headerColor,
    this.onAdd,
    this.thread,
  });

  factory _ChatListEntry.header(String title, Color color) =>
      _ChatListEntry._(headerTitle: title, headerColor: color);

  factory _ChatListEntry.headerWithAdd(
    String title,
    Color color,
    VoidCallback onAdd,
  ) => _ChatListEntry._(headerTitle: title, headerColor: color, onAdd: onAdd);

  factory _ChatListEntry.thread(_ChatThread t) =>
      _ChatListEntry._(thread: t);

  bool get isHeader => thread == null;
}

// ─────────────────────────────────────────────────────────────────
//  Section header widget
// ─────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.color,
    this.onAdd,
  });

  final String title;
  final Color color;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          if (onAdd != null)
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: color, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Создать',
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
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
